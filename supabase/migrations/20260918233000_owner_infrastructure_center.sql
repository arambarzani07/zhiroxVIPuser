-- Owner Infrastructure Health Center.
-- Aggregate technical metadata only. No tenant/customer identifiers or message content.

create or replace function public.get_system_owner_infrastructure_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_active_jobs integer := 0;
  v_failed_jobs_24h integer := 0;
  v_pending_push_queue integer := 0;
  v_failed_deliveries_24h integer := 0;
  v_active_push_devices integer := 0;
  v_latest_push_success timestamptz;
  v_latest_push_failure timestamptz;
  v_latest_job_run timestamptz;
begin
  v_uid := private.require_system_owner();

  select count(*)::integer
    into v_active_jobs
  from cron.job j
  where j.active = true;

  select count(*)::integer,
         max(r.start_time)
    into v_failed_jobs_24h, v_latest_job_run
  from cron.job_run_details r
  where r.start_time >= now() - interval '24 hours'
    and lower(coalesce(r.status, '')) not in ('succeeded', 'running');

  if v_latest_job_run is null then
    select max(r.start_time)
      into v_latest_job_run
    from cron.job_run_details r;
  end if;

  select count(*)::integer
    into v_pending_push_queue
  from public.notification_outbox o
  where lower(coalesce(o.status, '')) in ('pending', 'retrying', 'queued');

  select count(*)::integer
    into v_failed_deliveries_24h
  from public.notification_deliveries d
  where d.created_at >= now() - interval '24 hours'
    and lower(coalesce(d.status, '')) in ('failed', 'retrying');

  select count(*)::integer,
         max(s.last_success_at),
         max(s.last_failure_at)
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
  v_uid uuid;
  v_page integer := greatest(coalesce(p_page, 1), 1);
  v_per_page integer := least(greatest(coalesce(p_per_page, 50), 1), 100);
  v_total integer := 0;
  v_items jsonb := '[]'::jsonb;
begin
  v_uid := private.require_system_owner();

  select count(*)::integer
    into v_total
  from cron.job;

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
        'latest_duration_ms',
          case
            when last_run.start_time is null or last_run.end_time is null then null
            else greatest(
              0,
              floor(extract(epoch from (last_run.end_time - last_run.start_time)) * 1000)
            )::bigint
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
      select
        count(*)::integer as run_count_24h,
        count(*) filter (
          where lower(coalesce(r.status, '')) not in ('succeeded', 'running')
        )::integer as failed_count_24h
      from cron.job_run_details r
      where r.jobid = j.jobid
        and r.start_time >= now() - interval '24 hours'
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

revoke all on function public.get_system_owner_infrastructure_overview()
  from public, anon;
revoke all on function public.get_system_owner_infrastructure_jobs_page(integer, integer)
  from public, anon;

grant execute on function public.get_system_owner_infrastructure_overview()
  to authenticated;
grant execute on function public.get_system_owner_infrastructure_jobs_page(integer, integer)
  to authenticated;
