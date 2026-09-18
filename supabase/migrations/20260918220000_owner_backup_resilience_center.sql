-- Owner Backup & Resilience Center.
-- Strict privacy boundary: backup metadata and monitoring policy only.
-- Snapshot contents and tenant business-record statistics are intentionally never read.

create table if not exists public.owner_backup_monitoring_policies (
  admin_id uuid primary key references public.profiles(id) on delete cascade,
  expected_interval_hours integer not null default 48,
  verification_interval_days integer not null default 30,
  alert_enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by uuid null references public.profiles(id) on delete set null,
  constraint owner_backup_expected_interval_check
    check (expected_interval_hours between 6 and 168),
  constraint owner_backup_verification_interval_check
    check (verification_interval_days between 1 and 90)
);

alter table public.owner_backup_monitoring_policies enable row level security;
revoke all on table public.owner_backup_monitoring_policies
  from public, anon, authenticated;

create or replace function public.get_system_owner_backup_resilience_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_total integer := 0;
  v_healthy integer := 0;
  v_stale integer := 0;
  v_missing integer := 0;
  v_unverified integer := 0;
  v_verification_failed integer := 0;
begin
  v_uid := private.require_system_owner();

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
      'expected_interval_hours', v_expected,
      'verification_interval_days', v_verify,
      'alert_enabled', coalesce(p_alert_enabled, true)
    )
  );

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'expected_interval_hours', v_expected,
    'verification_interval_days', v_verify,
    'alert_enabled', coalesce(p_alert_enabled, true)
  );
end;
$$;

revoke all on function public.get_system_owner_backup_resilience_overview()
  from public, anon;
revoke all on function public.get_system_owner_backup_resilience_page(integer, integer)
  from public, anon;
revoke all on function public.set_system_owner_backup_monitoring_policy(uuid, integer, integer, boolean)
  from public, anon;

grant execute on function public.get_system_owner_backup_resilience_overview()
  to authenticated;
grant execute on function public.get_system_owner_backup_resilience_page(integer, integer)
  to authenticated;
grant execute on function public.set_system_owner_backup_monitoring_policy(uuid, integer, integer, boolean)
  to authenticated;
