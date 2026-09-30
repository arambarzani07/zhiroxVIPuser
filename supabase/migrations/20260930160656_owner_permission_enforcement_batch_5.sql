-- Owner permission enforcement batch 5: Health, Infrastructure, Incidents.
-- Platform/account metadata only; no tenant business content is exposed.

create or replace function public.get_system_owner_health_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_active_tenants integer := 0;
  v_backup_fresh integer := 0;
  v_backup_stale integer := 0;
  v_billing_pending integer := 0;
  v_billing_failed integer := 0;
  v_revenue_30d numeric := 0;
  v_latest_backup timestamptz;
  v_latest_update timestamptz;
  v_latest_owner_action timestamptz;
begin
  perform private.assert_system_owner_permission('owner_view_platform_metrics', 'platform', null);
  perform private.assert_system_owner_permission('owner_view_database_health', 'platform', null);
  perform private.assert_system_owner_permission('owner_view_backup_health', 'platform', null);
  perform private.assert_system_owner_permission('owner_view_billing_history', 'market', null);
  perform private.assert_system_owner_permission('owner_view_owner_audit', 'platform', null);

  select count(*)::integer
    into v_active_tenants
  from public.profiles a
  left join public.owner_tenant_controls c on c.admin_id = a.id
  where a.role = 'admin'
    and a.is_system_owner = false
    and a.active = true
    and coalesce(c.lifecycle_status, 'active') not in ('suspended', 'archived');

  select count(distinct b.admin_id)::integer, max(b.created_at)
    into v_backup_fresh, v_latest_backup
  from public.tenant_backups b
  join public.profiles a
    on a.id = b.admin_id
   and a.role = 'admin'
   and a.is_system_owner = false
   and a.active = true
  where b.created_at >= now() - interval '48 hours';

  v_backup_stale := greatest(v_active_tenants - coalesce(v_backup_fresh, 0), 0);

  select
    count(*) filter (
      where lower(coalesce(s.status, '')) in ('pending', 'created', 'unpaid')
    )::integer,
    count(*) filter (
      where lower(coalesce(s.status, '')) in ('failed', 'declined', 'cancelled', 'canceled')
    )::integer,
    coalesce(sum(s.amount_iqd) filter (
      where lower(coalesce(s.status, '')) in ('paid', 'completed', 'success')
    ), 0)::numeric
  into v_billing_pending, v_billing_failed, v_revenue_30d
  from public.subscription_payments s
  where s.created_at >= now() - interval '30 days';

  select max(u.updated_at)
    into v_latest_update
  from public.app_update_settings u;

  select max(a.created_at)
    into v_latest_owner_action
  from public.owner_platform_audit a;

  return jsonb_build_object(
    'database_ok', true,
    'checked_at', now(),
    'active_tenants', v_active_tenants,
    'backup_fresh_tenants', coalesce(v_backup_fresh, 0),
    'backup_stale_tenants', v_backup_stale,
    'latest_backup_at', v_latest_backup,
    'billing_pending_30d', coalesce(v_billing_pending, 0),
    'billing_failed_30d', coalesce(v_billing_failed, 0),
    'platform_revenue_30d_iqd', coalesce(v_revenue_30d, 0),
    'latest_update_config_at', v_latest_update,
    'latest_owner_action_at', v_latest_owner_action
  );
end;
$$;

create or replace function public.get_system_owner_platform_audit_page(
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
  perform private.assert_system_owner_permission('owner_view_owner_audit', 'platform', null);

  select count(*)::integer
    into v_total
  from public.owner_platform_audit;

  select coalesce(jsonb_agg(row_item order by created_at desc, id desc), '[]'::jsonb)
    into v_items
  from (
    select
      a.id,
      a.created_at,
      jsonb_build_object(
        'id', a.id,
        'action', a.action,
        'market_name', coalesce(p.market_name, ''),
        'created_at', a.created_at,
        'metadata',
          case a.action
            when 'tenant_lifecycle_changed' then jsonb_build_object(
              'status', coalesce(a.metadata ->> 'status', ''),
              'reason', left(coalesce(a.metadata ->> 'reason', ''), 500)
            )
            when 'tenant_limits_changed' then jsonb_build_object(
              'device_limit', coalesce(a.metadata ->> 'device_limit', ''),
              'staff_limit', coalesce(a.metadata ->> 'staff_limit', ''),
              'support_tier', coalesce(a.metadata ->> 'support_tier', '')
            )
            else '{}'::jsonb
          end
      ) as row_item
    from public.owner_platform_audit a
    left join public.profiles p on p.id = a.target_admin_id
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

create or replace function public.get_system_owner_infrastructure_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_active_jobs integer := 0;
  v_failed_jobs_24h integer := 0;
  v_pending_push_queue integer := 0;
  v_failed_deliveries_24h integer := 0;
  v_active_push_devices integer := 0;
  v_latest_push_success timestamptz;
  v_latest_push_failure timestamptz;
  v_latest_job_run timestamptz;
begin
  perform private.assert_system_owner_permission('owner_view_backend_health', 'platform', null);
  perform private.assert_system_owner_permission('owner_view_queue_health', 'platform', null);

  select count(*)::integer into v_active_jobs from cron.job j where j.active = true;

  select count(*)::integer, max(r.start_time)
    into v_failed_jobs_24h, v_latest_job_run
  from cron.job_run_details r
  where r.start_time >= now() - interval '24 hours'
    and lower(coalesce(r.status, '')) not in ('succeeded', 'running');

  if v_latest_job_run is null then
    select max(r.start_time) into v_latest_job_run from cron.job_run_details r;
  end if;

  select count(*)::integer into v_pending_push_queue
  from public.notification_outbox o
  where lower(coalesce(o.status, '')) in ('pending', 'retrying', 'queued');

  select count(*)::integer into v_failed_deliveries_24h
  from public.notification_deliveries d
  where d.created_at >= now() - interval '24 hours'
    and lower(coalesce(d.status, '')) in ('failed', 'retrying');

  select count(*)::integer, max(s.last_success_at), max(s.last_failure_at)
    into v_active_push_devices, v_latest_push_success, v_latest_push_failure
  from public.customer_push_subscriptions s
  where s.active = true;

  return jsonb_build_object(
    'active_jobs', coalesce(v_active_jobs, 0),
    'failed_jobs_24h', coalesce(v_failed_jobs_24h, 0),
    'pending_push_queue', coalesce(v_pending_push_queue, 0),
    'failed_deliveries_24h', coalesce(v_failed_deliveries_24h, 0),
    'active_push_devices', coalesce(v_active_push_devices, 0),
    'latest_push_success_at', v_latest_push_success,
    'latest_push_failure_at', v_latest_push_failure,
    'latest_job_run_at', v_latest_job_run,
    'checked_at', now()
  );
end;
$$;

create or replace function public.get_system_owner_infrastructure_jobs_page(
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
  perform private.assert_system_owner_permission('owner_view_backend_health', 'platform', null);
  perform private.assert_system_owner_permission('owner_view_queue_health', 'platform', null);

  select count(*)::integer into v_total from cron.job;

  select coalesce(jsonb_agg(item order by sort_active desc, sort_name), '[]'::jsonb)
    into v_items
  from (
    select
      j.active as sort_active,
      coalesce(j.jobname, 'job-' || j.jobid::text) as sort_name,
      jsonb_build_object(
        'job_id', j.jobid,
        'job_name', coalesce(j.jobname, 'job-' || j.jobid::text),
        'schedule', j.schedule,
        'active', j.active,
        'latest_status', coalesce(last_run.status, 'never'),
        'latest_started_at', last_run.start_time,
        'latest_finished_at', last_run.end_time,
        'latest_duration_ms', case
          when last_run.start_time is null or last_run.end_time is null then null
          else greatest(0, floor(extract(epoch from (last_run.end_time - last_run.start_time)) * 1000))::bigint
        end,
        'run_count_24h', coalesce(stats.run_count_24h, 0),
        'failed_count_24h', coalesce(stats.failed_count_24h, 0)
      ) as item
    from cron.job j
    left join lateral (
      select r.status, r.start_time, r.end_time
      from cron.job_run_details r
      where r.jobid = j.jobid
      order by r.start_time desc nulls last, r.runid desc
      limit 1
    ) last_run on true
    left join lateral (
      select count(*)::integer as run_count_24h,
             count(*) filter (where lower(coalesce(r.status, '')) not in ('succeeded', 'running'))::integer as failed_count_24h
      from cron.job_run_details r
      where r.jobid = j.jobid and r.start_time >= now() - interval '24 hours'
    ) stats on true
    order by j.active desc, coalesce(j.jobname, 'job-' || j.jobid::text)
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

create or replace function public.get_system_owner_incident_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_active integer := 0;
  v_critical integer := 0;
  v_scheduled integer := 0;
  v_resolved_30d integer := 0;
  v_latest timestamptz;
begin
  perform private.assert_system_owner_permission('owner_view_platform_activity', 'platform', null);

  select
    count(*) filter (where status <> 'resolved')::integer,
    count(*) filter (where status <> 'resolved' and severity = 'critical')::integer,
    count(*) filter (where status = 'scheduled' and starts_at >= now())::integer,
    count(*) filter (where status = 'resolved' and resolved_at >= now() - interval '30 days')::integer,
    max(updated_at)
  into v_active, v_critical, v_scheduled, v_resolved_30d, v_latest
  from public.platform_incidents;

  return jsonb_build_object(
    'active_incidents', coalesce(v_active, 0),
    'critical_incidents', coalesce(v_critical, 0),
    'scheduled_incidents', coalesce(v_scheduled, 0),
    'resolved_30d', coalesce(v_resolved_30d, 0),
    'last_incident_update_at', v_latest,
    'checked_at', now()
  );
end;
$$;

create or replace function public.get_system_owner_incidents_page(
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
  perform private.assert_system_owner_permission('owner_view_platform_activity', 'platform', null);

  select count(*)::integer into v_total from public.platform_incidents;

  select coalesce(jsonb_agg(item order by sort_rank, sort_time desc, sort_id desc), '[]'::jsonb)
    into v_items
  from (
    select
      case i.status when 'investigating' then 1 when 'identified' then 2 when 'monitoring' then 3 when 'scheduled' then 4 else 5 end as sort_rank,
      i.updated_at as sort_time,
      i.id as sort_id,
      jsonb_build_object(
        'id', i.id,
        'title', i.title,
        'summary', i.summary,
        'severity', i.severity,
        'status', i.status,
        'affected_component', i.affected_component,
        'public_visible', i.public_visible,
        'starts_at', i.starts_at,
        'resolved_at', i.resolved_at,
        'created_at', i.created_at,
        'updated_at', i.updated_at
      ) as item
    from public.platform_incidents i
    order by case i.status when 'investigating' then 1 when 'identified' then 2 when 'monitoring' then 3 when 'scheduled' then 4 else 5 end,
             i.updated_at desc, i.id desc
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

create or replace function public.create_system_owner_incident(
  p_title text,
  p_summary text,
  p_severity text,
  p_status text,
  p_affected_component text,
  p_public_visible boolean,
  p_starts_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_title text := trim(coalesce(p_title, ''));
  v_summary text := trim(coalesce(p_summary, ''));
  v_severity text := lower(trim(coalesce(p_severity, 'minor')));
  v_status text := lower(trim(coalesce(p_status, 'investigating')));
  v_component text := trim(coalesce(p_affected_component, 'platform'));
  v_row public.platform_incidents%rowtype;
  v_permission_keys jsonb := jsonb_build_array('owner_refresh_platform_config');
begin
  v_uid := private.require_system_owner();
  perform private.assert_system_owner_permission('owner_refresh_platform_config', 'platform', null);

  if coalesce(p_public_visible, true) then
    perform private.assert_system_owner_permission('owner_publish_update_message', 'platform', null);
    v_permission_keys := v_permission_keys || jsonb_build_array('owner_publish_update_message');
  end if;

  if char_length(v_title) < 1 or char_length(v_title) > 180 then raise exception 'invalid_incident_title' using errcode = '22023'; end if;
  if char_length(v_summary) > 4000 then raise exception 'incident_summary_too_long' using errcode = '22023'; end if;
  if v_severity not in ('info','minor','major','critical') then raise exception 'invalid_incident_severity' using errcode = '22023'; end if;
  if v_status not in ('scheduled','investigating','identified','monitoring','resolved') then raise exception 'invalid_incident_status' using errcode = '22023'; end if;
  if char_length(v_component) < 1 or char_length(v_component) > 120 then raise exception 'invalid_incident_component' using errcode = '22023'; end if;

  insert into public.platform_incidents (
    title, summary, severity, status, affected_component, public_visible,
    starts_at, resolved_at, created_by, updated_by
  ) values (
    v_title, v_summary, v_severity, v_status, v_component,
    coalesce(p_public_visible, true), coalesce(p_starts_at, now()),
    case when v_status = 'resolved' then now() else null end, v_uid, v_uid
  ) returning * into v_row;

  insert into public.owner_platform_audit (actor_id, target_admin_id, action, metadata)
  values (v_uid, null, 'platform_incident_created', jsonb_build_object(
    'permission_keys', v_permission_keys,
    'incident_id', v_row.id,
    'severity', v_row.severity,
    'status', v_row.status,
    'affected_component', v_row.affected_component,
    'public_visible', v_row.public_visible
  ));

  return jsonb_build_object(
    'id', v_row.id,
    'status', v_row.status,
    'severity', v_row.severity,
    'permission_keys', v_permission_keys
  );
end;
$$;

create or replace function public.update_system_owner_incident(
  p_incident_id uuid,
  p_title text,
  p_summary text,
  p_severity text,
  p_status text,
  p_affected_component text,
  p_public_visible boolean,
  p_starts_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_title text := trim(coalesce(p_title, ''));
  v_summary text := trim(coalesce(p_summary, ''));
  v_severity text := lower(trim(coalesce(p_severity, 'minor')));
  v_status text := lower(trim(coalesce(p_status, 'investigating')));
  v_component text := trim(coalesce(p_affected_component, 'platform'));
  v_old public.platform_incidents%rowtype;
  v_row public.platform_incidents%rowtype;
  v_permission_keys jsonb := jsonb_build_array('owner_refresh_platform_config');
begin
  v_uid := private.require_system_owner();

  if p_incident_id is null then raise exception 'incident_id_required' using errcode = '22023'; end if;
  if char_length(v_title) < 1 or char_length(v_title) > 180 then raise exception 'invalid_incident_title' using errcode = '22023'; end if;
  if char_length(v_summary) > 4000 then raise exception 'incident_summary_too_long' using errcode = '22023'; end if;
  if v_severity not in ('info','minor','major','critical') then raise exception 'invalid_incident_severity' using errcode = '22023'; end if;
  if v_status not in ('scheduled','investigating','identified','monitoring','resolved') then raise exception 'invalid_incident_status' using errcode = '22023'; end if;
  if char_length(v_component) < 1 or char_length(v_component) > 120 then raise exception 'invalid_incident_component' using errcode = '22023'; end if;

  select * into v_old from public.platform_incidents where id = p_incident_id for update;
  if not found then raise exception 'incident_not_found' using errcode = 'P0002'; end if;

  perform private.assert_system_owner_permission('owner_refresh_platform_config', 'platform', null);
  if v_old.public_visible or coalesce(p_public_visible, true) then
    perform private.assert_system_owner_permission('owner_publish_update_message', 'platform', null);
    v_permission_keys := v_permission_keys || jsonb_build_array('owner_publish_update_message');
  end if;

  update public.platform_incidents
     set title = v_title,
         summary = v_summary,
         severity = v_severity,
         status = v_status,
         affected_component = v_component,
         public_visible = coalesce(p_public_visible, true),
         starts_at = coalesce(p_starts_at, starts_at),
         resolved_at = case when v_status = 'resolved' then coalesce(resolved_at, now()) else null end,
         updated_by = v_uid,
         updated_at = now()
   where id = p_incident_id
   returning * into v_row;

  insert into public.owner_platform_audit (actor_id, target_admin_id, action, metadata)
  values (v_uid, null, 'platform_incident_updated', jsonb_build_object(
    'permission_keys', v_permission_keys,
    'incident_id', v_row.id,
    'severity', v_row.severity,
    'status', v_row.status,
    'affected_component', v_row.affected_component,
    'public_visible', v_row.public_visible,
    'previous_status', v_old.status,
    'previous_severity', v_old.severity,
    'previous_public_visible', v_old.public_visible
  ));

  return jsonb_build_object(
    'id', v_row.id,
    'status', v_row.status,
    'severity', v_row.severity,
    'resolved_at', v_row.resolved_at,
    'permission_keys', v_permission_keys
  );
end;
$$;

revoke all on function public.get_system_owner_health_overview() from public, anon;
revoke all on function public.get_system_owner_platform_audit_page(integer, integer) from public, anon;
revoke all on function public.get_system_owner_infrastructure_overview() from public, anon;
revoke all on function public.get_system_owner_infrastructure_jobs_page(integer, integer) from public, anon;
revoke all on function public.get_system_owner_incident_overview() from public, anon;
revoke all on function public.get_system_owner_incidents_page(integer, integer) from public, anon;
revoke all on function public.create_system_owner_incident(text, text, text, text, text, boolean, timestamptz) from public, anon;
revoke all on function public.update_system_owner_incident(uuid, text, text, text, text, text, boolean, timestamptz) from public, anon;

grant execute on function public.get_system_owner_health_overview() to authenticated;
grant execute on function public.get_system_owner_platform_audit_page(integer, integer) to authenticated;
grant execute on function public.get_system_owner_infrastructure_overview() to authenticated;
grant execute on function public.get_system_owner_infrastructure_jobs_page(integer, integer) to authenticated;
grant execute on function public.get_system_owner_incident_overview() to authenticated;
grant execute on function public.get_system_owner_incidents_page(integer, integer) to authenticated;
grant execute on function public.create_system_owner_incident(text, text, text, text, text, boolean, timestamptz) to authenticated;
grant execute on function public.update_system_owner_incident(uuid, text, text, text, text, text, boolean, timestamptz) to authenticated;
