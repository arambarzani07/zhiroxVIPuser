-- Owner platform controls are intentionally limited to tenant/account metadata.
-- No market business content (customers, debts, payments, receipts, notes) is exposed.

create table if not exists public.owner_tenant_controls (
  admin_id uuid primary key references public.profiles(id) on delete cascade,
  lifecycle_status text not null default 'active'
    check (lifecycle_status in ('trial','active','grace','suspended','archived')),
  support_tier text not null default 'standard'
    check (support_tier in ('standard','priority','vip')),
  device_limit integer not null default 5 check (device_limit between 1 and 100),
  staff_limit integer not null default 3 check (staff_limit between 0 and 1000),
  platform_note text not null default '',
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null
);

create table if not exists public.owner_platform_audit (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references public.profiles(id) on delete restrict,
  target_admin_id uuid references public.profiles(id) on delete set null,
  action text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.owner_tenant_controls enable row level security;
alter table public.owner_platform_audit enable row level security;

revoke all privileges on table public.owner_tenant_controls from public, anon, authenticated;
revoke all privileges on table public.owner_platform_audit from public, anon, authenticated;
grant select, insert, update, delete on table public.owner_tenant_controls to service_role;
grant select, insert, update, delete on table public.owner_platform_audit to service_role;

create or replace function public.get_system_owner_platform_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_total integer := 0;
  v_active integer := 0;
  v_suspended integer := 0;
  v_expiring_7 integer := 0;
  v_expired integer := 0;
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
  v_uid uuid := auth.uid();
  v_page integer := greatest(coalesce(p_page, 1), 1);
  v_per_page integer := least(greatest(coalesce(p_per_page, 20), 1), 100);
  v_total integer;
  v_items jsonb;
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
  v_uid uuid := auth.uid();
  v_market_name text;
  v_active boolean;
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

  if p_status not in ('trial','active','grace','suspended','archived') then
    raise exception 'invalid_lifecycle_status' using errcode = '22023';
  end if;

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
      'status', p_status,
      'reason', left(coalesce(p_reason, ''), 500),
      'market_name', v_market_name
    )
  );

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'lifecycle_status', p_status,
    'active', v_active
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
      'device_limit', p_device_limit,
      'staff_limit', p_staff_limit,
      'support_tier', p_support_tier
    )
  );

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'device_limit', p_device_limit,
    'staff_limit', p_staff_limit,
    'support_tier', p_support_tier
  );
end;
$$;

revoke all on function public.get_system_owner_platform_overview() from public, anon;
revoke all on function public.get_system_owner_tenants_page(integer, integer) from public, anon;
revoke all on function public.set_system_owner_tenant_lifecycle(uuid, text, text) from public, anon;
revoke all on function public.set_system_owner_tenant_limits(uuid, integer, integer, text) from public, anon;

grant execute on function public.get_system_owner_platform_overview() to authenticated;
grant execute on function public.get_system_owner_tenants_page(integer, integer) to authenticated;
grant execute on function public.set_system_owner_tenant_lifecycle(uuid, text, text) to authenticated;
grant execute on function public.set_system_owner_tenant_limits(uuid, integer, integer, text) to authenticated;
