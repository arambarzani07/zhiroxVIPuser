-- Owner Account Recovery + Admin Device Authorization Center.
-- Platform/authentication metadata only; never reads tenant business content.

alter table public.owner_tenant_controls
  add column if not exists device_policy_mode text not null default 'observe';

create table if not exists public.platform_admin_devices (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  device_hash text not null,
  device_label text not null default 'ZHIROX app',
  platform text not null default 'unknown',
  app_version text not null default 'unknown',
  status text not null default 'pending',
  last_session_id uuid null,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  approved_at timestamptz null,
  approved_by uuid null references public.profiles(id) on delete set null,
  revoked_at timestamptz null,
  revoked_by uuid null references public.profiles(id) on delete set null,
  unique (admin_id, device_hash),
  constraint platform_admin_devices_status_check
    check (status in ('pending','approved','revoked'))
);

create index if not exists platform_admin_devices_admin_status_idx
  on public.platform_admin_devices(admin_id, status, last_seen_at desc);

create table if not exists public.platform_account_recovery_events (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  reason text not null default '',
  revoked_session_count integer not null default 0,
  reset_device_count integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists platform_account_recovery_events_admin_idx
  on public.platform_account_recovery_events(admin_id, created_at desc);

alter table public.platform_admin_devices enable row level security;
alter table public.platform_account_recovery_events enable row level security;

revoke all on table public.platform_admin_devices from public, anon, authenticated;
revoke all on table public.platform_account_recovery_events from public, anon, authenticated;

create or replace function public.register_platform_admin_device(
  p_device_id text,
  p_platform text default 'unknown',
  p_device_label text default 'ZHIROX app',
  p_app_version text default 'unknown'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_session_id uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  v_device_id text := trim(coalesce(p_device_id, ''));
  v_device_hash text;
  v_policy text := 'observe';
  v_device_limit integer := 5;
  v_existing_status text;
  v_status text;
  v_id uuid;
  v_approved_count integer := 0;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = v_uid
      and p.role = 'admin'
      and p.is_system_owner = false
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'admin_account_required' using errcode = '42501';
  end if;

  if length(v_device_id) < 16 or length(v_device_id) > 256 then
    raise exception 'invalid_device_id' using errcode = '22023';
  end if;

  v_device_hash := encode(
    extensions.digest(v_uid::text || ':' || v_device_id, 'sha256'),
    'hex'
  );

  select coalesce(c.device_policy_mode, 'observe'),
         coalesce(c.device_limit, 5)
    into v_policy, v_device_limit
  from public.owner_tenant_controls c
  where c.admin_id = v_uid;

  v_policy := coalesce(v_policy, 'observe');
  v_device_limit := greatest(coalesce(v_device_limit, 5), 1);

  select d.status
    into v_existing_status
  from public.platform_admin_devices d
  where d.admin_id = v_uid
    and d.device_hash = v_device_hash;

  if found then
    v_status := v_existing_status;
  else
    select count(*)::integer
      into v_approved_count
    from public.platform_admin_devices d
    where d.admin_id = v_uid
      and d.status = 'approved';

    v_status := case
      when v_policy = 'approval_required' then 'pending'
      when v_approved_count >= v_device_limit then 'pending'
      else 'approved'
    end;
  end if;

  insert into public.platform_admin_devices (
    admin_id,
    device_hash,
    device_label,
    platform,
    app_version,
    status,
    last_session_id,
    first_seen_at,
    last_seen_at,
    approved_at
  ) values (
    v_uid,
    v_device_hash,
    left(coalesce(nullif(trim(p_device_label), ''), 'ZHIROX app'), 80),
    left(coalesce(nullif(trim(p_platform), ''), 'unknown'), 32),
    left(coalesce(nullif(trim(p_app_version), ''), 'unknown'), 40),
    v_status,
    v_session_id,
    now(),
    now(),
    case when v_status = 'approved' then now() else null end
  )
  on conflict (admin_id, device_hash) do update
    set device_label = excluded.device_label,
        platform = excluded.platform,
        app_version = excluded.app_version,
        last_session_id = excluded.last_session_id,
        last_seen_at = now()
  returning id, status into v_id, v_status;

  return jsonb_build_object(
    'device_id', v_id,
    'status', v_status,
    'policy', v_policy,
    'allowed', v_status = 'approved',
    'device_limit', v_device_limit
  );
end;
$$;

create or replace function public.get_system_owner_recovery_device_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
begin
  v_uid := private.require_system_owner();

  return jsonb_build_object(
    'admin_accounts', (
      select count(*)::integer
      from public.profiles a
      where a.role = 'admin' and a.is_system_owner = false
    ),
    'registered_devices', (
      select count(*)::integer from public.platform_admin_devices
    ),
    'pending_devices', (
      select count(*)::integer
      from public.platform_admin_devices d
      where d.status = 'pending'
    ),
    'revoked_devices', (
      select count(*)::integer
      from public.platform_admin_devices d
      where d.status = 'revoked'
    ),
    'approval_required_accounts', (
      select count(*)::integer
      from public.owner_tenant_controls c
      join public.profiles a on a.id = c.admin_id
      where a.role = 'admin'
        and a.is_system_owner = false
        and c.device_policy_mode = 'approval_required'
    ),
    'recoveries_30d', (
      select count(*)::integer
      from public.platform_account_recovery_events e
      where e.created_at >= now() - interval '30 days'
    ),
    'checked_at', now()
  );
end;
$$;

create or replace function public.get_system_owner_recovery_device_page(
  p_page integer default 1,
  p_per_page integer default 30
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
  v_per_page integer := least(greatest(coalesce(p_per_page, 30), 1), 100);
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
        'approved', a.approved,
        'device_policy_mode', coalesce(c.device_policy_mode, 'observe'),
        'device_limit', coalesce(c.device_limit, 5),
        'device_count', coalesce(dev.device_count, 0),
        'approved_device_count', coalesce(dev.approved_count, 0),
        'pending_device_count', coalesce(dev.pending_count, 0),
        'revoked_device_count', coalesce(dev.revoked_count, 0),
        'devices', coalesce(dev.devices, '[]'::jsonb),
        'last_recovery_at', rec.last_recovery_at,
        'recovery_count', coalesce(rec.recovery_count, 0)
      ) as item
    from public.profiles a
    left join public.owner_tenant_controls c on c.admin_id = a.id
    left join lateral (
      select
        count(*)::integer as device_count,
        count(*) filter (where d.status = 'approved')::integer as approved_count,
        count(*) filter (where d.status = 'pending')::integer as pending_count,
        count(*) filter (where d.status = 'revoked')::integer as revoked_count,
        jsonb_agg(
          jsonb_build_object(
            'id', d.id,
            'device_label', d.device_label,
            'platform', d.platform,
            'app_version', d.app_version,
            'status', d.status,
            'first_seen_at', d.first_seen_at,
            'last_seen_at', d.last_seen_at,
            'approved_at', d.approved_at,
            'revoked_at', d.revoked_at
          )
          order by d.last_seen_at desc, d.id desc
        ) as devices
      from public.platform_admin_devices d
      where d.admin_id = a.id
    ) dev on true
    left join lateral (
      select max(e.created_at) as last_recovery_at,
             count(*)::integer as recovery_count
      from public.platform_account_recovery_events e
      where e.admin_id = a.id
    ) rec on true
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

create or replace function public.set_system_owner_admin_device_policy(
  p_admin_id uuid,
  p_policy text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_policy text := lower(trim(coalesce(p_policy, '')));
begin
  v_uid := private.require_system_owner();

  if v_policy not in ('observe','approval_required') then
    raise exception 'invalid_device_policy' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.profiles a
    where a.id = p_admin_id
      and a.role = 'admin'
      and a.is_system_owner = false
  ) then
    raise exception 'admin_not_found' using errcode = 'P0002';
  end if;

  insert into public.owner_tenant_controls (
    admin_id, device_policy_mode, updated_at, updated_by
  ) values (
    p_admin_id, v_policy, now(), v_uid
  )
  on conflict (admin_id) do update
    set device_policy_mode = excluded.device_policy_mode,
        updated_at = now(),
        updated_by = v_uid;

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    v_uid,
    p_admin_id,
    'admin_device_policy_changed',
    jsonb_build_object('device_policy_mode', v_policy)
  );

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'device_policy_mode', v_policy
  );
end;
$$;

create or replace function public.set_system_owner_admin_device_authorization(
  p_device_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_status text := lower(trim(coalesce(p_status, '')));
  v_admin_id uuid;
  v_session_id uuid;
  v_device_limit integer := 5;
  v_approved_count integer := 0;
begin
  v_uid := private.require_system_owner();

  if v_status not in ('pending','approved','revoked') then
    raise exception 'invalid_device_status' using errcode = '22023';
  end if;

  select d.admin_id, d.last_session_id
    into v_admin_id, v_session_id
  from public.platform_admin_devices d
  where d.id = p_device_id;

  if not found then
    raise exception 'device_not_found' using errcode = 'P0002';
  end if;

  if v_status = 'approved' then
    select coalesce(c.device_limit, 5)
      into v_device_limit
    from public.owner_tenant_controls c
    where c.admin_id = v_admin_id;
    v_device_limit := greatest(coalesce(v_device_limit, 5), 1);

    select count(*)::integer
      into v_approved_count
    from public.platform_admin_devices d
    where d.admin_id = v_admin_id
      and d.status = 'approved'
      and d.id <> p_device_id;

    if v_approved_count >= v_device_limit then
      raise exception 'device_limit_reached' using errcode = '23514';
    end if;
  end if;

  update public.platform_admin_devices
     set status = v_status,
         approved_at = case when v_status = 'approved' then now() else approved_at end,
         approved_by = case when v_status = 'approved' then v_uid else approved_by end,
         revoked_at = case when v_status = 'revoked' then now() else null end,
         revoked_by = case when v_status = 'revoked' then v_uid else null end,
         last_seen_at = last_seen_at
   where id = p_device_id;

  if v_status = 'revoked' and v_session_id is not null then
    update auth.refresh_tokens
       set revoked = true,
           updated_at = now()
     where session_id = v_session_id
       and revoked = false;

    delete from auth.sessions
     where id = v_session_id;
  end if;

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    v_uid,
    v_admin_id,
    'admin_device_authorization_changed',
    jsonb_build_object(
      'device_registration_id', p_device_id,
      'status', v_status
    )
  );

  return jsonb_build_object(
    'device_id', p_device_id,
    'admin_id', v_admin_id,
    'status', v_status
  );
end;
$$;

create or replace function public.complete_system_owner_admin_recovery_service(
  p_actor_id uuid,
  p_admin_id uuid,
  p_reason text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sessions integer := 0;
  v_devices integer := 0;
  v_reason text := left(trim(coalesce(p_reason, '')), 500);
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = p_actor_id
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'system_owner_required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.profiles a
    where a.id = p_admin_id
      and a.role = 'admin'
      and a.is_system_owner = false
  ) then
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

  update public.platform_admin_devices
     set status = 'pending',
         last_session_id = null,
         approved_at = null,
         approved_by = null,
         revoked_at = null,
         revoked_by = null
   where admin_id = p_admin_id
     and status <> 'pending';

  get diagnostics v_devices = row_count;

  insert into public.platform_account_recovery_events (
    admin_id,
    actor_id,
    reason,
    revoked_session_count,
    reset_device_count
  ) values (
    p_admin_id,
    p_actor_id,
    v_reason,
    v_sessions,
    v_devices
  );

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    p_actor_id,
    p_admin_id,
    'admin_account_recovered',
    jsonb_build_object(
      'revoked_session_count', v_sessions,
      'reset_device_count', v_devices,
      'reason', v_reason
    )
  );

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'revoked_session_count', v_sessions,
    'reset_device_count', v_devices
  );
end;
$$;

revoke all on function public.register_platform_admin_device(text,text,text,text)
  from public, anon;
revoke all on function public.get_system_owner_recovery_device_overview()
  from public, anon;
revoke all on function public.get_system_owner_recovery_device_page(integer,integer)
  from public, anon;
revoke all on function public.set_system_owner_admin_device_policy(uuid,text)
  from public, anon;
revoke all on function public.set_system_owner_admin_device_authorization(uuid,text)
  from public, anon;
revoke all on function public.complete_system_owner_admin_recovery_service(uuid,uuid,text)
  from public, anon, authenticated;

grant execute on function public.register_platform_admin_device(text,text,text,text)
  to authenticated;
grant execute on function public.get_system_owner_recovery_device_overview()
  to authenticated;
grant execute on function public.get_system_owner_recovery_device_page(integer,integer)
  to authenticated;
grant execute on function public.set_system_owner_admin_device_policy(uuid,text)
  to authenticated;
grant execute on function public.set_system_owner_admin_device_authorization(uuid,text)
  to authenticated;
grant execute on function public.complete_system_owner_admin_recovery_service(uuid,uuid,text)
  to service_role;
