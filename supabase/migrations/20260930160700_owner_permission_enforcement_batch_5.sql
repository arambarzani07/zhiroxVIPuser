-- Owner permission enforcement batch 5: close remaining legacy Owner RPC gaps.
-- Existing function bodies are preserved from prior migrations; this batch
-- deterministically injects the central permission guard after the main BEGIN.

do $$
declare
  r record;
  v_def text;
  v_marker text := E'\nbegin\n';
  v_pos integer;
  v_guard text;
begin
  for r in
    select * from (values
      ('public.get_system_owner_admins_page(integer,integer)'::regprocedure, 'owner_view_all_admins', 'platform', 'null'),
      ('public.get_system_owner_branding_overview()'::regprocedure, 'owner_view_all_markets', 'platform', 'null'),
      ('public.get_system_owner_branding_page(integer,integer)'::regprocedure, 'owner_view_all_markets', 'platform', 'null'),
      ('public.get_system_owner_domain_check_target(uuid)'::regprocedure, 'owner_view_market_profile', 'market', 'p_admin_id'),
      ('public.get_system_owner_domain_overview()'::regprocedure, 'owner_view_all_markets', 'platform', 'null'),
      ('public.get_system_owner_domain_page(integer,integer)'::regprocedure, 'owner_view_all_markets', 'platform', 'null'),
      ('public.get_system_owner_health_overview()'::regprocedure, 'owner_view_platform_metrics', 'platform', 'null'),
      ('public.get_system_owner_incident_overview()'::regprocedure, 'owner_view_platform_activity', 'platform', 'null'),
      ('public.get_system_owner_incidents_page(integer,integer)'::regprocedure, 'owner_view_platform_activity', 'platform', 'null'),
      ('public.get_system_owner_infrastructure_jobs_page(integer,integer)'::regprocedure, 'owner_view_queue_health', 'platform', 'null'),
      ('public.get_system_owner_infrastructure_overview()'::regprocedure, 'owner_view_backend_health', 'platform', 'null'),
      ('public.get_system_owner_platform_audit_page(integer,integer)'::regprocedure, 'owner_view_owner_audit', 'platform', 'null'),
      ('public.get_system_owner_policy_overview()'::regprocedure, 'owner_view_platform_metrics', 'platform', 'null'),
      ('public.get_system_owner_policy_page(integer,integer)'::regprocedure, 'owner_view_platform_metrics', 'platform', 'null'),
      ('public.get_system_owner_readiness_overview()'::regprocedure, 'owner_view_all_markets', 'platform', 'null'),
      ('public.get_system_owner_readiness_page(integer,integer)'::regprocedure, 'owner_view_all_markets', 'platform', 'null'),
      ('public.set_system_owner_retention_policy(integer,integer,integer)'::regprocedure, 'owner_refresh_platform_config', 'platform', 'null'),
      ('public.set_system_owner_tenant_branding(uuid,boolean,text,text,text)'::regprocedure, 'owner_set_market_metadata', 'market', 'p_admin_id'),
      ('public.set_system_owner_tenant_domain(uuid,text,text)'::regprocedure, 'owner_set_market_metadata', 'market', 'p_admin_id'),
      ('public.update_system_owner_incident(uuid,text,text,text,text,text,boolean,timestamp with time zone)'::regprocedure, 'owner_refresh_platform_config', 'platform', 'null')
    ) as x(fn, permission_key, scope_type, scope_expr)
  loop
    select pg_get_functiondef(r.fn) into v_def;

    if position('private.assert_system_owner_permission' in v_def) > 0 then
      continue;
    end if;

    v_pos := strpos(v_def, v_marker);
    if v_pos = 0 then
      raise exception 'owner_permission_injection_pattern_missing:%', r.fn::text;
    end if;

    v_guard := format(
      E'\nbegin\n  perform private.assert_system_owner_permission(%L, %L, %s);\n',
      r.permission_key,
      r.scope_type,
      r.scope_expr
    );

    v_def := overlay(v_def placing v_guard from v_pos for char_length(v_marker));
    execute v_def;
  end loop;
end;
$$;

create or replace function public.get_system_owner_permission_catalog()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  perform private.assert_system_owner_permission(
    'owner_access_console', 'platform', null
  );
  return private.get_system_owner_permission_catalog_internal();
end;
$$;

revoke all on function public.get_system_owner_permission_catalog() from public, anon;
grant execute on function public.get_system_owner_permission_catalog() to authenticated;
