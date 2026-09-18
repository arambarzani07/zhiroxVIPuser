-- Owner Tenant Readiness Center.
-- Platform metadata only: account lifecycle, subscription, device posture,
-- backup freshness/verification, support SLA, and app telemetry.
-- No tenant business content is read.

create or replace function public.get_system_owner_readiness_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_total integer := 0;
  v_ready integer := 0;
  v_attention integer := 0;
  v_blocked integer := 0;
begin
  v_uid := private.require_system_owner();

  with readiness as (
    select
      a.id,
      (
        a.active = true
        and a.approved = true
        and coalesce(c.lifecycle_status, 'active') not in ('suspended','archived')
      ) as account_ready,
      (
        a.subscription_end is null
        or a.subscription_end >= now()
      ) as subscription_ready,
      (
        case
          when coalesce(c.device_policy_mode, 'observe') = 'approval_required'
            then coalesce(dev.approved_count, 0) > 0
                 and coalesce(dev.pending_count, 0) = 0
          else coalesce(dev.registered_count, 0) > 0
        end
      ) as device_ready,
      (
        bk.latest_backup_at is not null
        and bk.latest_backup_at >= now()
          - make_interval(hours => coalesce(bp.expected_interval_hours, 48))
      ) as backup_fresh,
      (
        bk.last_verified_at is not null
        and bk.last_verified_at >= now()
          - make_interval(days => coalesce(bp.verification_interval_days, 30))
        and coalesce(bk.restorable, false) = true
      ) as backup_verified,
      coalesce(sla.overdue_count, 0) = 0 as support_sla_ready,
      (
        dev.latest_device_seen_at is not null
        and dev.latest_device_seen_at >= now() - interval '30 days'
        and coalesce(dev.latest_app_version, '') not in ('', 'unknown')
      ) as app_telemetry_ready
    from public.profiles a
    left join public.owner_tenant_controls c on c.admin_id = a.id
    left join public.owner_backup_monitoring_policies bp on bp.admin_id = a.id
    left join lateral (
      select
        count(*)::integer as registered_count,
        count(*) filter (where d.status = 'approved')::integer as approved_count,
        count(*) filter (where d.status = 'pending')::integer as pending_count,
        max(d.last_seen_at) as latest_device_seen_at,
        (
          select d2.app_version
          from public.platform_admin_devices d2
          where d2.admin_id = a.id
          order by d2.last_seen_at desc, d2.id desc
          limit 1
        ) as latest_app_version
      from public.platform_admin_devices d
      where d.admin_id = a.id
    ) dev on true
    left join lateral (
      select
        x.created_at as latest_backup_at,
        x.last_verified_at,
        case
          when x.verification ? 'restorable'
            then coalesce((x.verification ->> 'restorable')::boolean, false)
          else null
        end as restorable
      from public.tenant_backups x
      where x.admin_id = a.id
      order by x.created_at desc, x.id desc
      limit 1
    ) bk on true
    left join lateral (
      select count(*)::integer as overdue_count
      from public.platform_support_tickets t
      where t.admin_id = a.id
        and t.status not in ('resolved','closed')
        and (
          (t.responded_at is null and t.response_due_at < now())
          or
          (t.resolved_at is null and t.resolution_due_at < now())
        )
    ) sla on true
    where a.role = 'admin'
      and a.is_system_owner = false
  ),
  classified as (
    select *,
      case
        when not account_ready or not subscription_ready then 'blocked'
        when not (
          device_ready
          and backup_fresh
          and backup_verified
          and support_sla_ready
          and app_telemetry_ready
        ) then 'attention'
        else 'ready'
      end as readiness_status
    from readiness
  )
  select
    count(*)::integer,
    count(*) filter (where readiness_status = 'ready')::integer,
    count(*) filter (where readiness_status = 'attention')::integer,
    count(*) filter (where readiness_status = 'blocked')::integer
  into v_total, v_ready, v_attention, v_blocked
  from classified;

  return jsonb_build_object(
    'total_tenants', coalesce(v_total, 0),
    'ready_tenants', coalesce(v_ready, 0),
    'attention_tenants', coalesce(v_attention, 0),
    'blocked_tenants', coalesce(v_blocked, 0),
    'checked_at', now()
  );
end;
$$;

create or replace function public.get_system_owner_readiness_page(
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

  with base as (
    select
      a.id,
      a.created_at,
      coalesce(a.market_name, '') as market_name,
      coalesce(a.name, '') as admin_name,
      coalesce(a.phone, '') as phone,
      a.active,
      a.approved,
      a.subscription_end,
      coalesce(c.lifecycle_status, case when a.active then 'active' else 'suspended' end) as lifecycle_status,
      coalesce(c.feature_plan, 'standard') as feature_plan,
      coalesce(c.support_tier, 'standard') as support_tier,
      coalesce(c.device_policy_mode, 'observe') as device_policy_mode,
      coalesce(bp.expected_interval_hours, 48) as expected_backup_hours,
      coalesce(bp.verification_interval_days, 30) as verification_interval_days,
      coalesce(dev.registered_count, 0) as registered_device_count,
      coalesce(dev.approved_count, 0) as approved_device_count,
      coalesce(dev.pending_count, 0) as pending_device_count,
      dev.latest_device_seen_at,
      coalesce(dev.latest_app_version, '') as latest_app_version,
      bk.latest_backup_at,
      bk.last_verified_at,
      coalesce(bk.restorable, false) as backup_restorable,
      coalesce(sla.overdue_count, 0) as overdue_support_count
    from public.profiles a
    left join public.owner_tenant_controls c on c.admin_id = a.id
    left join public.owner_backup_monitoring_policies bp on bp.admin_id = a.id
    left join lateral (
      select
        count(*)::integer as registered_count,
        count(*) filter (where d.status = 'approved')::integer as approved_count,
        count(*) filter (where d.status = 'pending')::integer as pending_count,
        max(d.last_seen_at) as latest_device_seen_at,
        (
          select d2.app_version
          from public.platform_admin_devices d2
          where d2.admin_id = a.id
          order by d2.last_seen_at desc, d2.id desc
          limit 1
        ) as latest_app_version
      from public.platform_admin_devices d
      where d.admin_id = a.id
    ) dev on true
    left join lateral (
      select
        x.created_at as latest_backup_at,
        x.last_verified_at,
        case
          when x.verification ? 'restorable'
            then coalesce((x.verification ->> 'restorable')::boolean, false)
          else null
        end as restorable
      from public.tenant_backups x
      where x.admin_id = a.id
      order by x.created_at desc, x.id desc
      limit 1
    ) bk on true
    left join lateral (
      select count(*)::integer as overdue_count
      from public.platform_support_tickets t
      where t.admin_id = a.id
        and t.status not in ('resolved','closed')
        and (
          (t.responded_at is null and t.response_due_at < now())
          or
          (t.resolved_at is null and t.resolution_due_at < now())
        )
    ) sla on true
    where a.role = 'admin'
      and a.is_system_owner = false
  ),
  checks as (
    select *,
      (
        active = true
        and approved = true
        and lifecycle_status not in ('suspended','archived')
      ) as account_ready,
      (
        subscription_end is null
        or subscription_end >= now()
      ) as subscription_ready,
      (
        case
          when device_policy_mode = 'approval_required'
            then approved_device_count > 0 and pending_device_count = 0
          else registered_device_count > 0
        end
      ) as device_ready,
      (
        latest_backup_at is not null
        and latest_backup_at >= now()
          - make_interval(hours => expected_backup_hours)
      ) as backup_fresh,
      (
        last_verified_at is not null
        and last_verified_at >= now()
          - make_interval(days => verification_interval_days)
        and backup_restorable = true
      ) as backup_verified,
      overdue_support_count = 0 as support_sla_ready,
      (
        latest_device_seen_at is not null
        and latest_device_seen_at >= now() - interval '30 days'
        and latest_app_version not in ('', 'unknown')
      ) as app_telemetry_ready
    from base
  ),
  classified as (
    select *,
      (
        account_ready::integer
        + subscription_ready::integer
        + device_ready::integer
        + backup_fresh::integer
        + backup_verified::integer
        + support_sla_ready::integer
        + app_telemetry_ready::integer
      ) as readiness_score,
      case
        when not account_ready or not subscription_ready then 'blocked'
        when not (
          device_ready
          and backup_fresh
          and backup_verified
          and support_sla_ready
          and app_telemetry_ready
        ) then 'attention'
        else 'ready'
      end as readiness_status
    from checks
  )
  select coalesce(jsonb_agg(item order by sort_status, sort_score, sort_created desc, sort_id desc), '[]'::jsonb)
    into v_items
  from (
    select
      case readiness_status
        when 'blocked' then 0
        when 'attention' then 1
        else 2
      end as sort_status,
      readiness_score as sort_score,
      created_at as sort_created,
      id as sort_id,
      jsonb_build_object(
        'id', id,
        'market_name', market_name,
        'admin_name', admin_name,
        'phone', phone,
        'lifecycle_status', lifecycle_status,
        'feature_plan', feature_plan,
        'support_tier', support_tier,
        'subscription_end', subscription_end,
        'device_policy_mode', device_policy_mode,
        'registered_device_count', registered_device_count,
        'approved_device_count', approved_device_count,
        'pending_device_count', pending_device_count,
        'latest_device_seen_at', latest_device_seen_at,
        'latest_app_version', latest_app_version,
        'latest_backup_at', latest_backup_at,
        'last_verified_at', last_verified_at,
        'expected_backup_hours', expected_backup_hours,
        'verification_interval_days', verification_interval_days,
        'overdue_support_count', overdue_support_count,
        'account_ready', account_ready,
        'subscription_ready', subscription_ready,
        'device_ready', device_ready,
        'backup_fresh', backup_fresh,
        'backup_verified', backup_verified,
        'support_sla_ready', support_sla_ready,
        'app_telemetry_ready', app_telemetry_ready,
        'readiness_score', readiness_score,
        'readiness_total', 7,
        'readiness_status', readiness_status
      ) as item
    from classified
    order by
      case readiness_status
        when 'blocked' then 0
        when 'attention' then 1
        else 2
      end,
      readiness_score,
      created_at desc,
      id desc
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

revoke all on function public.get_system_owner_readiness_overview()
  from public, anon;
revoke all on function public.get_system_owner_readiness_page(integer, integer)
  from public, anon;

grant execute on function public.get_system_owner_readiness_overview()
  to authenticated;
grant execute on function public.get_system_owner_readiness_page(integer, integer)
  to authenticated;
