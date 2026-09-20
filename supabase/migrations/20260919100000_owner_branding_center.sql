-- Owner tenant branding center.
-- Platform metadata only. It does not read tenant business content.

insert into public.platform_feature_catalog (
  feature_key, display_name, description, category, default_enabled, sort_order
) values (
  'white_label_branding',
  'ناسنامەی تایبەتی مارکێت',
  'ناو، لۆگۆ و ڕەنگی تایبەتی مارکێت',
  'platform',
  false,
  70
)
on conflict (feature_key) do update
set display_name = excluded.display_name,
    description = excluded.description,
    category = excluded.category,
    sort_order = excluded.sort_order,
    updated_at = now();

insert into public.platform_plan_entitlements (
  plan_key, feature_key, enabled
) values
  ('standard', 'white_label_branding', false),
  ('pro', 'white_label_branding', false),
  ('vip', 'white_label_branding', true)
on conflict (plan_key, feature_key) do update
set enabled = excluded.enabled,
    updated_at = now();

create table if not exists public.owner_tenant_branding (
  admin_id uuid primary key references public.profiles(id) on delete cascade,
  branding_enabled boolean not null default false,
  brand_name text not null default '',
  logo_url text not null default '',
  primary_color_hex text not null default '#4459DB',
  updated_at timestamptz not null default now(),
  updated_by uuid null references public.profiles(id) on delete set null,
  constraint owner_tenant_branding_name_length
    check (char_length(brand_name) <= 120),
  constraint owner_tenant_branding_logo_length
    check (char_length(logo_url) <= 2048),
  constraint owner_tenant_branding_color_format
    check (primary_color_hex ~ '^#[0-9A-Fa-f]{6}$')
);

alter table public.owner_tenant_branding enable row level security;
revoke all on table public.owner_tenant_branding
  from public, anon, authenticated;

create or replace function public.get_system_owner_branding_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_configured integer := 0;
  v_enabled integer := 0;
  v_entitled integer := 0;
begin
  v_uid := private.require_system_owner();

  select count(*)::integer,
         count(*) filter (where b.branding_enabled)::integer
    into v_configured, v_enabled
  from public.owner_tenant_branding b
  join public.profiles a
    on a.id = b.admin_id
   and a.role = 'admin'
   and a.is_system_owner = false;

  select count(*)::integer
    into v_entitled
  from public.profiles a
  left join public.owner_tenant_controls c on c.admin_id = a.id
  left join public.owner_tenant_entitlement_overrides o
    on o.admin_id = a.id
   and o.feature_key = 'white_label_branding'
  left join public.platform_plan_entitlements pe
    on pe.plan_key = coalesce(c.feature_plan, 'standard')
   and pe.feature_key = 'white_label_branding'
  left join public.platform_feature_catalog f
    on f.feature_key = 'white_label_branding'
  where a.role = 'admin'
    and a.is_system_owner = false
    and coalesce(o.enabled, pe.enabled, f.default_enabled, false) = true;

  return jsonb_build_object(
    'configured_tenants', coalesce(v_configured, 0),
    'enabled_tenants', coalesce(v_enabled, 0),
    'entitled_tenants', coalesce(v_entitled, 0),
    'checked_at', now()
  );
end;
$$;

create or replace function public.get_system_owner_branding_page(
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
  v_items jsonb := '[]'::jsonb;
begin
  v_uid := private.require_system_owner();

  select count(*)::integer
    into v_total
  from public.profiles a
  where a.role = 'admin'
    and a.is_system_owner = false;

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
        'feature_plan', coalesce(c.feature_plan, 'standard'),
        'feature_enabled', coalesce(o.enabled, pe.enabled, f.default_enabled, false),
        'branding_enabled', coalesce(b.branding_enabled, false),
        'brand_name', coalesce(b.brand_name, ''),
        'logo_url', coalesce(b.logo_url, ''),
        'primary_color_hex', coalesce(b.primary_color_hex, '#4459DB'),
        'updated_at', b.updated_at
      ) as item
    from public.profiles a
    left join public.owner_tenant_controls c on c.admin_id = a.id
    left join public.owner_tenant_entitlement_overrides o
      on o.admin_id = a.id
     and o.feature_key = 'white_label_branding'
    left join public.platform_plan_entitlements pe
      on pe.plan_key = coalesce(c.feature_plan, 'standard')
     and pe.feature_key = 'white_label_branding'
    left join public.platform_feature_catalog f
      on f.feature_key = 'white_label_branding'
    left join public.owner_tenant_branding b on b.admin_id = a.id
    where a.role = 'admin'
      and a.is_system_owner = false
    order by a.created_at desc, a.id desc
    offset (v_page - 1) * v_per_page
    limit v_per_page
  ) rows;

  return jsonb_build_object(
    'items', v_items,
    'total_items', v_total,
    'total_pages', greatest(1, ceil(v_total::numeric / v_per_page)::integer),
    'page', v_page
  );
end;
$$;

create or replace function public.set_system_owner_tenant_branding(
  p_admin_id uuid,
  p_enabled boolean,
  p_brand_name text default '',
  p_logo_url text default '',
  p_primary_color_hex text default '#4459DB'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_brand_name text := trim(coalesce(p_brand_name, ''));
  v_logo_url text := trim(coalesce(p_logo_url, ''));
  v_color text := upper(trim(coalesce(p_primary_color_hex, '#4459DB')));
  v_entitled boolean := false;
begin
  v_uid := private.require_system_owner();

  if not exists (
    select 1
    from public.profiles a
    where a.id = p_admin_id
      and a.role = 'admin'
      and a.is_system_owner = false
  ) then
    raise exception 'admin_not_found' using errcode = 'P0002';
  end if;

  if char_length(v_brand_name) > 120 then
    raise exception 'invalid_brand_name' using errcode = '22023';
  end if;

  if char_length(v_logo_url) > 2048
     or (v_logo_url <> '' and v_logo_url !~ '^https://') then
    raise exception 'invalid_logo_url' using errcode = '22023';
  end if;

  if v_color !~ '^#[0-9A-F]{6}$' then
    raise exception 'invalid_primary_color' using errcode = '22023';
  end if;

  select coalesce(o.enabled, pe.enabled, f.default_enabled, false)
    into v_entitled
  from public.profiles a
  left join public.owner_tenant_controls c on c.admin_id = a.id
  left join public.owner_tenant_entitlement_overrides o
    on o.admin_id = a.id
   and o.feature_key = 'white_label_branding'
  left join public.platform_plan_entitlements pe
    on pe.plan_key = coalesce(c.feature_plan, 'standard')
   and pe.feature_key = 'white_label_branding'
  left join public.platform_feature_catalog f
    on f.feature_key = 'white_label_branding'
  where a.id = p_admin_id;

  if p_enabled and not coalesce(v_entitled, false) then
    raise exception 'feature_not_entitled' using errcode = '42501';
  end if;

  insert into public.owner_tenant_branding (
    admin_id,
    branding_enabled,
    brand_name,
    logo_url,
    primary_color_hex,
    updated_at,
    updated_by
  ) values (
    p_admin_id,
    p_enabled,
    v_brand_name,
    v_logo_url,
    v_color,
    now(),
    v_uid
  )
  on conflict (admin_id) do update
  set branding_enabled = excluded.branding_enabled,
      brand_name = excluded.brand_name,
      logo_url = excluded.logo_url,
      primary_color_hex = excluded.primary_color_hex,
      updated_at = now(),
      updated_by = v_uid;

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    v_uid,
    p_admin_id,
    'tenant_branding_changed',
    jsonb_build_object(
      'branding_enabled', p_enabled,
      'brand_name_configured', v_brand_name <> '',
      'logo_configured', v_logo_url <> '',
      'primary_color_hex', v_color
    )
  );

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'branding_enabled', p_enabled,
    'brand_name', v_brand_name,
    'logo_url', v_logo_url,
    'primary_color_hex', v_color
  );
end;
$$;

create or replace function public.get_platform_branding_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_admin_id uuid;
  v_entitled boolean := false;
  v_enabled boolean := false;
  v_brand_name text := '';
  v_logo_url text := '';
  v_color text := '#4459DB';
begin
  if v_uid is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  select
    case
      when p.role = 'admin' then p.id
      else p.admin_id
    end
  into v_admin_id
  from public.profiles p
  where p.id = v_uid
    and p.active = true
    and p.approved = true;

  if v_admin_id is null then
    raise exception 'tenant_not_found' using errcode = 'P0002';
  end if;

  select
    coalesce(o.enabled, pe.enabled, f.default_enabled, false),
    coalesce(b.branding_enabled, false),
    coalesce(b.brand_name, ''),
    coalesce(b.logo_url, ''),
    coalesce(b.primary_color_hex, '#4459DB')
  into
    v_entitled,
    v_enabled,
    v_brand_name,
    v_logo_url,
    v_color
  from public.profiles a
  left join public.owner_tenant_controls c on c.admin_id = a.id
  left join public.owner_tenant_entitlement_overrides o
    on o.admin_id = a.id
   and o.feature_key = 'white_label_branding'
  left join public.platform_plan_entitlements pe
    on pe.plan_key = coalesce(c.feature_plan, 'standard')
   and pe.feature_key = 'white_label_branding'
  left join public.platform_feature_catalog f
    on f.feature_key = 'white_label_branding'
  left join public.owner_tenant_branding b on b.admin_id = a.id
  where a.id = v_admin_id
    and a.role = 'admin';

  return jsonb_build_object(
    'enabled', coalesce(v_entitled, false) and coalesce(v_enabled, false),
    'brand_name', case
      when coalesce(v_entitled, false) and coalesce(v_enabled, false)
        then v_brand_name
      else ''
    end,
    'logo_url', case
      when coalesce(v_entitled, false) and coalesce(v_enabled, false)
        then v_logo_url
      else ''
    end,
    'primary_color_hex', case
      when coalesce(v_entitled, false) and coalesce(v_enabled, false)
        then v_color
      else '#4459DB'
    end
  );
end;
$$;

revoke all on function public.get_system_owner_branding_overview()
  from public, anon;
revoke all on function public.get_system_owner_branding_page(integer, integer)
  from public, anon;
revoke all on function public.set_system_owner_tenant_branding(uuid, boolean, text, text, text)
  from public, anon;
revoke all on function public.get_platform_branding_state()
  from public, anon;

grant execute on function public.get_system_owner_branding_overview()
  to authenticated;
grant execute on function public.get_system_owner_branding_page(integer, integer)
  to authenticated;
grant execute on function public.set_system_owner_tenant_branding(uuid, boolean, text, text, text)
  to authenticated;
grant execute on function public.get_platform_branding_state()
  to authenticated;
