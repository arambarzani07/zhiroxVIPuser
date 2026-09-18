-- Refine Owner Security Center risk scoring.
-- Device limit applies to distinct devices, not authentication session count.
-- Raw IP and user-agent values remain private and are never returned.

create or replace function public.get_system_owner_security_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_total integer := 0;
  v_locked integer := 0;
  v_active_sessions integer := 0;
  v_review integer := 0;
begin
  if v_uid is null or not exists (
    select 1 from public.profiles p
    where p.id = v_uid
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'system_owner_required' using errcode = '42501';
  end if;

  with tenant_security as (
    select
      a.id,
      (a.active = false or coalesce(au.banned_until > now(), false)) as locked,
      coalesce(c.device_limit, 5) as device_limit,
      count(distinct s.id) filter (
        where exists (
          select 1
          from auth.refresh_tokens rt
          where rt.session_id = s.id
            and rt.revoked = false
        )
      )::integer as active_sessions,
      count(distinct s.ip) filter (
        where s.ip is not null
          and s.updated_at >= now() - interval '24 hours'
      )::integer as recent_ip_count_24h,
      count(distinct s.user_agent) filter (
        where coalesce(s.user_agent, '') <> ''
          and s.updated_at >= now() - interval '30 days'
      )::integer as recent_device_count_30d
    from public.profiles a
    left join auth.users au on au.id = a.id
    left join public.owner_tenant_controls c on c.admin_id = a.id
    left join auth.sessions s on s.user_id = a.id
    where a.role = 'admin'
      and a.is_system_owner = false
    group by a.id, a.active, au.banned_until, c.device_limit
  )
  select
    count(*)::integer,
    count(*) filter (where locked)::integer,
    coalesce(sum(active_sessions), 0)::integer,
    count(*) filter (
      where not locked
        and (
          recent_ip_count_24h >= 3
          or recent_device_count_30d > device_limit
        )
    )::integer
  into v_total, v_locked, v_active_sessions, v_review
  from tenant_security;

  return jsonb_build_object(
    'total_admin_accounts', coalesce(v_total, 0),
    'locked_admin_accounts', coalesce(v_locked, 0),
    'active_sessions', coalesce(v_active_sessions, 0),
    'accounts_needing_review', coalesce(v_review, 0),
    'checked_at', now()
  );
end;
$$;

create or replace function public.get_system_owner_security_page(
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
  v_total integer := 0;
  v_items jsonb := '[]'::jsonb;
begin
  if v_uid is null or not exists (
    select 1 from public.profiles p
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
        'locked', (a.active = false or coalesce(au.banned_until > now(), false)),
        'last_sign_in_at', au.last_sign_in_at,
        'banned_until', au.banned_until,
        'active_sessions', coalesce(sec.active_sessions, 0),
        'aal2_sessions', coalesce(sec.aal2_sessions, 0),
        'recent_ip_count_24h', coalesce(sec.recent_ip_count_24h, 0),
        'recent_device_count_30d', coalesce(sec.recent_device_count_30d, 0),
        'last_session_at', sec.last_session_at,
        'device_limit', coalesce(c.device_limit, 5),
        'security_state',
          case
            when a.active = false or coalesce(au.banned_until > now(), false)
              then 'locked'
            when coalesce(sec.recent_ip_count_24h, 0) >= 3
              or coalesce(sec.recent_device_count_30d, 0) > coalesce(c.device_limit, 5)
              then 'review'
            else 'normal'
          end
      ) as item
    from public.profiles a
    left join auth.users au on au.id = a.id
    left join public.owner_tenant_controls c on c.admin_id = a.id
    left join lateral (
      select
        count(distinct s.id) filter (
          where exists (
            select 1
            from auth.refresh_tokens rt
            where rt.session_id = s.id
              and rt.revoked = false
          )
        )::integer as active_sessions,
        count(distinct s.id) filter (
          where s.aal::text = 'aal2'
            and exists (
              select 1
              from auth.refresh_tokens rt
              where rt.session_id = s.id
                and rt.revoked = false
            )
        )::integer as aal2_sessions,
        count(distinct s.ip) filter (
          where s.ip is not null
            and s.updated_at >= now() - interval '24 hours'
        )::integer as recent_ip_count_24h,
        count(distinct s.user_agent) filter (
          where coalesce(s.user_agent, '') <> ''
            and s.updated_at >= now() - interval '30 days'
        )::integer as recent_device_count_30d,
        max(s.updated_at) as last_session_at
      from auth.sessions s
      where s.user_id = a.id
    ) sec on true
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
