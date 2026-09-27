begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

select ok(to_regprocedure('public.get_my_daftar_sync_alerts()') is not null,
  'admin sync alerts endpoint exists');
select ok(not has_table_privilege('authenticated', 'public.daftar_sync_alerts', 'SELECT'),
  'raw sync alert rows are private');
select ok(not has_function_privilege('anon', 'public.get_my_daftar_sync_alerts()', 'EXECUTE'),
  'anonymous users cannot read tenant alerts');
select is((select count(*)::bigint from cron.job
  where jobname = 'zhirox-daftar-operational-alerts'), 1::bigint,
  'the sync alert scanner is scheduled once');
select ok(to_regprocedure('public.merge_my_duplicate_customer(uuid,uuid)') is not null,
  'customer identity merge exists');
select ok(not has_table_privilege('authenticated', 'public.customer_identity_merges', 'INSERT'),
  'clients cannot forge identity merges');
select ok(not has_function_privilege('anon',
  'public.merge_my_duplicate_customer(uuid,uuid)', 'EXECUTE'),
  'anonymous users cannot merge identities');
select ok(to_regprocedure('public.unmerge_my_duplicate_customer(uuid)') is not null,
  'reversible identity merge exists');
select ok(to_regprocedure('public.get_my_customer_merge_group(uuid)') is not null,
  'merged balances remain readable through a tenant-checked endpoint');

select * from finish();
rollback;
