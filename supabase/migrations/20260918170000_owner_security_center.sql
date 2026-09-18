-- Owner Security Center.
-- Privacy boundary: account/authentication metadata only.
-- Never reads customer, debt, payment-ledger, receipt, note, or market business content.

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
      (a.active = false or au.banned_until > now()) as locked,
      coalesce(c.device_limit, 5) as device_limit,
      count(s.id) filter (
        where s.not_after is null or s.not_after > now()
      )::integer as active_sessions,
      count(distinct s.ip) filter (
        where s.ip is not null
          and s.updated_at >= now() - interval '24 hours'
      )::integer as recent_ip_count_24h
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
          or active_sessions > device_limit
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
        'locked', (a.active = false or au.banned_until > now()),
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
            when a.active = false or au.banned_until > now() then 'locked'
            when coalesce(sec.recent_ip_count_24h, 0) >= 3
              or coalesce(sec.active_sessions, 0) > coalesce(c.device_limit, 5)
              then 'review'
            else 'normal'
          end
      ) as item
    from public.profiles a
    left join auth.users au on au.id = a.id
    left join public.owner_tenant_controls c on c.admin_id = a.id
    left join lateral (
      select
        count(s.id) filter (
          where s.not_after is null or s.not_after > now()
        )::integer as active_sessions,
        count(s.id) filter (
          where (s.not_after is null or s.not_after > now())
            and s.aal::text = 'aal2'
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

create or replace function public.revoke_system_owner_admin_sessions(
  p_admin_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_market_name text := '';
  v_sessions integer := 0;
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

  select coalesce(a.market_name, '')
    into v_market_name
  from public.profiles a
  where a.id = p_admin_id
    and a.role = 'admin'
    and a.is_system_owner = false;

  if not found then
    raise exception 'admin_not_found' using errcode = 'P0002';
  end if;

  select count(*)::integer
    into v_sessions
  from auth.sessions s
  where s.user_id = p_admin_id;

  update auth.refresh_tokens
     set revoked = true,
         updated_at = now()
   where user_id = p_admin_id::text
     and revoked = false;

  delete from auth.sessions
   where user_id = p_admin_id;

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    v_uid,
    p_admin_id,
    'admin_sessions_revoked',
    jsonb_build_object(
      'revoked_session_count', v_sessions,
      'market_name', v_market_name
    )
  );

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'revoked_session_count', v_sessions
  );
end;
$$;

create or replace function public.set_system_owner_admin_lock(
  p_admin_id uuid,
  p_locked boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_market_name text := '';
  v_sessions integer := 0;
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

  select coalesce(a.market_name, '')
    into v_market_name
  from public.profiles a
  where a.id = p_admin_id
    and a.role = 'admin'
    and a.is_system_owner = false;

  if not found then
    raise exception 'admin_not_found' using errcode = 'P0002';
  end if;

  update public.profiles
     set active = not p_locked,
         updated_at = now()
   where id = p_admin_id;

  update auth.users
     set banned_until = case
           when p_locked then now() + interval '100 years'
           else null
         end,
         updated_at = now()
   where id = p_admin_id;

  insert into public.owner_tenant_controls (
    admin_id, lifecycle_status, updated_at, updated_by
  ) values (
    p_admin_id,
    case when p_locked then 'suspended' else 'active' end,
    now(),
    v_uid
  )
  on conflict (admin_id) do update
    set lifecycle_status = excluded.lifecycle_status,
        updated_at = now(),
        updated_by = v_uid;

  if p_locked then
    select count(*)::integer
      into v_sessions
    from auth.sessions s
    where s.user_id = p_admin_id;

    update auth.refresh_tokens
       set revoked = true,
           updated_at = now()
     where user_id = p_admin_id::text
       and revoked = false;

    delete from auth.sessions
     where user_id = p_admin_id;
  end if;

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    v_uid,
    p_admin_id,
    case when p_locked then 'admin_account_locked' else 'admin_account_unlocked' end,
    jsonb_build_object(
      'locked', p_locked,
      'revoked_session_count', v_sessions,
      'market_name', v_market_name
    )
  );

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'locked', p_locked,
    'active', not p_locked,
    'revoked_session_count', v_sessions
  );
end;
$$;

revoke all on function public.get_system_owner_security_overview()
  from public, anon;
revoke all on function public.get_system_owner_security_page(integer, integer)
  from public, anon;
revoke all on function public.revoke_system_owner_admin_sessions(uuid)
  from public, anon;
revoke all on function public.set_system_owner_admin_lock(uuid, boolean)
  from public, anon;

grant execute on function public.get_system_owner_security_overview()
  to authenticated;
grant execute on function public.get_system_owner_security_page(integer, integer)
  to authenticated;
grant execute on function public.revoke_system_owner_admin_sessions(uuid)
  to authenticated;
grant execute on function public.set_system_owner_admin_lock(uuid, boolean)
  to authenticated;
