-- Harden and finalize the generic multi-tenant Daftar runtime.
-- Generated from verified production definitions after live reconciliation.
-- Supabase CLI generation was unavailable in this runtime; timestamp is from the database clock.
--
-- Key guarantees:
-- 1) one source lineage per sync_source_id, including explicit historical fingerprints;
-- 2) source-scoped reconciliation with historical-payment compatibility;
-- 3) one generic dispatch/reconcile/guardian runtime for all tenants;
-- 4) generic daily tenant backups;
-- 5) permanent bidirectional source lock remains private and non-client-callable.

create table if not exists private.daftar_source_fingerprint_aliases (
  sync_source_id uuid not null
    references public.daftar_sync_sources(id) on delete cascade,
  source_fingerprint text not null
    check (length(trim(source_fingerprint)) > 0),
  alias_kind text not null default 'historical_import'
    check (alias_kind in ('current','historical_import')),
  created_at timestamptz not null default now(),
  primary key (sync_source_id, source_fingerprint)
);

alter table private.daftar_source_fingerprint_aliases enable row level security;
revoke all on table private.daftar_source_fingerprint_aliases
  from public, anon, authenticated;

insert into private.daftar_source_fingerprint_aliases(
  sync_source_id,source_fingerprint,alias_kind
)
select id,source_fingerprint,'current'
from public.daftar_sync_sources
where nullif(source_fingerprint,'') is not null
on conflict(sync_source_id,source_fingerprint)
do update set alias_kind='current';

-- Verified historical import lineage for the existing account-28 source.
insert into private.daftar_source_fingerprint_aliases(
  sync_source_id,source_fingerprint,alias_kind
)
select id,
       '3001c4f0e5d0690ac2a57fd3bcf5e76d779f4c88e24c123fa92644911cfa6d98',
       'historical_import'
from public.daftar_sync_sources
where legacy_user_id=28
  and source_fingerprint='daftar-live-account-28-v1'
on conflict(sync_source_id,source_fingerprint) do nothing;

CREATE OR REPLACE FUNCTION private.prevent_daftar_sync_source_breakage()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_guardian boolean :=
    coalesce(current_setting('zhirox.daftar_sync_guardian', true), '') = 'on';
  v_unlock boolean :=
    coalesce(current_setting('zhirox.daftar_sync_unlock', true), '') = 'on';
  v_protected boolean;
begin
  if v_unlock or v_guardian then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  v_protected :=
    coalesce(old.enabled, false)
    and old.sync_mode in ('mirror', 'zhirox_primary');

  if tg_op = 'DELETE' then
    if v_protected then
      raise exception 'daftar_sync_source_locked' using errcode = '42501';
    end if;
    return old;
  end if;

  if not v_protected then
    return new;
  end if;

  if new.id is distinct from old.id
     or new.admin_id is distinct from old.admin_id
     or new.legacy_user_id is distinct from old.legacy_user_id
     or new.source_fingerprint is distinct from old.source_fingerprint
     or new.api_base_url is distinct from old.api_base_url
     or new.trigger_secret_hash is distinct from old.trigger_secret_hash
     or new.trigger_secret_vault_name is distinct from old.trigger_secret_vault_name then
    raise exception 'daftar_sync_source_identity_locked' using errcode = '42501';
  end if;

  if old.sync_mode = 'mirror' then
    if new.sync_mode is distinct from 'mirror'
       or new.enabled is distinct from true then
      raise exception 'daftar_sync_mirror_mode_locked' using errcode = '42501';
    end if;
  elsif old.sync_mode = 'zhirox_primary' then
    if new.sync_mode is distinct from 'zhirox_primary' then
      raise exception 'daftar_sync_primary_mode_locked' using errcode = '42501';
    end if;

    if new.enabled is distinct from true
       or new.inbound_sync_enabled is distinct from true
       or new.outbound_sync_enabled is distinct from true then
      raise exception 'daftar_bidirectional_sync_must_remain_enabled'
        using errcode = '42501';
    end if;

    if new.outbound_write_contract_status is distinct from 'verified' then
      raise exception 'daftar_outbound_write_contract_must_remain_verified'
        using errcode = '42501';
    end if;
  else
    raise exception 'daftar_sync_unknown_mode_locked' using errcode = '42501';
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.run_daftar_sync_reconciliation(p_source_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_checks jsonb;
  v_status text;
begin
  if not exists (
    select 1
    from public.daftar_sync_sources s
    where s.id = p_source_id
  ) then
    raise exception 'sync_source_not_found' using errcode = 'P0002';
  end if;

  with active_mapped as (
    select s.*
    from public.daftar_sync_seen s
    where s.sync_source_id = p_source_id
      and not (
        s.entity_kind in ('debt','payment','payment_allocation')
        and s.payload_hash in ('__deleted__','__credit_limit_rejected__')
      )
  ),
  archived_customers as (
    select distinct a.target_id
    from public.daftar_customer_link_archive a
    left join public.daftar_mirror_contacts mc
      on mc.sync_source_id = a.sync_source_id
     and mc.source_id = a.source_id
    where a.sync_source_id = p_source_id
      and a.archived_reason = 'source_contact_absent_from_current_daftar_snapshot'
      and mc.source_id is null
  ),
  source_state as (
    select
      s.last_contact_id,
      s.last_transaction_id,
      s.last_success_at,
      (
        s.last_success_at is null
        or s.last_success_at < now() - interval '10 minutes'
      ) as sync_stale
    from public.daftar_sync_sources s
    where s.id = p_source_id
  ),
  mapping_counts as (
    select
      count(*) filter (where entity_kind='customer') as mapped_customers,
      count(*) filter (where entity_kind='debt') as mapped_debts,
      count(*) filter (where entity_kind='payment') as mapped_payments,
      count(*) filter (where entity_kind='payment_allocation') as mapped_payment_allocations
    from active_mapped
  ),
  orphan_counts as (
    select
      count(*) filter (where m.entity_kind='customer' and p.id is null) as customer_orphans,
      count(*) filter (where m.entity_kind='debt' and d.id is null) as debt_orphans,
      count(*) filter (where m.entity_kind='payment_allocation' and pay.id is null) as payment_allocation_orphans
    from active_mapped m
    left join public.profiles p
      on m.entity_kind='customer'
     and p.id=m.target_id
    left join public.debts d
      on m.entity_kind='debt'
     and d.id=m.target_id
    left join public.payments pay
      on m.entity_kind='payment_allocation'
     and pay.id=m.target_id
  ),
  target_conflicts as (
    select count(*) as duplicate_target_links
    from (
      select entity_kind,target_id
      from active_mapped
      where entity_kind in ('customer','debt','payment_allocation')
        and target_id is not null
      group by entity_kind,target_id
      having count(*) > 1
    ) q
  ),
  source_conflicts as (
    select count(*) as duplicate_source_links
    from (
      select entity_kind,source_id
      from active_mapped
      group by entity_kind,source_id
      having count(*) > 1
    ) q
  ),
  mapped_debts as (
    select d.*
    from active_mapped m
    join public.debts d
      on m.entity_kind='debt'
     and d.id=m.target_id
  ),
  payment_totals as (
    select p.debt_id, coalesce(sum(p.amount),0) as paid
    from public.payments p
    join mapped_debts d on d.id=p.debt_id
    group by p.debt_id
  ),
  debt_checks as (
    select
      count(*) filter (where coalesce(d.remaining,0) < 0) as negative_remaining,
      count(*) filter (where coalesce(d.remaining,0) > coalesce(d.amount,0)) as remaining_over_amount,
      count(*) filter (
        where cm.target_id is null
          and ac.target_id is null
      ) as debt_customer_without_source_customer,
      count(*) filter (
        where abs(
          coalesce(d.remaining,0)
          - greatest(coalesce(d.amount,0)-coalesce(pt.paid,0),0)
        ) > 0.01
      ) as balance_mismatches,
      count(*) filter (
        where coalesce(pt.paid,0) > coalesce(d.amount,0)+0.01
      ) as overpaid_debts
    from mapped_debts d
    left join active_mapped cm
      on cm.entity_kind='customer'
     and cm.target_id=d.customer_id
    left join archived_customers ac
      on ac.target_id=d.customer_id
    left join payment_totals pt
      on pt.debt_id=d.id
  ),
  payment_checks as (
    select count(*) as mapped_payment_to_unmapped_debt
    from active_mapped m
    join public.payments p
      on m.entity_kind='payment_allocation'
     and p.id=m.target_id
    left join active_mapped dm
      on dm.entity_kind='debt'
     and dm.target_id=p.debt_id
    where dm.target_id is null
  )
  select jsonb_build_object(
    'last_contact_id',ss.last_contact_id,
    'last_transaction_id',ss.last_transaction_id,
    'last_success_at',ss.last_success_at,
    'sync_stale',ss.sync_stale,
    'mapped_customers',mc.mapped_customers,
    'mapped_debts',mc.mapped_debts,
    'mapped_payments',mc.mapped_payments,
    'mapped_payment_allocations',mc.mapped_payment_allocations,
    'customer_orphans',oc.customer_orphans,
    'debt_orphans',oc.debt_orphans,
    'payment_allocation_orphans',oc.payment_allocation_orphans,
    'duplicate_target_links',tc.duplicate_target_links,
    'duplicate_source_links',sc.duplicate_source_links,
    'negative_remaining',dc.negative_remaining,
    'remaining_over_amount',dc.remaining_over_amount,
    'debt_customer_without_source_customer',dc.debt_customer_without_source_customer,
    'balance_mismatches',dc.balance_mismatches,
    'overpaid_debts',dc.overpaid_debts,
    'mapped_payment_to_unmapped_debt',pc.mapped_payment_to_unmapped_debt
  )
  into v_checks
  from source_state ss
  cross join mapping_counts mc
  cross join orphan_counts oc
  cross join target_conflicts tc
  cross join source_conflicts sc
  cross join debt_checks dc
  cross join payment_checks pc;

  v_status := case when
    coalesce((v_checks->>'sync_stale')::boolean,true)
    or coalesce((v_checks->>'customer_orphans')::bigint,0)>0
    or coalesce((v_checks->>'debt_orphans')::bigint,0)>0
    or coalesce((v_checks->>'payment_allocation_orphans')::bigint,0)>0
    or coalesce((v_checks->>'duplicate_target_links')::bigint,0)>0
    or coalesce((v_checks->>'duplicate_source_links')::bigint,0)>0
    or coalesce((v_checks->>'negative_remaining')::bigint,0)>0
    or coalesce((v_checks->>'remaining_over_amount')::bigint,0)>0
    or coalesce((v_checks->>'debt_customer_without_source_customer')::bigint,0)>0
    or coalesce((v_checks->>'balance_mismatches')::bigint,0)>0
    or coalesce((v_checks->>'overpaid_debts')::bigint,0)>0
    or coalesce((v_checks->>'mapped_payment_to_unmapped_debt')::bigint,0)>0
    then 'unhealthy'
    else 'healthy'
  end;

  insert into private.daftar_sync_reconciliation_runs(
    sync_source_id,status,checks
  )
  values (p_source_id,v_status,v_checks);

  delete from private.daftar_sync_reconciliation_runs
  where created_at < now()-interval '90 days';

  return jsonb_build_object('status',v_status,'checks',v_checks);
end;
$function$;

CREATE OR REPLACE FUNCTION private.reconcile_daftar_source(p_source_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  select * into v_source
  from public.daftar_sync_sources
  where id=p_source_id
    and (enabled=true or inbound_sync_enabled=true or outbound_sync_enabled=true);

  if v_source.id is null then
    raise exception 'daftar_source_not_available' using errcode='P0002';
  end if;

  for v_tx in
    select t.source_id,t.payload,t.payload_hash,
           t.payload->>'transaction_type' as transaction_type,
           coalesce(t.payload->>'transaction_date',t.payload->>'created_at') as occurred_at,
           coalesce(t.payload->>'currency','IQD') as currency,
           coalesce(t.payload->>'note','') as note,
           t.payload->>'contact_id' as contact_source_id
    from public.daftar_mirror_transactions t
    where t.sync_source_id=v_source.id
      and coalesce(nullif(t.payload->>'amount','')::numeric,0)=0
      and not exists (
        select 1 from public.daftar_sync_seen z
        where z.sync_source_id=v_source.id
          and z.entity_kind='zero_event'
          and z.source_id=t.source_id
      )
    order by t.last_mirrored_at,t.source_id
  loop
    select s.target_id into v_customer_id
    from public.daftar_sync_seen s
    join public.profiles p on p.id=s.target_id
    where s.sync_source_id=v_source.id
      and s.entity_kind='customer'
      and s.source_id=v_tx.contact_source_id
      and p.role='customer'
      and p.admin_id=v_source.admin_id
    limit 1;

    if v_customer_id is null then continue; end if;

    insert into public.financial_events(
      customer_id,event_type,actor_id,actor_name,actor_role,
      amount,remaining,currency,description,metadata,created_at
    )
    values(
      v_customer_id,
      case when v_tx.transaction_type='PAYMENT' then 'payment_created' else 'debt_created' end,
      v_source.admin_id,'Daftar Qarz Sync','admin',
      0,0,v_tx.currency,v_tx.note,
      jsonb_build_object(
        'legacy_zero_amount',true,
        'legacy_transaction_id',v_tx.source_id,
        'legacy_contact_id',v_tx.contact_source_id,
        'source','daftar_live_sync_reconcile',
        'source_fingerprint',v_source.source_fingerprint
      ),
      coalesce(v_tx.occurred_at::timestamptz,now())
    )
    returning id into v_event_id;

    insert into public.daftar_sync_seen(
      sync_source_id,entity_kind,source_id,target_id,payload_hash
    )
    values(v_source.id,'zero_event',v_tx.source_id,v_event_id,v_tx.payload_hash)
    on conflict(sync_source_id,entity_kind,source_id) do nothing;

    if v_tx.transaction_type='PAYMENT' then
      insert into public.daftar_sync_seen(
        sync_source_id,entity_kind,source_id,target_id,payload_hash
      )
      values(v_source.id,'payment',v_tx.source_id,null,v_tx.payload_hash)
      on conflict(sync_source_id,entity_kind,source_id) do nothing;
    end if;

    v_backfilled:=v_backfilled+1;
  end loop;

  select count(*) into v_mirrored_contacts
  from public.daftar_mirror_contacts c
  where c.sync_source_id=v_source.id;

  select count(*) into v_missing_contacts
  from public.daftar_mirror_contacts c
  where c.sync_source_id=v_source.id
    and not exists (
      select 1
      from public.daftar_sync_seen s
      join public.profiles p on p.id=s.target_id
      where s.sync_source_id=v_source.id
        and s.entity_kind='customer'
        and s.source_id=c.source_id
        and p.role='customer'
        and p.admin_id=v_source.admin_id
    );

  select count(*) into v_mirrored_transactions
  from public.daftar_mirror_transactions t
  where t.sync_source_id=v_source.id;

  select count(*) into v_missing_transactions
  from public.daftar_mirror_transactions t
  where t.sync_source_id=v_source.id
    and case
      when coalesce(nullif(t.payload->>'amount','')::numeric,0)=0 then
        not exists (
          select 1 from public.daftar_sync_seen z
          join public.financial_events f on f.id=z.target_id
          where z.sync_source_id=v_source.id
            and z.entity_kind='zero_event'
            and z.source_id=t.source_id
        )
      when t.payload->>'transaction_type'='LOAN' then
        not exists (
          select 1
          from public.daftar_sync_seen d
          left join public.debts debt on debt.id=d.target_id
          where d.sync_source_id=v_source.id
            and d.entity_kind='debt'
            and d.source_id=t.source_id
            and (
              d.payload_hash in ('__deleted__','__credit_limit_rejected__')
              or debt.id is not null
            )
        )
      when t.payload->>'transaction_type'='PAYMENT' then
        not (
          exists (
            select 1
            from public.daftar_sync_seen p
            where p.sync_source_id=v_source.id
              and p.entity_kind='payment'
              and p.source_id=t.source_id
              and (
                p.payload_hash in ('__deleted__','__credit_limit_rejected__')
                or exists (
                  select 1
                  from public.daftar_sync_seen a
                  join public.payments pay on pay.id=a.target_id
                  where a.sync_source_id=v_source.id
                    and a.entity_kind='payment_allocation'
                    and a.source_id like t.source_id || ':%'
                )
              )
          )
          or exists (
            select 1
            from public.legacy_import_links l
            join public.payments pay on pay.id=l.target_id
            where l.admin_id=v_source.admin_id
              and exists (
       select 1
       from private.daftar_source_fingerprint_aliases a
       where a.sync_source_id=v_source.id
         and a.source_fingerprint=l.source_fingerprint
     )
              and l.entity_kind='payment'
              and split_part(l.source_id,':',1)=t.source_id
          )
        )
      else true
    end;

  v_status:=case
    when v_missing_contacts=0 and v_missing_transactions=0 then 'clean'
    else 'gap'
  end;

  update public.daftar_sync_sources
  set reconciliation_status=v_status,
      reconciliation_missing_contacts=v_missing_contacts,
      reconciliation_missing_transactions=v_missing_transactions,
      last_reconciled_at=now(),
      updated_at=now()
  where id=v_source.id;

  insert into public.daftar_reconciliation_runs(
    sync_source_id,mirrored_contacts,mirrored_transactions,
    missing_contacts,missing_transactions,backfilled_zero_events,status
  )
  values(
    v_source.id,v_mirrored_contacts,v_mirrored_transactions,
    v_missing_contacts,v_missing_transactions,v_backfilled,v_status
  );

  return jsonb_build_object(
    'source_id',v_source.id,
    'source_fingerprint',v_source.source_fingerprint,
    'status',v_status,
    'mirrored_contacts',v_mirrored_contacts,
    'mirrored_transactions',v_mirrored_transactions,
    'missing_contacts',v_missing_contacts,
    'missing_transactions',v_missing_transactions,
    'backfilled_zero_events',v_backfilled
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.dispatch_daftar_sync_sources()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r record;
  v_secret text;
  v_inbound_count integer := 0;
  v_outbound_count integer := 0;
  v_skipped_count integer := 0;
begin
  for r in
    select
      s.id,
      s.legacy_user_id,
      s.source_fingerprint,
      s.trigger_secret_hash,
      s.trigger_secret_vault_name,
      s.sync_mode,
      s.inbound_sync_enabled,
      s.outbound_sync_enabled,
      s.outbound_write_contract_status
    from public.daftar_sync_sources s
    where s.enabled = true
      and nullif(s.trigger_secret_vault_name, '') is not null
    order by s.created_at
  loop
    v_secret := null;

    select decrypted_secret into v_secret
    from vault.decrypted_secrets
    where name = r.trigger_secret_vault_name
    limit 1;

    if v_secret is null
       or encode(extensions.digest(v_secret, 'sha256'), 'hex')
          is distinct from r.trigger_secret_hash then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    if r.sync_mode = 'mirror'
       or (r.sync_mode = 'zhirox_primary' and r.inbound_sync_enabled = true) then
      perform net.http_post(
        url := 'https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/daftar-sync-gateway',
        headers := jsonb_build_object(
          'Content-Type','application/json',
          'x-daftar-sync-secret',v_secret
        ),
        body := jsonb_build_object('source_id',r.id),
        timeout_milliseconds := 120000
      );
      v_inbound_count := v_inbound_count + 1;
    end if;

    if r.sync_mode = 'zhirox_primary'
       and r.outbound_sync_enabled = true
       and r.outbound_write_contract_status = 'verified' then
      perform net.http_post(
        url := 'https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/daftar-outbound-sync',
        headers := jsonb_build_object(
          'Content-Type','application/json',
          'x-daftar-sync-secret',v_secret
        ),
        body := jsonb_build_object(
          'source_id',r.id,
          'action','drain'
        ),
        timeout_milliseconds := 120000
      );
      v_outbound_count := v_outbound_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'inbound_dispatched',v_inbound_count,
    'outbound_dispatched',v_outbound_count,
    'skipped_missing_or_invalid_secret',v_skipped_count
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.reconcile_daftar_sync_sources()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r record;
  v_projection jsonb;
  v_integrity jsonb;
  v_clean integer := 0;
  v_gap integer := 0;
  v_errors integer := 0;
begin
  for r in
    select id
    from public.daftar_sync_sources
    where enabled=true
       or inbound_sync_enabled=true
       or outbound_sync_enabled=true
    order by created_at
  loop
    begin
      v_projection := private.reconcile_daftar_source(r.id);
      v_integrity := private.run_daftar_sync_reconciliation(r.id);

      if v_projection->>'status'='clean'
         and v_integrity->>'status'='healthy' then
        v_clean := v_clean + 1;
      else
        v_gap := v_gap + 1;
        update public.daftar_sync_sources
        set reconciliation_status='gap',
            updated_at=now()
        where id=r.id;
      end if;
    exception when others then
      v_errors := v_errors + 1;
      update public.daftar_sync_sources
      set reconciliation_status='gap',
          updated_at=now()
      where id=r.id;
    end;
  end loop;

  return jsonb_build_object(
    'clean_sources',v_clean,
    'gap_sources',v_gap,
    'error_sources',v_errors
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.run_daftar_tenant_backups()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r record;
  v_ok integer := 0;
  v_errors integer := 0;
begin
  for r in
    select distinct admin_id
    from public.daftar_sync_sources
    where enabled=true
       or inbound_sync_enabled=true
       or outbound_sync_enabled=true
    order by admin_id
  loop
    begin
      perform private.run_scheduled_tenant_backup(r.admin_id);
      v_ok := v_ok + 1;
    exception when others then
      v_errors := v_errors + 1;
    end;
  end loop;

  return jsonb_build_object(
    'backed_up_tenants',v_ok,
    'backup_errors',v_errors
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.guard_daftar_sync_sources()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r record;
  j record;
  v_secret text;
  v_valid integer := 0;
  v_invalid integer := 0;
  v_job_id bigint;
  v_removed_legacy integer := 0;
begin
  perform set_config('zhirox.daftar_sync_guardian','on',true);

  insert into private.daftar_source_fingerprint_aliases(
    sync_source_id,source_fingerprint,alias_kind
  )
  select id,source_fingerprint,'current'
  from public.daftar_sync_sources
  where nullif(source_fingerprint,'') is not null
  on conflict(sync_source_id,source_fingerprint)
  do update set alias_kind='current';

  for r in
    select id,trigger_secret_hash,trigger_secret_vault_name
    from public.daftar_sync_sources
    where enabled=true
    order by created_at,id
  loop
    v_secret := null;

    if nullif(r.trigger_secret_vault_name,'') is not null then
      select decrypted_secret into v_secret
      from vault.decrypted_secrets
      where name=r.trigger_secret_vault_name
      limit 1;
    end if;

    if v_secret is null
       or encode(extensions.digest(v_secret,'sha256'),'hex')
          is distinct from r.trigger_secret_hash then
      v_invalid := v_invalid + 1;

      update public.daftar_sync_sources
      set health_status='degraded',
          last_status='failed',
          last_error='trigger_secret_missing_or_invalid',
          updated_at=now()
      where id=r.id;
    else
      v_valid := v_valid + 1;

      update public.daftar_sync_sources
      set last_error=null,
          updated_at=now()
      where id=r.id
        and last_error='trigger_secret_missing_or_invalid';
    end if;

    perform public.qualify_daftar_outage(r.id);
  end loop;

  for j in
    select jobid
    from cron.job
    where jobname in (
      'daftar-live-sync-account-28',
      'daftar-sync-reconcile-account-28',
      'daily-tenant-backup-account-28',
      'daftar-sync-guardian-account-28',
      'daftar-outbound-sync-account-28',
      'daftar-sync-dispatch-all',
      'daftar-sync-reconcile-all',
      'daftar-sync-guardian-all'
    )
  loop
    perform cron.unschedule(j.jobid);
    v_removed_legacy := v_removed_legacy + 1;
  end loop;

  select jobid into v_job_id
  from cron.job
  where jobname='daftar-sync-multitenant-dispatch'
  limit 1;

  if v_job_id is null then
    perform cron.schedule(
      'daftar-sync-multitenant-dispatch',
      '* * * * *',
      'select private.dispatch_daftar_sync_sources();'
    );
  else
    perform cron.alter_job(
      job_id=>v_job_id,
      schedule=>'* * * * *',
      command=>'select private.dispatch_daftar_sync_sources();',
      active=>true
    );
  end if;

  select jobid into v_job_id
  from cron.job
  where jobname='daftar-sync-multitenant-reconcile'
  limit 1;

  if v_job_id is null then
    perform cron.schedule(
      'daftar-sync-multitenant-reconcile',
      '17 * * * *',
      'select private.reconcile_daftar_sync_sources();'
    );
  else
    perform cron.alter_job(
      job_id=>v_job_id,
      schedule=>'17 * * * *',
      command=>'select private.reconcile_daftar_sync_sources();',
      active=>true
    );
  end if;

  select jobid into v_job_id
  from cron.job
  where jobname='daily-daftar-tenant-backup-all'
  limit 1;

  if v_job_id is null then
    perform cron.schedule(
      'daily-daftar-tenant-backup-all',
      '30 2 * * *',
      'select private.run_daftar_tenant_backups();'
    );
  else
    perform cron.alter_job(
      job_id=>v_job_id,
      schedule=>'30 2 * * *',
      command=>'select private.run_daftar_tenant_backups();',
      active=>true
    );
  end if;

  select jobid into v_job_id
  from cron.job
  where jobname='daftar-sync-multitenant-guardian'
  limit 1;

  if v_job_id is null then
    perform cron.schedule(
      'daftar-sync-multitenant-guardian',
      '* * * * *',
      'select private.guard_daftar_sync_sources();'
    );
  else
    perform cron.alter_job(
      job_id=>v_job_id,
      schedule=>'* * * * *',
      command=>'select private.guard_daftar_sync_sources();',
      active=>true
    );
  end if;

  return jsonb_build_object(
    'valid_sources',v_valid,
    'invalid_sources',v_invalid,
    'deprecated_jobs_removed',v_removed_legacy,
    'runtime_jobs',4
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.guard_daftar_sync_runtime()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select private.guard_daftar_sync_sources();
$function$;

CREATE OR REPLACE FUNCTION public.guard_daftar_sync_account_28()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform private.guard_daftar_sync_sources();
end;
$function$;

CREATE OR REPLACE FUNCTION public.guard_daftar_outbound_account_28()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform private.guard_daftar_sync_sources();
end;
$function$;

CREATE OR REPLACE FUNCTION private.get_daftar_official_customer_totals(p_customer_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(customer_id uuid, source_contact_id text, loan_iqd numeric, payment_iqd numeric, balance_iqd numeric, loan_usd numeric, payment_usd numeric, balance_usd numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with tenant as (
    select private.current_admin_id() as admin_id
  ),
  source_row as (
    select s.id,s.admin_id,s.source_fingerprint
    from public.daftar_sync_sources s
    cross join tenant t
    where t.admin_id is not null
      and s.admin_id=t.admin_id
      and s.sync_mode='zhirox_primary'
      and coalesce(s.inbound_sync_enabled,false)
      and s.official_totals_at is not null
    order by s.official_totals_at desc nulls last,s.created_at
    limit 1
  )
  select
    l.target_id as customer_id,
    l.source_id as source_contact_id,
    oct.loan_iqd,
    oct.payment_iqd,
    oct.balance_iqd,
    oct.loan_usd,
    oct.payment_usd,
    oct.balance_usd
  from source_row sr
  join public.legacy_import_links l
    on l.admin_id=sr.admin_id
   and l.entity_kind='customer'
   and exists (
     select 1
     from private.daftar_source_fingerprint_aliases a
     where a.sync_source_id=sr.id
       and a.source_fingerprint=l.source_fingerprint
   )
  join public.daftar_official_contact_totals oct
    on oct.sync_source_id=sr.id
   and oct.source_contact_id=l.source_id
  join public.profiles p
    on p.id=l.target_id
   and p.admin_id=sr.admin_id
   and p.role='customer'
  where p_customer_id is null or l.target_id=p_customer_id;
$function$;

CREATE OR REPLACE FUNCTION private.get_daftar_projection_summary()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with tenant as (
    select private.current_admin_id() as admin_id
  )
  select coalesce((
    select jsonb_build_object(
      'source_id',s.id,
      'admin_id',s.admin_id,
      'source_fingerprint',s.source_fingerprint,
      'legacy_user_id',s.legacy_user_id,
      'official_total_customers',coalesce(s.official_total_customers,0),
      'official_total_loan_iqd',coalesce(s.official_total_loan_iqd,0),
      'official_total_payment_iqd',coalesce(s.official_total_payment_iqd,0),
      'official_balance_iqd',coalesce(s.official_balance_iqd,0),
      'official_total_loan_usd',coalesce(s.official_total_loan_usd,0),
      'official_total_payment_usd',coalesce(s.official_total_payment_usd,0),
      'official_balance_usd',coalesce(s.official_balance_usd,0),
      'official_totals_at',s.official_totals_at
    )
    from public.daftar_sync_sources s
    cross join tenant t
    where t.admin_id is not null
      and s.admin_id=t.admin_id
      and s.sync_mode='zhirox_primary'
      and coalesce(s.inbound_sync_enabled,false)
      and s.official_totals_at is not null
    order by s.official_totals_at desc nulls last,s.created_at
    limit 1
  ),'{}'::jsonb);
$function$;


revoke execute on function private.prevent_daftar_sync_source_breakage()
  from public,anon,authenticated;
revoke execute on function private.run_daftar_sync_reconciliation(uuid)
  from public,anon,authenticated;
revoke execute on function private.reconcile_daftar_source(uuid)
  from public,anon,authenticated;
revoke execute on function private.dispatch_daftar_sync_sources()
  from public,anon,authenticated;
revoke execute on function private.reconcile_daftar_sync_sources()
  from public,anon,authenticated;
revoke execute on function private.run_daftar_tenant_backups()
  from public,anon,authenticated;
revoke execute on function private.guard_daftar_sync_sources()
  from public,anon,authenticated;
revoke execute on function private.guard_daftar_sync_runtime()
  from public,anon,authenticated;
revoke execute on function public.guard_daftar_sync_account_28()
  from public,anon,authenticated;
revoke execute on function public.guard_daftar_outbound_account_28()
  from public,anon,authenticated;

drop trigger if exists zhirox_protect_daftar_sync_account_28
  on public.daftar_sync_sources;
drop trigger if exists zhirox_protect_daftar_sync_sources
  on public.daftar_sync_sources;

create trigger zhirox_protect_daftar_sync_sources
before delete or update on public.daftar_sync_sources
for each row
execute function private.prevent_daftar_sync_source_breakage();

-- Consolidate any deprecated/duplicate schedules and enforce the canonical
-- four-job multi-tenant runtime.
select private.guard_daftar_sync_sources();
