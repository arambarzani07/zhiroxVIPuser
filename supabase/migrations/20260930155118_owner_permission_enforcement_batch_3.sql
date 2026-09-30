-- Owner permission enforcement batch 3: Backup/Resilience + Device/Recovery.
-- Keeps backup access metadata-only and closes the account-recovery gap by
-- authorizing delegated Owners before the Edge Function changes a password.

create or replace function public.get_system_owner_recovery_device_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.assert_system_owner_permission(
    'owner_view_admin_devices', 'admin', null
  );

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
  v_page integer := greatest(coalesce(p_page, 1), 1);
  v_per_page integer := least(greatest(coalesce(p_per_page, 30), 1), 100);
  v_total integer := 0;
  v_items jsonb := '[]'::jsonb;
begin
  perform private.assert_system_owner_permission(
    'owner_view_admin_profile', 'admin', null
  );
  perform private.assert_system_owner_permission(
    'owner_view_admin_devices', 'admin', null
  );
  perform private.assert_system_owner_permission(
    'owner_view_admin_status', 'admin', null
  );

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
  v_permission_key text;
begin
  v_uid := private.require_system_owner();

  if v_policy not in ('observe','approval_required') then
    raise exception 'invalid_device_policy' using errcode = '22023';
  end if;

  v_permission_key := case
    when v_policy = 'approval_required' then 'owner_block_device'
    else 'owner_unblock_device'
  end;

  perform private.assert_system_owner_permission(
    v_permission_key, 'admin', p_admin_id
  );

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
    jsonb_build_object(
      'permission_key', v_permission_key,
      'device_policy_mode', v_policy
    )
  );

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'device_policy_mode', v_policy,
    'permission_key', v_permission_key
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
  v_permission_key text;
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

  v_permission_key := case
    when v_status = 'approved' then 'owner_unblock_device'
    when v_status = 'revoked' then 'owner_revoke_admin_device'
    else 'owner_block_device'
  end;

  perform private.assert_system_owner_permission(
    v_permission_key, 'admin', v_admin_id
  );

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
      'permission_key', v_permission_key,
      'device_registration_id', p_device_id,
      'status', v_status
    )
  );

  return jsonb_build_object(
    'device_id', p_device_id,
    'admin_id', v_admin_id,
    'status', v_status,
    'permission_key', v_permission_key
  );
end;
$$;

create or replace function public.authorize_system_owner_admin_recovery_service(
  p_actor_id uuid,
  p_admin_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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

  if not private.system_owner_has_permission(
    'owner_reset_admin_password', 'admin', p_admin_id, p_actor_id
  ) then
    raise exception 'owner_permission_denied:owner_reset_admin_password'
      using errcode = '42501';
  end if;

  if not private.system_owner_has_permission(
    'owner_revoke_admin_sessions', 'admin', p_admin_id, p_actor_id
  ) then
    raise exception 'owner_permission_denied:owner_revoke_admin_sessions'
      using errcode = '42501';
  end if;

  if not private.system_owner_has_permission(
    'owner_revoke_admin_device', 'admin', p_admin_id, p_actor_id
  ) then
    raise exception 'owner_permission_denied:owner_revoke_admin_device'
      using errcode = '42501';
  end if;

  return jsonb_build_object(
    'authorized', true,
    'admin_id', p_admin_id,
    'permission_keys', jsonb_build_array(
      'owner_reset_admin_password',
      'owner_revoke_admin_sessions',
      'owner_revoke_admin_device'
    )
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

  if not private.system_owner_has_permission(
    'owner_reset_admin_password', 'admin', p_admin_id, p_actor_id
  ) then
    raise exception 'owner_permission_denied:owner_reset_admin_password'
      using errcode = '42501';
  end if;
  if not private.system_owner_has_permission(
    'owner_revoke_admin_sessions', 'admin', p_admin_id, p_actor_id
  ) then
    raise exception 'owner_permission_denied:owner_revoke_admin_sessions'
      using errcode = '42501';
  end if;
  if not private.system_owner_has_permission(
    'owner_revoke_admin_device', 'admin', p_admin_id, p_actor_id
  ) then
    raise exception 'owner_permission_denied:owner_revoke_admin_device'
      using errcode = '42501';
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
      'permission_keys', jsonb_build_array(
        'owner_reset_admin_password',
        'owner_revoke_admin_sessions',
        'owner_revoke_admin_device'
      ),
      'revoked_session_count', v_sessions,
      'reset_device_count', v_devices,
      'reason', v_reason
    )
  );

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'revoked_session_count', v_sessions,
    'reset_device_count', v_devices,
    'permission_keys', jsonb_build_array(
      'owner_reset_admin_password',
      'owner_revoke_admin_sessions',
      'owner_revoke_admin_device'
    )
  );
end;
$$;

create or replace function public.get_system_owner_backup_resilience_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_total integer := 0;
  v_healthy integer := 0;
  v_stale integer := 0;
  v_missing integer := 0;
  v_unverified integer := 0;
  v_verification_failed integer := 0;
begin
  perform private.assert_system_owner_permission(
    'owner_view_backup_health', 'platform', null
  );

  with tenant_state as (
    select
      a.id,
      coalesce(pol.expected_interval_hours, 48) as expected_hours,
      coalesce(pol.verification_interval_days, 30) as verify_days,
      b.created_at as latest_backup_at,
      b.last_verified_at,
      case
        when b.verification ? 'restorable'
          then coalesce((b.verification ->> 'restorable')::boolean, false)
        else null
      end as restorable
    from public.profiles a
    left join public.owner_tenant_controls c on c.admin_id = a.id
    left join public.owner_backup_monitoring_policies pol on pol.admin_id = a.id
    left join lateral (
      select x.created_at, x.last_verified_at, x.verification
      from public.tenant_backups x
      where x.admin_id = a.id
      order by x.created_at desc, x.id desc
      limit 1
    ) b on true
    where a.role = 'admin'
      and a.is_system_owner = false
      and a.active = true
      and coalesce(c.lifecycle_status, 'active') not in ('suspended', 'archived')
  )
  select
    count(*)::integer,
    count(*) filter (
      where latest_backup_at is not null
        and latest_backup_at >= now() - make_interval(hours => expected_hours)
        and last_verified_at is not null
        and last_verified_at >= now() - make_interval(days => verify_days)
        and coalesce(restorable, true)
    )::integer,
    count(*) filter (
      where latest_backup_at is not null
        and latest_backup_at < now() - make_interval(hours => expected_hours)
    )::integer,
    count(*) filter (where latest_backup_at is null)::integer,
    count(*) filter (
      where latest_backup_at is not null
        and (
          last_verified_at is null
          or last_verified_at < now() - make_interval(days => verify_days)
        )
    )::integer,
    count(*) filter (
      where latest_backup_at is not null
        and restorable = false
    )::integer
  into
    v_total,
    v_healthy,
    v_stale,
    v_missing,
    v_unverified,
    v_verification_failed
  from tenant_state;

  return jsonb_build_object(
    'monitored_tenants', coalesce(v_total, 0),
    'healthy_tenants', coalesce(v_healthy, 0),
    'stale_tenants', coalesce(v_stale, 0),
    'missing_backup_tenants', coalesce(v_missing, 0),
    'verification_due_tenants', coalesce(v_unverified, 0),
    'verification_failed_tenants', coalesce(v_verification_failed, 0),
    'checked_at', now()
  );
end;
$$;

create or replace function public.get_system_owner_backup_resilience_page(
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
  v_items jsonb := '[]'::jsonb;
begin
  perform private.assert_system_owner_permission(
    'owner_view_backup_health', 'platform', null
  );
  perform private.assert_system_owner_permission(
    'owner_view_market_backups', 'market', null
  );

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
        'active', a.active,
        'lifecycle_status', coalesce(c.lifecycle_status, 'active'),
        'expected_interval_hours', coalesce(pol.expected_interval_hours, 48),
        'verification_interval_days', coalesce(pol.verification_interval_days, 30),
        'alert_enabled', coalesce(pol.alert_enabled, true),
        'latest_backup_at', b.created_at,
        'latest_backup_type', coalesce(b.backup_type, ''),
        'latest_backup_expires_at', b.expires_at,
        'last_verified_at', b.last_verified_at,
        'restorable',
          case
            when b.verification ? 'restorable'
              then coalesce((b.verification ->> 'restorable')::boolean, false)
            else null
          end,
        'backup_count', coalesce(bc.backup_count, 0),
        'automatic_backup_count', coalesce(bc.automatic_backup_count, 0),
        'health_state',
          case
            when b.created_at is null then 'missing'
            when b.verification ? 'restorable'
                 and coalesce((b.verification ->> 'restorable')::boolean, false) = false
              then 'verification_failed'
            when b.created_at < now() - make_interval(
              hours => coalesce(pol.expected_interval_hours, 48)
            ) then 'stale'
            when b.last_verified_at is null
              or b.last_verified_at < now() - make_interval(
                days => coalesce(pol.verification_interval_days, 30)
              ) then 'verification_due'
            else 'healthy'
          end
      ) as item
    from public.profiles a
    left join public.owner_tenant_controls c on c.admin_id = a.id
    left join public.owner_backup_monitoring_policies pol on pol.admin_id = a.id
    left join lateral (
      select
        x.created_at,
        x.backup_type,
        x.expires_at,
        x.last_verified_at,
        x.verification
      from public.tenant_backups x
      where x.admin_id = a.id
      order by x.created_at desc, x.id desc
      limit 1
    ) b on true
    left join lateral (
      select
        count(*)::integer as backup_count,
        count(*) filter (where x.backup_type = 'automatic')::integer
          as automatic_backup_count
      from public.tenant_backups x
      where x.admin_id = a.id
    ) bc on true
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

create or replace function public.set_system_owner_backup_monitoring_policy(
  p_admin_id uuid,
  p_expected_interval_hours integer,
  p_verification_interval_days integer,
  p_alert_enabled boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_expected integer := coalesce(p_expected_interval_hours, 48);
  v_verify integer := coalesce(p_verification_interval_days, 30);
begin
  v_uid := private.require_system_owner();

  perform private.assert_system_owner_permission(
    'owner_view_market_backups', 'market', p_admin_id
  );
  perform private.assert_system_owner_permission(
    'owner_verify_backup', 'platform', null
  );

  if v_expected < 6 or v_expected > 168 then
    raise exception 'invalid_backup_expected_interval' using errcode = '22023';
  end if;
  if v_verify < 1 or v_verify > 90 then
    raise exception 'invalid_backup_verification_interval' using errcode = '22023';
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

  insert into public.owner_backup_monitoring_policies (
    admin_id,
    expected_interval_hours,
    verification_interval_days,
    alert_enabled,
    updated_at,
    updated_by
  ) values (
    p_admin_id,
    v_expected,
    v_verify,
    coalesce(p_alert_enabled, true),
    now(),
    v_uid
  )
  on conflict (admin_id) do update
    set expected_interval_hours = excluded.expected_interval_hours,
        verification_interval_days = excluded.verification_interval_days,
        alert_enabled = excluded.alert_enabled,
        updated_at = now(),
        updated_by = v_uid;

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    v_uid,
    p_admin_id,
    'backup_monitoring_policy_changed',
    jsonb_build_object(
      'permission_keys', jsonb_build_array(
        'owner_view_market_backups',
        'owner_verify_backup'
      ),
      'expected_interval_hours', v_expected,
      'verification_interval_days', v_verify,
      'alert_enabled', coalesce(p_alert_enabled, true)
    )
  );

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'expected_interval_hours', v_expected,
    'verification_interval_days', v_verify,
    'alert_enabled', coalesce(p_alert_enabled, true),
    'permission_keys', jsonb_build_array(
      'owner_view_market_backups',
      'owner_verify_backup'
    )
  );
end;
$$;

revoke all on function public.get_system_owner_recovery_device_overview()
  from public, anon;
revoke all on function public.get_system_owner_recovery_device_page(integer,integer)
  from public, anon;
revoke all on function public.set_system_owner_admin_device_policy(uuid,text)
  from public, anon;
revoke all on function public.set_system_owner_admin_device_authorization(uuid,text)
  from public, anon;
revoke all on function public.authorize_system_owner_admin_recovery_service(uuid,uuid)
  from public, anon, authenticated;
revoke all on function public.complete_system_owner_admin_recovery_service(uuid,uuid,text)
  from public, anon, authenticated;
revoke all on function public.get_system_owner_backup_resilience_overview()
  from public, anon;
revoke all on function public.get_system_owner_backup_resilience_page(integer,integer)
  from public, anon;
revoke all on function public.set_system_owner_backup_monitoring_policy(uuid,integer,integer,boolean)
  from public, anon;

grant execute on function public.get_system_owner_recovery_device_overview()
  to authenticated;
grant execute on function public.get_system_owner_recovery_device_page(integer,integer)
  to authenticated;
grant execute on function public.set_system_owner_admin_device_policy(uuid,text)
  to authenticated;
grant execute on function public.set_system_owner_admin_device_authorization(uuid,text)
  to authenticated;
grant execute on function public.authorize_system_owner_admin_recovery_service(uuid,uuid)
  to service_role;
grant execute on function public.complete_system_owner_admin_recovery_service(uuid,uuid,text)
  to service_role;
grant execute on function public.get_system_owner_backup_resilience_overview()
  to authenticated;
grant execute on function public.get_system_owner_backup_resilience_page(integer,integer)
  to authenticated;
grant execute on function public.set_system_owner_backup_monitoring_policy(uuid,integer,integer,boolean)
  to authenticated;
