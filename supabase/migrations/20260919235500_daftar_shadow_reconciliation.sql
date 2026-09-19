-- Shadow reconciliation for Daftar Qarz mirror mode.
-- Repairs historical zero-amount events without changing balances and blocks
-- source-of-truth cutover until every mirrored record maps to ZHIROX.

alter table public.daftar_sync_sources
  add column if not exists reconciliation_status text not null default 'pending',
  add column if not exists reconciliation_missing_contacts bigint not null default 0,
  add column if not exists reconciliation_missing_transactions bigint not null default 0,
  add column if not exists last_reconciled_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'daftar_sync_sources_reconciliation_status_check'
      and conrelid = 'public.daftar_sync_sources'::regclass
  ) then
    alter table public.daftar_sync_sources
      add constraint daftar_sync_sources_reconciliation_status_check
      check (reconciliation_status in ('pending','clean','gap'));
  end if;
end;
$$;

create table if not exists public.daftar_reconciliation_runs (
  id bigint generated always as identity primary key,
  sync_source_id uuid not null
    references public.daftar_sync_sources(id) on delete restrict,
  mirrored_contacts bigint not null,
  mirrored_transactions bigint not null,
  missing_contacts bigint not null,
  missing_transactions bigint not null,
  backfilled_zero_events integer not null default 0,
  status text not null check (status in ('clean','gap')),
  created_at timestamptz not null default now()
);

create index if not exists daftar_reconciliation_runs_source_time_idx
  on public.daftar_reconciliation_runs(sync_source_id, created_at desc);

alter table public.daftar_reconciliation_runs enable row level security;
revoke all on public.daftar_reconciliation_runs from public, anon, authenticated;
grant all on public.daftar_reconciliation_runs to service_role;
grant usage, select on sequence public.daftar_reconciliation_runs_id_seq to service_role;

create or replace function public.reconcile_daftar_account_28(p_source_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source public.daftar_sync_sources%rowtype;
  v_tx record;
  v_customer_id uuid;
  v_event_id uuid;
  v_backfilled integer := 0;
  v_mirrored_contacts bigint := 0;
  v_mirrored_transactions bigint := 0;
  v_missing_contacts bigint := 0;
  v_missing_transactions bigint := 0;
  v_status text;
begin
  select *
    into v_source
  from public.daftar_sync_sources
  where id = p_source_id
    and legacy_user_id = 28
    and source_fingerprint = 'daftar-live-account-28-v1'
    and enabled = true;

  if v_source.id is null then
    raise exception 'daftar_source_not_available' using errcode = '42501';
  end if;

  -- Historical gaps discovered by the raw mirror are zero-amount events.
  -- Backfilling them only restores audit history; it does not alter debt/payment balances.
  for v_tx in
    select
      t.source_id,
      t.payload,
      t.payload_hash,
      t.payload->>'transaction_type' as transaction_type,
      coalesce(t.payload->>'transaction_date', t.payload->>'created_at') as occurred_at,
      coalesce(t.payload->>'currency', 'IQD') as currency,
      coalesce(t.payload->>'note', '') as note,
      t.payload->>'contact_id' as contact_source_id
    from public.daftar_mirror_transactions t
    where t.sync_source_id = v_source.id
      and coalesce(nullif(t.payload->>'amount','')::numeric, 0) = 0
      and not exists (
        select 1
        from public.daftar_sync_seen z
        where z.sync_source_id = v_source.id
          and z.entity_kind = 'zero_event'
          and z.source_id = t.source_id
      )
    order by t.source_id::bigint
  loop
    select seen.target_id
      into v_customer_id
    from public.daftar_sync_seen seen
    join public.profiles p on p.id = seen.target_id
    where seen.sync_source_id = v_source.id
      and seen.entity_kind = 'customer'
      and seen.source_id = v_tx.contact_source_id
      and p.role = 'customer'
      and p.admin_id = v_source.admin_id
    limit 1;

    if v_customer_id is null then
      continue;
    end if;

    insert into public.financial_events(
      customer_id,
      event_type,
      actor_id,
      actor_name,
      actor_role,
      amount,
      remaining,
      currency,
      description,
      metadata,
      created_at
    ) values (
      v_customer_id,
      case when v_tx.transaction_type = 'PAYMENT'
        then 'payment_created' else 'debt_created' end,
      v_source.admin_id,
      'Daftar Qarz Sync',
      'admin',
      0,
      0,
      v_tx.currency,
      v_tx.note,
      jsonb_build_object(
        'legacy_zero_amount', true,
        'legacy_transaction_id', v_tx.source_id,
        'legacy_contact_id', v_tx.contact_source_id,
        'source', 'daftar_live_sync_reconcile'
      ),
      coalesce(v_tx.occurred_at::timestamptz, now())
    )
    returning id into v_event_id;

    insert into public.daftar_sync_seen(
      sync_source_id, entity_kind, source_id, target_id, payload_hash
    ) values (
      v_source.id, 'zero_event', v_tx.source_id, v_event_id, v_tx.payload_hash
    )
    on conflict (sync_source_id, entity_kind, source_id) do nothing;

    if v_tx.transaction_type = 'PAYMENT' then
      insert into public.daftar_sync_seen(
        sync_source_id, entity_kind, source_id, target_id, payload_hash
      ) values (
        v_source.id, 'payment', v_tx.source_id, v_event_id, v_tx.payload_hash
      )
      on conflict (sync_source_id, entity_kind, source_id) do nothing;
    end if;

    v_backfilled := v_backfilled + 1;
  end loop;

  select count(*)
    into v_mirrored_contacts
  from public.daftar_mirror_contacts c
  where c.sync_source_id = v_source.id;

  select count(*)
    into v_missing_contacts
  from public.daftar_mirror_contacts c
  where c.sync_source_id = v_source.id
    and not exists (
      select 1
      from public.daftar_sync_seen seen
      join public.profiles p on p.id = seen.target_id
      where seen.sync_source_id = v_source.id
        and seen.entity_kind = 'customer'
        and seen.source_id = c.source_id
        and p.role = 'customer'
        and p.admin_id = v_source.admin_id
    );

  select count(*)
    into v_mirrored_transactions
  from public.daftar_mirror_transactions t
  where t.sync_source_id = v_source.id;

  select count(*)
    into v_missing_transactions
  from public.daftar_mirror_transactions t
  where t.sync_source_id = v_source.id
    and case
      when coalesce(nullif(t.payload->>'amount','')::numeric, 0) = 0 then
        not exists (
          select 1
          from public.daftar_sync_seen z
          join public.financial_events f on f.id = z.target_id
          where z.sync_source_id = v_source.id
            and z.entity_kind = 'zero_event'
            and z.source_id = t.source_id
        )
      when t.payload->>'transaction_type' = 'LOAN' then
        not exists (
          select 1
          from public.legacy_import_links l
          join public.debts d on d.id = l.target_id
          where l.admin_id = v_source.admin_id
            and l.entity_kind = 'debt'
            and l.source_id = t.source_id
        )
      when t.payload->>'transaction_type' = 'PAYMENT' then
        not exists (
          select 1
          from public.legacy_import_links l
          join public.payments p on p.id = l.target_id
          where l.admin_id = v_source.admin_id
            and l.entity_kind = 'payment'
            and split_part(l.source_id, ':', 1) = t.source_id
        )
      else true
    end;

  v_status := case
    when v_missing_contacts = 0 and v_missing_transactions = 0
      then 'clean'
    else 'gap'
  end;

  update public.daftar_sync_sources
  set reconciliation_status = v_status,
      reconciliation_missing_contacts = v_missing_contacts,
      reconciliation_missing_transactions = v_missing_transactions,
      last_reconciled_at = now(),
      updated_at = now()
  where id = v_source.id;

  insert into public.daftar_reconciliation_runs(
    sync_source_id,
    mirrored_contacts,
    mirrored_transactions,
    missing_contacts,
    missing_transactions,
    backfilled_zero_events,
    status
  ) values (
    v_source.id,
    v_mirrored_contacts,
    v_mirrored_transactions,
    v_missing_contacts,
    v_missing_transactions,
    v_backfilled,
    v_status
  );

  return jsonb_build_object(
    'status', v_status,
    'mirrored_contacts', v_mirrored_contacts,
    'mirrored_transactions', v_mirrored_transactions,
    'missing_contacts', v_missing_contacts,
    'missing_transactions', v_missing_transactions,
    'backfilled_zero_events', v_backfilled
  );
end;
$$;

revoke all on function public.reconcile_daftar_account_28(uuid)
  from public, anon, authenticated;
grant execute on function public.reconcile_daftar_account_28(uuid)
  to service_role;

create or replace function public.get_my_daftar_mirror_status()
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_build_object(
      'sync_mode', s.sync_mode,
      'mirror_bootstrapped_at', s.mirror_bootstrapped_at,
      'mirror_last_full_at', s.mirror_last_full_at,
      'contacts_count', (
        select count(*)
        from public.daftar_mirror_contacts c
        where c.sync_source_id = s.id
      ),
      'transactions_count', (
        select count(*)
        from public.daftar_mirror_transactions t
        where t.sync_source_id = s.id
      ),
      'last_success_at', s.last_success_at,
      'health_status', s.health_status,
      'consecutive_failures', s.consecutive_failures,
      'reconciliation_status', s.reconciliation_status,
      'reconciliation_missing_contacts', s.reconciliation_missing_contacts,
      'reconciliation_missing_transactions', s.reconciliation_missing_transactions,
      'last_reconciled_at', s.last_reconciled_at,
      'cutover_ready',
        s.mirror_bootstrapped_at is not null
        and s.health_status = 'healthy'
        and s.consecutive_failures = 0
        and s.reconciliation_status = 'clean'
        and s.reconciliation_missing_contacts = 0
        and s.reconciliation_missing_transactions = 0
        and s.last_success_at is not null
        and s.last_success_at >= now() - interval '5 minutes'
    ),
    '{}'::jsonb
  )
  from public.daftar_sync_sources s
  where (select auth.uid()) is not null
    and s.admin_id = (select auth.uid())
    and s.legacy_user_id = 28
    and s.source_fingerprint = 'daftar-live-account-28-v1'
  order by s.created_at
  limit 1;
$$;

revoke all on function public.get_my_daftar_mirror_status()
  from public, anon;
grant execute on function public.get_my_daftar_mirror_status()
  to authenticated;

do $$
declare
  v_source_id uuid;
begin
  select id into v_source_id
  from public.daftar_sync_sources
  where legacy_user_id = 28
    and source_fingerprint = 'daftar-live-account-28-v1'
    and enabled = true
  limit 1;

  if v_source_id is not null then
    perform public.reconcile_daftar_account_28(v_source_id);
  end if;
end;
$$;
