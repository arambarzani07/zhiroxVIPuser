-- Deep financial cutover rehearsal for Daftar Qarz -> ZHIROX.
-- This does not change the source of truth. It proves that mirrored non-zero
-- loans/payments and zero-amount audit events are represented consistently.

create index if not exists legacy_import_links_admin_kind_source_idx
  on public.legacy_import_links(admin_id, entity_kind, source_id);

create index if not exists legacy_import_links_payment_base_idx
  on public.legacy_import_links(admin_id, split_part(source_id, ':', 1))
  where entity_kind = 'payment';

alter table public.daftar_sync_sources
  add column if not exists cutover_rehearsal_status text not null default 'pending',
  add column if not exists cutover_rehearsal_mismatches bigint not null default 0,
  add column if not exists last_cutover_rehearsal_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'daftar_sync_sources_cutover_rehearsal_status_check'
      and conrelid = 'public.daftar_sync_sources'::regclass
  ) then
    alter table public.daftar_sync_sources
      add constraint daftar_sync_sources_cutover_rehearsal_status_check
      check (cutover_rehearsal_status in ('pending','pass','fail'));
  end if;
end;
$$;

create table if not exists public.daftar_cutover_rehearsal_runs (
  id bigint generated always as identity primary key,
  sync_source_id uuid not null
    references public.daftar_sync_sources(id) on delete restrict,
  nonzero_loans bigint not null,
  missing_loans bigint not null,
  loan_target_conflicts bigint not null,
  loan_amount_mismatches bigint not null,
  loan_currency_mismatches bigint not null,
  nonzero_payments bigint not null,
  missing_payments bigint not null,
  payment_amount_mismatches bigint not null,
  payment_currency_mismatches bigint not null,
  zero_event_mismatches bigint not null,
  total_mismatches bigint not null,
  status text not null check (status in ('pass','fail')),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists daftar_cutover_rehearsal_runs_source_time_idx
  on public.daftar_cutover_rehearsal_runs(sync_source_id, created_at desc);

alter table public.daftar_cutover_rehearsal_runs enable row level security;
revoke all on public.daftar_cutover_rehearsal_runs
  from public, anon, authenticated;
grant all on public.daftar_cutover_rehearsal_runs to service_role;
grant usage, select on sequence public.daftar_cutover_rehearsal_runs_id_seq
  to service_role;

create or replace function public.run_daftar_cutover_rehearsal(p_source_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source public.daftar_sync_sources%rowtype;
  v_nonzero_loans bigint := 0;
  v_missing_loans bigint := 0;
  v_loan_target_conflicts bigint := 0;
  v_loan_amount_mismatches bigint := 0;
  v_loan_currency_mismatches bigint := 0;
  v_nonzero_payments bigint := 0;
  v_missing_payments bigint := 0;
  v_payment_amount_mismatches bigint := 0;
  v_payment_currency_mismatches bigint := 0;
  v_zero_event_mismatches bigint := 0;
  v_total_mismatches bigint := 0;
  v_status text := 'fail';
  v_details jsonb := '{}'::jsonb;
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

  with raw as (
    select
      t.source_id,
      coalesce(nullif(t.payload->>'amount','')::numeric, 0) as raw_amount,
      upper(coalesce(nullif(t.payload->>'currency',''), 'IQD')) as raw_currency
    from public.daftar_mirror_transactions t
    where t.sync_source_id = v_source.id
      and t.payload->>'transaction_type' = 'LOAN'
      and coalesce(nullif(t.payload->>'amount','')::numeric, 0) <> 0
  ),
  links as (
    select
      l.source_id,
      count(distinct l.target_id) as target_count,
      min(l.target_id::text)::uuid as target_id
    from public.legacy_import_links l
    where l.admin_id = v_source.admin_id
      and l.entity_kind = 'debt'
    group by l.source_id
  ),
  cmp as (
    select
      r.source_id,
      r.raw_amount,
      r.raw_currency,
      coalesce(l.target_count, 0) as target_count,
      d.id as debt_id,
      d.amount as zhirox_amount,
      upper(coalesce(d.currency, 'IQD')) as zhirox_currency
    from raw r
    left join links l on l.source_id = r.source_id
    left join public.debts d on d.id = l.target_id
  )
  select
    count(*),
    count(*) filter (where target_count = 0 or debt_id is null),
    count(*) filter (where target_count > 1),
    count(*) filter (
      where target_count = 1
        and debt_id is not null
        and abs(raw_amount - zhirox_amount) > 0.009
    ),
    count(*) filter (
      where target_count = 1
        and debt_id is not null
        and raw_currency <> zhirox_currency
    )
  into
    v_nonzero_loans,
    v_missing_loans,
    v_loan_target_conflicts,
    v_loan_amount_mismatches,
    v_loan_currency_mismatches
  from cmp;

  with raw as (
    select
      t.source_id,
      coalesce(nullif(t.payload->>'amount','')::numeric, 0) as raw_amount,
      upper(coalesce(nullif(t.payload->>'currency',''), 'IQD')) as raw_currency
    from public.daftar_mirror_transactions t
    where t.sync_source_id = v_source.id
      and t.payload->>'transaction_type' = 'PAYMENT'
      and coalesce(nullif(t.payload->>'amount','')::numeric, 0) <> 0
  ),
  targets as (
    select distinct
      split_part(l.source_id, ':', 1) as source_id,
      l.target_id
    from public.legacy_import_links l
    where l.admin_id = v_source.admin_id
      and l.entity_kind = 'payment'
  ),
  agg as (
    select
      r.source_id,
      r.raw_amount,
      r.raw_currency,
      count(p.id) as allocation_count,
      coalesce(sum(p.amount), 0) as zhirox_amount,
      count(*) filter (
        where p.id is not null
          and upper(coalesce(d.currency, 'IQD')) <> r.raw_currency
      ) as currency_mismatch_allocations
    from raw r
    left join targets t on t.source_id = r.source_id
    left join public.payments p on p.id = t.target_id
    left join public.debts d on d.id = p.debt_id
    group by r.source_id, r.raw_amount, r.raw_currency
  )
  select
    count(*),
    count(*) filter (where allocation_count = 0),
    count(*) filter (
      where allocation_count > 0
        and abs(raw_amount - zhirox_amount) > 0.009
    ),
    count(*) filter (where currency_mismatch_allocations > 0)
  into
    v_nonzero_payments,
    v_missing_payments,
    v_payment_amount_mismatches,
    v_payment_currency_mismatches
  from agg;

  select count(*)
    into v_zero_event_mismatches
  from public.daftar_mirror_transactions t
  where t.sync_source_id = v_source.id
    and coalesce(nullif(t.payload->>'amount','')::numeric, 0) = 0
    and not exists (
      select 1
      from public.daftar_sync_seen z
      join public.financial_events f on f.id = z.target_id
      where z.sync_source_id = v_source.id
        and z.entity_kind = 'zero_event'
        and z.source_id = t.source_id
        and f.amount = 0
        and f.remaining = 0
        and f.event_type = case
          when t.payload->>'transaction_type' = 'PAYMENT'
            then 'payment_created'
          else 'debt_created'
        end
    );

  v_total_mismatches :=
      v_missing_loans
    + v_loan_target_conflicts
    + v_loan_amount_mismatches
    + v_loan_currency_mismatches
    + v_missing_payments
    + v_payment_amount_mismatches
    + v_payment_currency_mismatches
    + v_zero_event_mismatches;

  v_status := case when v_total_mismatches = 0 then 'pass' else 'fail' end;

  v_details := jsonb_build_object(
    'nonzero_loans', v_nonzero_loans,
    'missing_loans', v_missing_loans,
    'loan_target_conflicts', v_loan_target_conflicts,
    'loan_amount_mismatches', v_loan_amount_mismatches,
    'loan_currency_mismatches', v_loan_currency_mismatches,
    'nonzero_payments', v_nonzero_payments,
    'missing_payments', v_missing_payments,
    'payment_amount_mismatches', v_payment_amount_mismatches,
    'payment_currency_mismatches', v_payment_currency_mismatches,
    'zero_event_mismatches', v_zero_event_mismatches,
    'total_mismatches', v_total_mismatches
  );

  update public.daftar_sync_sources
  set cutover_rehearsal_status = v_status,
      cutover_rehearsal_mismatches = v_total_mismatches,
      last_cutover_rehearsal_at = now(),
      updated_at = now()
  where id = v_source.id;

  insert into public.daftar_cutover_rehearsal_runs(
    sync_source_id,
    nonzero_loans,
    missing_loans,
    loan_target_conflicts,
    loan_amount_mismatches,
    loan_currency_mismatches,
    nonzero_payments,
    missing_payments,
    payment_amount_mismatches,
    payment_currency_mismatches,
    zero_event_mismatches,
    total_mismatches,
    status,
    details
  ) values (
    v_source.id,
    v_nonzero_loans,
    v_missing_loans,
    v_loan_target_conflicts,
    v_loan_amount_mismatches,
    v_loan_currency_mismatches,
    v_nonzero_payments,
    v_missing_payments,
    v_payment_amount_mismatches,
    v_payment_currency_mismatches,
    v_zero_event_mismatches,
    v_total_mismatches,
    v_status,
    v_details
  );

  return jsonb_build_object(
    'status', v_status,
    'details', v_details
  );
end;
$$;

revoke all on function public.run_daftar_cutover_rehearsal(uuid)
  from public, anon, authenticated;
grant execute on function public.run_daftar_cutover_rehearsal(uuid)
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
      'cutover_rehearsal_status', s.cutover_rehearsal_status,
      'cutover_rehearsal_mismatches', s.cutover_rehearsal_mismatches,
      'last_cutover_rehearsal_at', s.last_cutover_rehearsal_at,
      'cutover_ready',
        s.mirror_bootstrapped_at is not null
        and s.health_status = 'healthy'
        and s.consecutive_failures = 0
        and s.reconciliation_status = 'clean'
        and s.reconciliation_missing_contacts = 0
        and s.reconciliation_missing_transactions = 0
        and s.cutover_rehearsal_status = 'pass'
        and s.cutover_rehearsal_mismatches = 0
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
    perform public.run_daftar_cutover_rehearsal(v_source_id);
  end if;
end;
$$;
