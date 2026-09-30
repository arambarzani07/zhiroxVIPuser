-- Enforce Owner permission governance on the first production control surfaces.
-- Root/full Owners remain backward-compatible; restricted Owners are scoped.

create or replace function public.get_system_owner_platform_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_total integer := 0;
  v_active integer := 0;
  v_suspended integer := 0;
  v_expiring_7 integer := 0;
  v_expired integer := 0;
begin
  perform private.assert_system_owner_permission(
    'owner_view_platform_dashboard', 'platform', null
  );

  select
    count(*)::integer,
    count(*) filter (
      where a.active = true
        and coalesce(c.lifecycle_status, 'active') not in ('suspended','archived')
    )::integer,
    count(*) filter (
      where a.active = false
         or coalesce(c.lifecycle_status, 'active') = 'suspended'
    )::integer,
    count(*) filter (
      where a.subscription_end is not null
        and a.subscription_end >= now()
        and a.subscription_end < now() + interval '7 days'
    )::integer,
    count(*) filter (
      where a.subscription_end is not null
        and a.subscription_end < now()
    )::integer
  into v_total, v_active, v_suspended, v_expiring_7, v_expired
  from public.profiles a
  left join public.owner_tenant_controls c on c.admin_id = a.id
  where a.role = 'admin'
    and a.is_system_owner = false;

  return jsonb_build_object(
    'total_tenants', v_total,
    'active_tenants', v_active,
    'suspended_tenants', v_suspended,
    'expiring_7_days', v_expiring_7,
    'expired_tenants', v_expired
  );
end;
$$;

create or replace function public.get_system_owner_tenants_page(
  p_page integer default 1,
  p_per_page integer default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_page integer := greatest(coalesce(p_page, 1), 1);
  v_per_page integer := least(greatest(coalesce(p_per_page, 20), 1), 100);
  v_total integer;
  v_items jsonb;
begin
  perform private.assert_system_owner_permission(
    'owner_view_all_markets', 'platform', null
  );

  select count(*)::integer
    into v_total
  from public.profiles a
  where a.role = 'admin'
    and a.is_system_owner = false;

  select coalesce(jsonb_agg(item order by created_at desc, id desc), '[]'::jsonb)
    into v_items
  from (
    select
      a.id,
      a.created_at,
      jsonb_build_object(
        'id', a.id,
        'market_name', a.market_name,
        'admin_name', a.name,
        'phone', a.phone,
        'active', a.active,
        'approved', a.approved,
        'subscription_plan', a.subscription_plan,
        'subscription_end', a.subscription_end,
        'created_at', a.created_at,
        'updated_at', a.updated_at,
        'lifecycle_status', coalesce(c.lifecycle_status, case when a.active then 'active' else 'suspended' end),
        'support_tier', coalesce(c.support_tier, 'standard'),
        'device_limit', coalesce(c.device_limit, 5),
        'staff_limit', coalesce(c.staff_limit, 3),
        'platform_note', coalesce(c.platform_note, '')
      ) as item
    from public.profiles a
    left join public.owner_tenant_controls c on c.admin_id = a.id
    where a.role = 'admin'
      and a.is_system_owner = false
    order by a.created_at desc, a.id desc
    offset (v_page - 1) * v_per_page
    limit v_per_page
  ) rows;

  return jsonb_build_object(
    'tenants', v_items,
    'total_items', v_total,
    'total_pages', greatest(1, ceil(v_total::numeric / v_per_page)::integer),
    'page', v_page
  );
end;
$$;

create or replace function public.set_system_owner_tenant_lifecycle(
  p_admin_id uuid,
  p_status text,
  p_reason text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_market_name text;
  v_active boolean;
  v_permission_key text;
begin
  v_uid := private.require_system_owner();

  if p_status not in ('trial','active','grace','suspended','archived') then
    raise exception 'invalid_lifecycle_status' using errcode = '22023';
  end if;

  v_permission_key := case p_status
    when 'trial' then 'owner_set_market_trial'
    when 'active' then 'owner_activate_market'
    when 'grace' then 'owner_set_market_grace'
    when 'suspended' then 'owner_suspend_market'
    when 'archived' then 'owner_archive_market'
  end;

  perform private.assert_system_owner_permission(
    v_permission_key, 'market', p_admin_id
  );

  select a.market_name
    into v_market_name
  from public.profiles a
  where a.id = p_admin_id
    and a.role = 'admin'
    and a.is_system_owner = false;

  if v_market_name is null then
    raise exception 'admin_not_found' using errcode = 'P0002';
  end if;

  v_active := p_status in ('trial','active','grace');

  insert into public.owner_tenant_controls (
    admin_id, lifecycle_status, updated_at, updated_by
  ) values (
    p_admin_id, p_status, now(), v_uid
  )
  on conflict (admin_id) do update
    set lifecycle_status = excluded.lifecycle_status,
        updated_at = now(),
        updated_by = v_uid;

  update public.profiles
     set active = v_active,
         updated_at = now()
   where id = p_admin_id;

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    v_uid,
    p_admin_id,
    'tenant_lifecycle_changed',
    jsonb_build_object(
      'permission_key', v_permission_key,
      'status', p_status,
      'reason', left(coalesce(p_reason, ''), 500),
      'market_name', v_market_name
    )
  );

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'lifecycle_status', p_status,
    'active', v_active,
    'permission_key', v_permission_key
  );
end;
$$;

create or replace function public.set_system_owner_tenant_limits(
  p_admin_id uuid,
  p_device_limit integer,
  p_staff_limit integer,
  p_support_tier text default 'standard'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_current_device integer := 5;
  v_current_staff integer := 3;
  v_current_support text := 'standard';
  v_support_permission text;
  v_permissions jsonb := '[]'::jsonb;
begin
  v_uid := private.require_system_owner();

  if p_device_limit < 1 or p_device_limit > 100
     or p_staff_limit < 0 or p_staff_limit > 1000
     or p_support_tier not in ('standard','priority','vip') then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = p_admin_id
      and role = 'admin'
      and is_system_owner = false
  ) then
    raise exception 'admin_not_found' using errcode = 'P0002';
  end if;

  select
    coalesce(c.device_limit, 5),
    coalesce(c.staff_limit, 3),
    coalesce(c.support_tier, 'standard')
  into v_current_device, v_current_staff, v_current_support
  from public.profiles a
  left join public.owner_tenant_controls c on c.admin_id = a.id
  where a.id = p_admin_id;

  if p_device_limit is distinct from v_current_device then
    perform private.assert_system_owner_permission(
      'owner_set_device_limit', 'market', p_admin_id
    );
    v_permissions := v_permissions || jsonb_build_array('owner_set_device_limit');
  end if;

  if p_staff_limit is distinct from v_current_staff then
    perform private.assert_system_owner_permission(
      'owner_set_employee_limit', 'market', p_admin_id
    );
    v_permissions := v_permissions || jsonb_build_array('owner_set_employee_limit');
  end if;

  if p_support_tier is distinct from v_current_support then
    v_support_permission := case p_support_tier
      when 'standard' then 'owner_set_support_standard'
      when 'priority' then 'owner_set_support_priority'
      when 'vip' then 'owner_set_support_vip'
    end;
    perform private.assert_system_owner_permission(
      v_support_permission, 'market', p_admin_id
    );
    v_permissions := v_permissions || jsonb_build_array(v_support_permission);
  end if;

  insert into public.owner_tenant_controls (
    admin_id, device_limit, staff_limit, support_tier, updated_at, updated_by
  ) values (
    p_admin_id, p_device_limit, p_staff_limit, p_support_tier, now(), v_uid
  )
  on conflict (admin_id) do update
    set device_limit = excluded.device_limit,
        staff_limit = excluded.staff_limit,
        support_tier = excluded.support_tier,
        updated_at = now(),
        updated_by = v_uid;

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    v_uid,
    p_admin_id,
    'tenant_limits_changed',
    jsonb_build_object(
      'permission_keys', v_permissions,
      'device_limit', p_device_limit,
      'staff_limit', p_staff_limit,
      'support_tier', p_support_tier
    )
  );

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'device_limit', p_device_limit,
    'staff_limit', p_staff_limit,
    'support_tier', p_support_tier,
    'permission_keys', v_permissions
  );
end;
$$;

create or replace function public.get_system_owner_entitlements_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_features integer := 0;
  v_rules integer := 0;
  v_overrides integer := 0;
  v_tenants_with_overrides integer := 0;
begin
  perform private.assert_system_owner_permission(
    'owner_view_feature_catalog', 'market', null
  );

  select count(*)::integer into v_features
  from public.platform_feature_catalog;

  select count(*)::integer into v_rules
  from public.platform_plan_entitlements;

  select count(*)::integer,
         count(distinct admin_id)::integer
    into v_overrides, v_tenants_with_overrides
  from public.owner_tenant_entitlement_overrides;

  return jsonb_build_object(
    'feature_count', coalesce(v_features, 0),
    'plan_rule_count', coalesce(v_rules, 0),
    'override_count', coalesce(v_overrides, 0),
    'tenants_with_overrides', coalesce(v_tenants_with_overrides, 0),
    'checked_at', now()
  );
end;
$$;

create or replace function public.get_system_owner_entitlements_page(
  p_page integer default 1,
  p_per_page integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_page integer := greatest(coalesce(p_page, 1), 1);
  v_per_page integer := least(greatest(coalesce(p_per_page, 50), 1), 100);
  v_total integer := 0;
  v_features jsonb := '[]'::jsonb;
  v_plans jsonb := '{}'::jsonb;
  v_items jsonb := '[]'::jsonb;
begin
  perform private.assert_system_owner_permission(
    'owner_view_feature_catalog', 'market', null
  );

  select count(*)::integer
    into v_total
  from public.profiles a
  where a.role = 'admin'
    and a.is_system_owner = false;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'feature_key', f.feature_key,
        'display_name', f.display_name,
        'description', f.description,
        'category', f.category,
        'default_enabled', f.default_enabled
      )
      order by f.sort_order, f.feature_key
    ),
    '[]'::jsonb
  )
  into v_features
  from public.platform_feature_catalog f;

  select coalesce(
    jsonb_object_agg(plan_key, feature_map),
    '{}'::jsonb
  )
  into v_plans
  from (
    select pe.plan_key,
           jsonb_object_agg(pe.feature_key, pe.enabled order by pe.feature_key) as feature_map
    from public.platform_plan_entitlements pe
    group by pe.plan_key
  ) plans;

  select coalesce(jsonb_agg(item order by sort_created desc, sort_id desc), '[]'::jsonb)
    into v_items
  from (
    select
      a.created_at as sort_created,
      a.id as sort_id,
      jsonb_build_object(
        'id', a.id,
        'market_name', coalesce(a.market_name, ''),
        'admin_name', coalesce(a.name, ''),
        'phone', coalesce(a.phone, ''),
        'active', a.active,
        'approved', a.approved,
        'feature_plan', coalesce(c.feature_plan, 'standard'),
        'support_tier', coalesce(c.support_tier, 'standard'),
        'device_limit', coalesce(c.device_limit, 5),
        'staff_limit', coalesce(c.staff_limit, 3),
        'override_count', coalesce(o.override_count, 0),
        'entitlements', coalesce(e.entitlements, '[]'::jsonb)
      ) as item
    from public.profiles a
    left join public.owner_tenant_controls c on c.admin_id = a.id
    left join lateral (
      select count(*)::integer as override_count
      from public.owner_tenant_entitlement_overrides x
      where x.admin_id = a.id
    ) o on true
    left join lateral (
      select jsonb_agg(
        jsonb_build_object(
          'feature_key', f.feature_key,
          'display_name', f.display_name,
          'enabled', coalesce(x.enabled, pe.enabled, f.default_enabled),
          'source', case
            when x.feature_key is not null then 'override'
            when pe.feature_key is not null then 'plan'
            else 'default'
          end
        )
        order by f.sort_order, f.feature_key
      ) as entitlements
      from public.platform_feature_catalog f
      left join public.platform_plan_entitlements pe
        on pe.plan_key = coalesce(c.feature_plan, 'standard')
       and pe.feature_key = f.feature_key
      left join public.owner_tenant_entitlement_overrides x
        on x.admin_id = a.id
       and x.feature_key = f.feature_key
    ) e on true
    where a.role = 'admin'
      and a.is_system_owner = false
    order by a.created_at desc, a.id desc
    offset (v_page - 1) * v_per_page
    limit v_per_page
  ) rows;

  return jsonb_build_object(
    'features', v_features,
    'plans', v_plans,
    'items', v_items,
    'total_items', v_total,
    'total_pages', greatest(1, ceil(v_total::numeric / v_per_page)::integer),
    'page', v_page
  );
end;
$$;

create or replace function public.set_system_owner_tenant_feature_plan(
  p_admin_id uuid,
  p_plan_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_plan text := lower(trim(coalesce(p_plan_key, '')));
begin
  v_uid := private.require_system_owner();
  perform private.assert_system_owner_permission(
    'owner_override_market_feature', 'market', p_admin_id
  );

  if v_plan not in ('standard','pro','vip') then
    raise exception 'invalid_feature_plan' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.profiles a
    where a.id = p_admin_id
      and a.role = 'admin'
      and a.is_system_owner = false
  ) then
    raise exception 'admin_not_found' using errcode = 'P0002';
  end if;

  insert into public.owner_tenant_controls (
    admin_id, feature_plan, updated_at, updated_by
  ) values (
    p_admin_id, v_plan, now(), v_uid
  )
  on conflict (admin_id) do update
    set feature_plan = excluded.feature_plan,
        updated_at = now(),
        updated_by = v_uid;

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    v_uid,
    p_admin_id,
    'tenant_feature_plan_changed',
    jsonb_build_object(
      'permission_key', 'owner_override_market_feature',
      'feature_plan', v_plan
    )
  );

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'feature_plan', v_plan,
    'permission_key', 'owner_override_market_feature'
  );
end;
$$;

create or replace function public.set_system_owner_plan_entitlement(
  p_plan_key text,
  p_feature_key text,
  p_enabled boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_plan text := lower(trim(coalesce(p_plan_key, '')));
  v_feature text := lower(trim(coalesce(p_feature_key, '')));
  v_permission_key text;
begin
  v_uid := private.require_system_owner();

  if v_plan not in ('standard','pro','vip') then
    raise exception 'invalid_feature_plan' using errcode = '22023';
  end if;

  v_permission_key := case v_plan
    when 'standard' then 'owner_edit_standard_plan_features'
    when 'pro' then 'owner_edit_pro_plan_features'
    when 'vip' then 'owner_edit_vip_plan_features'
  end;

  perform private.assert_system_owner_permission(
    v_permission_key, 'market', null
  );

  if not exists (
    select 1 from public.platform_feature_catalog f
    where f.feature_key = v_feature
  ) then
    raise exception 'feature_not_found' using errcode = 'P0002';
  end if;

  insert into public.platform_plan_entitlements (
    plan_key, feature_key, enabled, updated_at, updated_by
  ) values (
    v_plan, v_feature, p_enabled, now(), v_uid
  )
  on conflict (plan_key, feature_key) do update
    set enabled = excluded.enabled,
        updated_at = now(),
        updated_by = v_uid;

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    v_uid,
    null,
    'feature_plan_entitlement_changed',
    jsonb_build_object(
      'permission_key', v_permission_key,
      'feature_plan', v_plan,
      'feature_key', v_feature,
      'enabled', p_enabled
    )
  );

  return jsonb_build_object(
    'permission_key', v_permission_key,
    'feature_plan', v_plan,
    'feature_key', v_feature,
    'enabled', p_enabled
  );
end;
$$;

create or replace function public.set_system_owner_tenant_entitlement(
  p_admin_id uuid,
  p_feature_key text,
  p_enabled boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_feature text := lower(trim(coalesce(p_feature_key, '')));
  v_permission_key text;
begin
  v_uid := private.require_system_owner();

  v_permission_key := case
    when p_enabled is null then 'owner_clear_feature_override'
    when p_enabled = true then 'owner_enable_market_feature'
    else 'owner_disable_market_feature'
  end;

  perform private.assert_system_owner_permission(
    v_permission_key, 'market', p_admin_id
  );

  if not exists (
    select 1 from public.profiles a
    where a.id = p_admin_id
      and a.role = 'admin'
      and a.is_system_owner = false
  ) then
    raise exception 'admin_not_found' using errcode = 'P0002';
  end if;

  if not exists (
    select 1 from public.platform_feature_catalog f
    where f.feature_key = v_feature
  ) then
    raise exception 'feature_not_found' using errcode = 'P0002';
  end if;

  if p_enabled is null then
    delete from public.owner_tenant_entitlement_overrides
    where admin_id = p_admin_id
      and feature_key = v_feature;
  else
    insert into public.owner_tenant_entitlement_overrides (
      admin_id, feature_key, enabled, updated_at, updated_by
    ) values (
      p_admin_id, v_feature, p_enabled, now(), v_uid
    )
    on conflict (admin_id, feature_key) do update
      set enabled = excluded.enabled,
          updated_at = now(),
          updated_by = v_uid;
  end if;

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    v_uid,
    p_admin_id,
    'tenant_feature_entitlement_changed',
    jsonb_build_object(
      'permission_key', v_permission_key,
      'feature_key', v_feature,
      'enabled', p_enabled,
      'override_removed', p_enabled is null
    )
  );

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'permission_key', v_permission_key,
    'feature_key', v_feature,
    'enabled', p_enabled
  );
end;
$$;
