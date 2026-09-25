-- Integrity reconciliation recognizes general-payment allocation targets.

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
      count(*) filter (
        where m.entity_kind='payment_allocation'
          and pay.id is null
          and gp.id is null
      ) as payment_allocation_orphans
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
    left join public.customer_general_payments gp
      on m.entity_kind='payment_allocation'
     and gp.id=m.target_id
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
