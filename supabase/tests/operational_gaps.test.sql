begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

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

do $test$
declare
  admin_a uuid := '00000000-0000-0000-0000-000000009101';
  admin_b uuid := '00000000-0000-0000-0000-000000009102';
  customer_a uuid := '00000000-0000-0000-0000-000000009111';
  duplicate_a uuid := '00000000-0000-0000-0000-000000009112';
  other_tenant uuid := '00000000-0000-0000-0000-000000009121';
  group_data jsonb;
begin
  insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,
    raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
    (admin_a,'authenticated','authenticated','gaps-a@test.local','',now(),'{}','{}',now(),now()),
    (admin_b,'authenticated','authenticated','gaps-b@test.local','',now(),'{}','{}',now(),now()),
    (customer_a,'authenticated','authenticated','gaps-c@test.local','',now(),'{}','{}',now(),now()),
    (duplicate_a,'authenticated','authenticated','gaps-d@test.local','',now(),'{}','{}',now(),now()),
    (other_tenant,'authenticated','authenticated','gaps-e@test.local','',now(),'{}','{}',now(),now());
  insert into public.profiles(id,name,phone,role,market_name,admin_id,created_by,
    approved,active,subscription_end) values
    (admin_a,'Market A','gaps-admin-a','admin','Market A',null,admin_a,true,true,now()+interval '30 days'),
    (admin_b,'Market B','gaps-admin-b','admin','Market B',null,admin_b,true,true,now()+interval '30 days'),
    (customer_a,'Same Customer','gaps-100','customer','',admin_a,admin_a,true,true,null),
    (duplicate_a,'Same Customer','gaps-101','customer','',admin_a,admin_a,true,true,null),
    (other_tenant,'Same Customer','gaps-102','customer','',admin_b,admin_b,true,true,null);
  perform set_config('request.jwt.claim.sub', admin_a::text, true);
  perform public.merge_my_duplicate_customer(customer_a, duplicate_a);
  group_data := public.get_my_customer_merge_group(customer_a);
  if jsonb_array_length(group_data->'customers') <> 2 then
    raise exception 'merge group did not preserve both identities';
  end if;
  begin
    perform public.merge_my_duplicate_customer(customer_a, other_tenant);
    raise exception 'cross-tenant customer merge was accepted';
  exception when insufficient_privilege then null;
  end;
  perform public.unmerge_my_duplicate_customer(duplicate_a);
  if exists (select 1 from public.customer_identity_merges where duplicate_id = duplicate_a) then
    raise exception 'unmerge left an identity link';
  end if;
  perform set_config('request.jwt.claim.sub', '', true);
end;
$test$;
select ok(true, 'merge/unmerge keeps identity and blocks cross-tenant requests');

select * from finish();
rollback;
