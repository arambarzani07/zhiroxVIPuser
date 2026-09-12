-- Run with a privileged migration/test connection. Every mutation is rolled back.
begin;

do $test$
declare
  v_profile_id uuid;
  v_tenant_id uuid;
  v_role text;
begin
  if has_table_privilege('authenticated', 'public.financial_events', 'TRUNCATE') then
    raise exception 'authenticated must not be able to truncate financial_events';
  end if;

  if not has_function_privilege(
    'authenticated',
    'private.employee_has_permission(text)',
    'EXECUTE'
  ) then
    raise exception 'authenticated cannot evaluate employee-aware RLS policies';
  end if;

  if has_function_privilege(
    'anon',
    'public.get_admin_dashboard_snapshot()',
    'EXECUTE'
  ) or not has_function_privilege(
    'authenticated',
    'public.get_admin_dashboard_snapshot()',
    'EXECUTE'
  ) then
    raise exception 'dashboard snapshot grants are unsafe';
  end if;

  if (select prosecdef from pg_proc
      where oid = 'public.create_tenant_backup(text,text)'::regprocedure)
     or (select prosecdef from pg_proc
         where oid = 'public.get_tenant_export()'::regprocedure) then
    raise exception 'exposed governance RPC must remain security invoker';
  end if;

  if has_function_privilege(
    'anon', 'private.create_tenant_backup_impl(text,text)', 'EXECUTE'
  ) or has_function_privilege(
    'anon', 'private.get_tenant_export_impl()', 'EXECUTE'
  ) then
    raise exception 'anonymous role can execute private governance implementation';
  end if;

  if (select count(*) from pg_policies
      where schemaname = 'public'
        and tablename = 'employee_permissions'
        and cmd = 'SELECT') <> 1 then
    raise exception 'employee permissions must have exactly one select policy';
  end if;

  if not has_table_privilege('authenticated', 'public.financial_events', 'SELECT') then
    raise exception 'authenticated must retain select access to financial_events';
  end if;

  select p.id, p.admin_id, p.role
    into v_profile_id, v_tenant_id, v_role
  from public.profiles p
  where p.is_system_owner = false
    and p.admin_id is not null
  order by p.created_at
  limit 1;

  if v_profile_id is null or v_tenant_id is null then
    raise exception 'a tenant member fixture is required for operational access regression';
  end if;

  update public.profiles
     set active = true,
         approved = true
   where id = v_profile_id;

  update public.profiles
     set active = true,
         approved = true,
         subscription_end = now() + interval '1 day'
   where id = v_tenant_id;

  perform set_config('request.jwt.claim.sub', v_profile_id::text, true);

  if private."current_role"() is distinct from v_role then
    raise exception 'active subscribed tenant member should be operational';
  end if;

  perform set_config('request.jwt.claim.sub', null, true);
  update public.profiles
     set subscription_end = now() - interval '1 second'
   where id = v_tenant_id;

  perform set_config('request.jwt.claim.sub', v_profile_id::text, true);

  if private."current_role"() is not null
     or private.current_admin_id() is not null then
    raise exception 'expired tenant retained operational access';
  end if;

  perform set_config('request.jwt.claim.sub', null, true);
  update public.profiles
     set subscription_end = now() + interval '1 day'
   where id = v_tenant_id;

  update public.profiles
     set active = false
   where id = v_profile_id;

  perform set_config('request.jwt.claim.sub', v_profile_id::text, true);

  if private."current_role"() is not null
     or private.current_admin_id() is not null then
    raise exception 'inactive tenant member retained operational access';
  end if;
end
$test$;

rollback;

select 'operational access regression passed' as result;
