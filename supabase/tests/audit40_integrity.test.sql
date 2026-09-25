begin;

create extension if not exists pgtap with schema extensions;
select plan(35);

select ok(
  to_regprocedure('public.record_payment_service(uuid,uuid,numeric,text,text,uuid)') is not null,
  'transactional debt payment service exists'
);

select ok(
  to_regprocedure('public.record_customer_payment_service(uuid,uuid,numeric,text,text,uuid)') is not null,
  'transactional general payment service exists'
);

select ok(
  to_regprocedure('public.delete_general_payment_service(uuid,uuid)') is not null,
  'general payment correction service exists'
);

select ok(
  to_regprocedure('private.get_customer_virtual_debt_balances(uuid)') is not null,
  'virtual debt balance projection exists'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.record_payment_service(uuid,uuid,numeric,text,text,uuid)',
    'EXECUTE'
  ),
  'authenticated users cannot bypass the payment Edge gateway'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.record_customer_payment_service(uuid,uuid,numeric,text,text,uuid)',
    'EXECUTE'
  ),
  'authenticated users cannot bypass the general payment Edge gateway'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.delete_general_payment_service(uuid,uuid)',
    'EXECUTE'
  ),
  'authenticated users cannot bypass the payment correction Edge gateway'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.get_platform_operations_state()',
    'EXECUTE'
  ),
  'anonymous users cannot read platform operations state'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_platform_operations_state()',
    'EXECUTE'
  ),
  'signed-in users retain platform operations access'
);

select is(
  (
    select count(*)::bigint
    from pg_policies
    where schemaname='storage'
      and tablename='objects'
      and policyname='receipts_select'
  ),
  1::bigint,
  'private receipt select policy exists exactly once'
);

select ok(
  position(
    'receipt_belongs_to_customer' in coalesce((
      select qual
      from pg_policies
      where schemaname='storage'
        and tablename='objects'
        and policyname='receipts_select'
    ), '')
  ) > 0,
  'legacy receipt ownership is enforced by the receipt policy'
);

select is(
  (
    select count(*)::bigint
    from cron.job
    where jobname='daily-tenant-backup-all'
      and active=true
  ),
  1::bigint,
  'one active all-tenant daily backup job exists'
);

select is(
  (
    select count(*)::bigint
    from cron.job
    where jobname='daily-daftar-tenant-backup-all'
  ),
  0::bigint,
  'superseded Daftar-only backup job is absent'
);

select ok(
  position(
    '''version'', 2' in
    pg_get_functiondef('private.build_tenant_backup_snapshot(uuid)'::regprocedure)
  ) > 0,
  'tenant backups use snapshot version 2'
);

select ok(
  to_regprocedure('private.get_effective_installment_remaining(uuid)') is not null,
  'partial installment credit projection exists'
);

select ok(
  position(
    'general_payment_policy' in
    pg_get_functiondef('public.get_customer_finance_snapshot(uuid)'::regprocedure)
  ) > 0,
  'finance snapshot declares account-credit policy'
);

select ok(
  position(
    'get_customer_virtual_debt_balances' in
    pg_get_functiondef('public.get_admin_dashboard_snapshot()'::regprocedure)
  ) > 0,
  'dashboard pending count is general-credit aware'
);

select ok(
  position(
    'get_effective_installment_remaining' in
    pg_get_functiondef(
      'public.read_customer_portal_due_summary_service(text,text,text)'::regprocedure
    )
  ) > 0,
  'customer portal due summary honors partial account credit'
);

select ok(
  position(
    'get_effective_installment_remaining' in
    pg_get_functiondef(
      'public.enqueue_customer_installment_reminders_service()'::regprocedure
    )
  ) > 0,
  'installment reminders honor partial account credit'
);

select ok(
  position(
    '<> ''USD''' in
    pg_get_functiondef('private.get_customer_virtual_debt_balances(uuid)'::regprocedure)
  ) > 0,
  'general IQD credit does not consume legacy raw-USD debt'
);

select ok(
  to_regprocedure('private.run_backup_catchup()') is not null,
  'backup catch-up watchdog function exists'
);

select ok(
  to_regprocedure('private.guard_backup_runtime()') is not null,
  'backup runtime guard exists'
);

select is(
  (
    select count(*)::bigint
    from cron.job
    where jobname='backup-catchup-watchdog'
      and active=true
  ),
  1::bigint,
  'one active backup catch-up watchdog exists'
);

select ok(
  position(
    'guard_backup_runtime' in
    pg_get_functiondef('private.guard_daftar_sync_sources()'::regprocedure)
  ) > 0,
  'Daftar guardian delegates backup scheduling to the canonical backup guard'
);

select ok(
  to_regclass('private.backup_runtime_events') is not null,
  'backup runtime event history exists'
);

select ok(
  to_regprocedure('public.resolve_daftar_recovered_dead_letters(uuid)') is not null,
  'Daftar recovered dead-letter resolver exists'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.resolve_daftar_recovered_dead_letters(uuid)',
    'EXECUTE'
  ),
  'authenticated users cannot resolve Daftar dead letters directly'
);

select is(
  (
    with fk as (
      select c.oid, c.conrelid, c.conkey
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
      where c.contype = 'f'
        and n.nspname = 'public'
    )
    select count(*)::bigint
    from fk
    where not exists (
      select 1
      from pg_index i
      where i.indrelid = fk.conrelid
        and i.indisvalid
        and i.indisready
        and i.indnkeyatts >= array_length(fk.conkey, 1)
        and (
          select array_agg(k.attnum order by k.ord)
          from unnest(i.indkey::smallint[]) with ordinality k(attnum, ord)
          where k.ord <= array_length(fk.conkey, 1)
        ) = fk.conkey
    )
  ),
  0::bigint,
  'all public foreign keys have covering indexes'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.resolve_daftar_recovered_dead_letters(uuid)',
    'EXECUTE'
  ),
  'service role can resolve recovered Daftar dead letters'
);

select ok(
  position(
    'resolved_after_clean_reconciliation' in
    pg_get_functiondef('public.resolve_daftar_recovered_dead_letters(uuid)'::regprocedure)
  ) > 0,
  'reconciliation dead letters resolve only after a later clean reconciliation'
);

select ok(
  position(
    'resolved_after_passing_cutover_rehearsal' in
    pg_get_functiondef('public.resolve_daftar_recovered_dead_letters(uuid)'::regprocedure)
  ) > 0,
  'cutover dead letters resolve only after a later passing rehearsal'
);

select ok(
  to_regprocedure(
    'public.apply_daftar_inbound_general_payment_update(uuid,uuid,text,uuid,numeric,text,timestamptz)'
  ) is not null,
  'general payment inbound update helper exists'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.apply_daftar_inbound_general_payment_update(uuid,uuid,text,uuid,numeric,text,timestamptz)',
    'EXECUTE'
  ),
  'authenticated users cannot call general payment inbound sync helper'
);

select is(
  (
    select count(*)::bigint
    from pg_trigger t
    where t.tgrelid='public.customer_general_payments'::regclass
      and not t.tgisinternal
      and t.tgname='daftar_outbound_general_payment_mutation'
  ),
  1::bigint,
  'general payment outbound mutation trigger exists exactly once'
);

select ok(
  position(
    'customer_general_payments' in
    pg_get_functiondef('public.enqueue_daftar_outbound_mutation()'::regprocedure)
  ) > 0,
  'outbound mutation function transports general payments'
);

select * from finish();
rollback;