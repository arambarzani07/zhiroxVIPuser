-- Owner Domain & HTTPS Center.
-- Platform routing metadata only. No tenant business content is read.

create table if not exists public.owner_tenant_domains (
  admin_id uuid primary key references public.profiles(id) on delete cascade,
  hostname text not null,
  routing_target text not null,
  verification_mode text not null default 'cname',
  dns_status text not null default 'pending',
  https_status text not null default 'unknown',
  last_http_status integer null,
  last_checked_at timestamptz null,
  check_detail text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid null references public.profiles(id) on delete set null,
  constraint owner_tenant_domains_mode_check
    check (verification_mode in ('cname')),
  constraint owner_tenant_domains_dns_check
    check (dns_status in ('pending','verified','mismatch','error')),
  constraint owner_tenant_domains_https_check
    check (https_status in ('unknown','reachable','unreachable','error')),
  constraint owner_tenant_domains_http_status_check
    check (last_http_status is null or (last_http_status between 100 and 599))
);

create unique index if not exists owner_tenant_domains_hostname_unique
  on public.owner_tenant_domains (lower(hostname));

alter table public.owner_tenant_domains enable row level security;
revoke all on table public.owner_tenant_domains from public, anon, authenticated;

create or replace function private.normalize_platform_hostname(p_value text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v text := lower(trim(coalesce(p_value, '')));
begin
  v := regexp_replace(v, '^https?://', '', 'i');
  v := split_part(v, '/', 1);
  v := regexp_replace(v, '\\.$', '');
  return v;
end;
$$;

create or replace function private.validate_platform_hostname(p_value text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select
    p_value ~ '^(?=.{1,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$'
    and p_value not in ('localhost')
    and p_value not like '%.local'
    and p_value not like '%.internal';
$$;

create or replace function public.get_system_owner_domain_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_total integer := 0;
  v_configured integer := 0;
  v_dns_verified integer := 0;
  v_https_reachable integer := 0;
  v_attention integer := 0;
begin
  v_uid := private.require_system_owner();

  select count(*)::integer
    into v_total
  from public.profiles a
  where a.role = 'admin'
    and a.is_system_owner = false;

  select
    count(*)::integer,
    count(*) filter (where d.dns_status = 'verified')::integer,
    count(*) filter (where d.https_status = 'reachable')::integer,
    count(*) filter (
      where d.dns_status <> 'verified'
         or d.https_status not in ('reachable','unknown')
    )::integer
  into v_configured, v_dns_verified, v_https_reachable, v_attention
  from public.owner_tenant_domains d;

  return jsonb_build_object(
    'tenant_count', coalesce(v_total, 0),
    'configured_domains', coalesce(v_configured, 0),
    'dns_verified', coalesce(v_dns_verified, 0),
    'https_reachable', coalesce(v_https_reachable, 0),
    'needs_attention', coalesce(v_attention, 0),
    'checked_at', now()
  );
end;
$$;

create or replace function public.get_system_owner_domain_page(
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
        'phone', coalesce(a.phone, ''),
        'active', a.active,
        'hostname', coalesce(d.hostname, ''),
        'routing_target', coalesce(d.routing_target, ''),
        'verification_mode', coalesce(d.verification_mode, 'cname'),
        'dns_status', coalesce(d.dns_status, 'pending'),
        'https_status', coalesce(d.https_status, 'unknown'),
        'last_http_status', d.last_http_status,
        'last_checked_at', d.last_checked_at,
        'check_detail', coalesce(d.check_detail, ''),
        'configured', (d.admin_id is not null)
      ) as item
    from public.profiles a
    left join public.owner_tenant_domains d on d.admin_id = a.id
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

create or replace function public.set_system_owner_tenant_domain(
  p_admin_id uuid,
  p_hostname text,
  p_routing_target text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_hostname text := private.normalize_platform_hostname(p_hostname);
  v_target text := private.normalize_platform_hostname(p_routing_target);
  v_market_name text := '';
begin
  v_uid := private.require_system_owner();

  select coalesce(a.market_name, '')
    into v_market_name
  from public.profiles a
  where a.id = p_admin_id
    and a.role = 'admin'
    and a.is_system_owner = false;

  if not found then
    raise exception 'admin_not_found' using errcode = 'P0002';
  end if;

  if v_hostname = '' then
    delete from public.owner_tenant_domains
    where admin_id = p_admin_id;

    insert into public.owner_platform_audit (
      actor_id, target_admin_id, action, metadata
    ) values (
      v_uid,
      p_admin_id,
      'tenant_domain_removed',
      jsonb_build_object('market_name', v_market_name)
    );

    return jsonb_build_object(
      'admin_id', p_admin_id,
      'configured', false
    );
  end if;

  if not private.validate_platform_hostname(v_hostname)
     or not private.validate_platform_hostname(v_target) then
    raise exception 'invalid_domain_hostname' using errcode = '22023';
  end if;

  insert into public.owner_tenant_domains (
    admin_id,
    hostname,
    routing_target,
    verification_mode,
    dns_status,
    https_status,
    last_http_status,
    last_checked_at,
    check_detail,
    created_at,
    updated_at,
    updated_by
  ) values (
    p_admin_id,
    v_hostname,
    v_target,
    'cname',
    'pending',
    'unknown',
    null,
    null,
    '',
    now(),
    now(),
    v_uid
  )
  on conflict (admin_id) do update
    set hostname = excluded.hostname,
        routing_target = excluded.routing_target,
        verification_mode = 'cname',
        dns_status = case
          when owner_tenant_domains.hostname is distinct from excluded.hostname
            or owner_tenant_domains.routing_target is distinct from excluded.routing_target
          then 'pending'
          else owner_tenant_domains.dns_status
        end,
        https_status = case
          when owner_tenant_domains.hostname is distinct from excluded.hostname
            or owner_tenant_domains.routing_target is distinct from excluded.routing_target
          then 'unknown'
          else owner_tenant_domains.https_status
        end,
        last_http_status = case
          when owner_tenant_domains.hostname is distinct from excluded.hostname
            or owner_tenant_domains.routing_target is distinct from excluded.routing_target
          then null
          else owner_tenant_domains.last_http_status
        end,
        last_checked_at = case
          when owner_tenant_domains.hostname is distinct from excluded.hostname
            or owner_tenant_domains.routing_target is distinct from excluded.routing_target
          then null
          else owner_tenant_domains.last_checked_at
        end,
        check_detail = case
          when owner_tenant_domains.hostname is distinct from excluded.hostname
            or owner_tenant_domains.routing_target is distinct from excluded.routing_target
          then ''
          else owner_tenant_domains.check_detail
        end,
        updated_at = now(),
        updated_by = v_uid;

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    v_uid,
    p_admin_id,
    'tenant_domain_changed',
    jsonb_build_object(
      'market_name', v_market_name,
      'hostname', v_hostname,
      'routing_target', v_target,
      'verification_mode', 'cname'
    )
  );

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'configured', true,
    'hostname', v_hostname,
    'routing_target', v_target,
    'dns_status', 'pending',
    'https_status', 'unknown'
  );
end;
$$;

create or replace function public.get_system_owner_domain_check_target(
  p_admin_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_result jsonb;
begin
  v_uid := private.require_system_owner();

  select jsonb_build_object(
    'admin_id', d.admin_id,
    'hostname', d.hostname,
    'routing_target', d.routing_target,
    'verification_mode', d.verification_mode
  )
  into v_result
  from public.owner_tenant_domains d
  join public.profiles a on a.id = d.admin_id
  where d.admin_id = p_admin_id
    and a.role = 'admin'
    and a.is_system_owner = false;

  if v_result is null then
    raise exception 'domain_not_configured' using errcode = 'P0002';
  end if;

  return v_result;
end;
$$;

create or replace function public.record_system_owner_domain_check(
  p_actor_id uuid,
  p_admin_id uuid,
  p_dns_status text,
  p_https_status text,
  p_http_status integer default null,
  p_detail text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old_dns text;
  v_old_https text;
  v_hostname text;
begin
  if not exists (
    select 1 from public.profiles p
    where p.id = p_actor_id
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'system_owner_required' using errcode = '42501';
  end if;

  if p_dns_status not in ('pending','verified','mismatch','error')
     or p_https_status not in ('unknown','reachable','unreachable','error') then
    raise exception 'invalid_domain_check_status' using errcode = '22023';
  end if;

  select d.dns_status, d.https_status, d.hostname
    into v_old_dns, v_old_https, v_hostname
  from public.owner_tenant_domains d
  where d.admin_id = p_admin_id
  for update;

  if not found then
    raise exception 'domain_not_configured' using errcode = 'P0002';
  end if;

  update public.owner_tenant_domains
  set dns_status = p_dns_status,
      https_status = p_https_status,
      last_http_status = p_http_status,
      last_checked_at = now(),
      check_detail = left(coalesce(p_detail, ''), 500),
      updated_at = now()
  where admin_id = p_admin_id;

  if v_old_dns is distinct from p_dns_status
     or v_old_https is distinct from p_https_status then
    insert into public.owner_platform_audit (
      actor_id, target_admin_id, action, metadata
    ) values (
      p_actor_id,
      p_admin_id,
      'tenant_domain_status_changed',
      jsonb_build_object(
        'hostname', v_hostname,
        'dns_status', p_dns_status,
        'https_status', p_https_status,
        'http_status', p_http_status
      )
    );
  end if;

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'dns_status', p_dns_status,
    'https_status', p_https_status,
    'http_status', p_http_status,
    'checked_at', now()
  );
end;
$$;

revoke all on function public.get_system_owner_domain_overview()
  from public, anon;
revoke all on function public.get_system_owner_domain_page(integer, integer)
  from public, anon;
revoke all on function public.set_system_owner_tenant_domain(uuid, text, text)
  from public, anon;
revoke all on function public.get_system_owner_domain_check_target(uuid)
  from public, anon;
revoke all on function public.record_system_owner_domain_check(uuid, uuid, text, text, integer, text)
  from public, anon, authenticated;

grant execute on function public.get_system_owner_domain_overview()
  to authenticated;
grant execute on function public.get_system_owner_domain_page(integer, integer)
  to authenticated;
grant execute on function public.set_system_owner_tenant_domain(uuid, text, text)
  to authenticated;
grant execute on function public.get_system_owner_domain_check_target(uuid)
  to authenticated;
grant execute on function public.record_system_owner_domain_check(uuid, uuid, text, text, integer, text)
  to service_role;
