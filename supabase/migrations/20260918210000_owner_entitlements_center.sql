-- Owner Feature Entitlements Center.
-- Platform metadata only: controls which platform capabilities a tenant may use.
-- No market business content is read or exposed.

alter table public.owner_tenant_controls
  add column if not exists feature_plan text not null default 'standard';

create table if not exists public.platform_feature_catalog (
  feature_key text primary key,
  display_name text not null,
  description text not null default '',
  category text not null default 'platform',
  default_enabled boolean not null default false,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_feature_catalog_key_check
    check (feature_key ~ '^[a-z][a-z0-9_]{1,63}$')
);

create table if not exists public.platform_plan_entitlements (
  plan_key text not null,
  feature_key text not null references public.platform_feature_catalog(feature_key) on delete cascade,
  enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid null references public.profiles(id) on delete set null,
  primary key (plan_key, feature_key),
  constraint platform_plan_entitlements_plan_check
    check (plan_key in ('standard','pro','vip'))
);

create table if not exists public.owner_tenant_entitlement_overrides (
  admin_id uuid not null references public.profiles(id) on delete cascade,
  feature_key text not null references public.platform_feature_catalog(feature_key) on delete cascade,
  enabled boolean not null,
  updated_at timestamptz not null default now(),
  updated_by uuid null references public.profiles(id) on delete set null,
  primary key (admin_id, feature_key)
);

alter table public.platform_feature_catalog enable row level security;
alter table public.platform_plan_entitlements enable row level security;
alter table public.owner_tenant_entitlement_overrides enable row level security;

revoke all on table public.platform_feature_catalog from public, anon, authenticated;
revoke all on table public.platform_plan_entitlements from public, anon, authenticated;
revoke all on table public.owner_tenant_entitlement_overrides from public, anon, authenticated;

insert into public.platform_feature_catalog (
  feature_key, display_name, description, category, default_enabled, sort_order
) values
  ('customer_notifications', 'ئاگادارکردنەوەی کڕیار', 'Web Push و ئاگادارکردنەوەی خۆکار/دەستی', 'communication', true, 10),
  ('automated_backup', 'Backup ـی خۆکار', 'Backup و health monitoring ـی پلاتفۆرم', 'resilience', true, 20),
  ('data_export', 'Export', 'Export ـی داتای خۆی tenant', 'data', false, 30),
  ('data_import', 'Import', 'Import ـی داتای خۆی tenant', 'data', false, 40),
  ('advanced_reports', 'ڕاپۆرتی پێشکەوتوو', 'ڕاپۆرت و analytics ـی پێشکەوتوو', 'analytics', false, 50),
  ('external_integrations', 'Integration ـە دەرەکییەکان', 'Webhook/API integration ـە ڕێگەپێدراوەکان', 'integration', false, 60)
on conflict (feature_key) do update
set display_name = excluded.display_name,
    description = excluded.description,
    category = excluded.category,
    sort_order = excluded.sort_order,
    updated_at = now();

insert into public.platform_plan_entitlements (plan_key, feature_key, enabled)
select p.plan_key, f.feature_key,
  case
    when p.plan_key = 'vip' then true
    when p.plan_key = 'pro' and f.feature_key in (
      'customer_notifications','automated_backup','data_export','data_import','advanced_reports'
    ) then true
    when p.plan_key = 'standard' and f.feature_key in (
      'customer_notifications','automated_backup'
    ) then true
    else false
  end
from (values ('standard'),('pro'),('vip')) as p(plan_key)
cross join public.platform_feature_catalog f
on conflict (plan_key, feature_key) do nothing;

create or replace function private.require_system_owner()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not exists (
    select 1
    from public.profiles p
    where p.id = v_uid
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'system_owner_required' using errcode = '42501';
  end if;
  return v_uid;
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
  v_uid uuid;
  v_features integer := 0;
  v_rules integer := 0;
  v_overrides integer := 0;
  v_tenants_with_overrides integer := 0;
begin
  v_uid := private.require_system_owner();

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
  v_uid uuid;
  v_page integer := greatest(coalesce(p_page, 1), 1);
  v_per_page integer := least(greatest(coalesce(p_per_page, 50), 1), 100);
  v_total integer := 0;
  v_features jsonb := '[]'::jsonb;
  v_plans jsonb := '{}'::jsonb;
  v_items jsonb := '[]'::jsonb;
begin
  v_uid := private.require_system_owner();

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
    jsonb_build_object('feature_plan', v_plan)
  );

  return jsonb_build_object('admin_id', p_admin_id, 'feature_plan', v_plan);
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
begin
  v_uid := private.require_system_owner();

  if v_plan not in ('standard','pro','vip') then
    raise exception 'invalid_feature_plan' using errcode = '22023';
  end if;

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
      'feature_plan', v_plan,
      'feature_key', v_feature,
      'enabled', p_enabled
    )
  );

  return jsonb_build_object(
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
begin
  v_uid := private.require_system_owner();

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
      'feature_key', v_feature,
      'enabled', p_enabled,
      'override_removed', p_enabled is null
    )
  );

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'feature_key', v_feature,
    'enabled', p_enabled
  );
end;
$$;

create or replace function public.get_platform_entitlements_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_admin_id uuid;
  v_plan text := 'standard';
  v_features jsonb := '{}'::jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select case
           when p.role = 'admin' then p.id
           when p.role = 'employee' then p.admin_id
           else null
         end
    into v_admin_id
  from public.profiles p
  where p.id = v_uid
    and p.active = true
    and p.approved = true;

  if v_admin_id is null then
    raise exception 'tenant_account_required' using errcode = '42501';
  end if;

  select coalesce(c.feature_plan, 'standard')
    into v_plan
  from public.owner_tenant_controls c
  where c.admin_id = v_admin_id;

  v_plan := coalesce(v_plan, 'standard');

  select coalesce(
    jsonb_object_agg(
      f.feature_key,
      coalesce(x.enabled, pe.enabled, f.default_enabled)
      order by f.feature_key
    ),
    '{}'::jsonb
  )
  into v_features
  from public.platform_feature_catalog f
  left join public.platform_plan_entitlements pe
    on pe.plan_key = v_plan
   and pe.feature_key = f.feature_key
  left join public.owner_tenant_entitlement_overrides x
    on x.admin_id = v_admin_id
   and x.feature_key = f.feature_key;

  return jsonb_build_object(
    'feature_plan', v_plan,
    'features', v_features,
    'checked_at', now()
  );
end;
$$;

revoke all on function public.get_system_owner_entitlements_overview()
  from public, anon;
revoke all on function public.get_system_owner_entitlements_page(integer, integer)
  from public, anon;
revoke all on function public.set_system_owner_tenant_feature_plan(uuid, text)
  from public, anon;
revoke all on function public.set_system_owner_plan_entitlement(text, text, boolean)
  from public, anon;
revoke all on function public.set_system_owner_tenant_entitlement(uuid, text, boolean)
  from public, anon;
revoke all on function public.get_platform_entitlements_state()
  from public, anon;

grant execute on function public.get_system_owner_entitlements_overview()
  to authenticated;
grant execute on function public.get_system_owner_entitlements_page(integer, integer)
  to authenticated;
grant execute on function public.set_system_owner_tenant_feature_plan(uuid, text)
  to authenticated;
grant execute on function public.set_system_owner_plan_entitlement(text, text, boolean)
  to authenticated;
grant execute on function public.set_system_owner_tenant_entitlement(uuid, text, boolean)
  to authenticated;
grant execute on function public.get_platform_entitlements_state()
  to authenticated;
