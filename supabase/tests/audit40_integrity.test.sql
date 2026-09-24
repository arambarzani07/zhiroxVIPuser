begin;

create extension if not exists pgtap with schema extensions;
select plan(14);

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

select * from finish();
rollback;
