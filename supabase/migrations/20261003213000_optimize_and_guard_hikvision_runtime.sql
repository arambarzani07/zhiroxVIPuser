-- Optimize Hikvision RLS execution and add an independent stale-job guardian.

create index if not exists hikvision_video_jobs_gateway_idx
  on private.hikvision_video_jobs(gateway_id);

-- Avoid per-row auth.uid() re-evaluation while preserving existing access rules.
drop policy if exists hikvision_market_config_admin_read on public.hikvision_market_config;
create policy hikvision_market_config_admin_read
on public.hikvision_market_config for select
to authenticated
using (
  market_id = (select auth.uid())
  or exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.active = true
      and p.approved = true
      and p.admin_id = hikvision_market_config.market_id
      and p.role = 'employee'
      and (p.can_view_transactions = true or p.can_manage_settings = true)
  )
);

-- Split the old FOR ALL policy so SELECT does not evaluate two permissive policies.
drop policy if exists hikvision_market_config_admin_write on public.hikvision_market_config;
drop policy if exists hikvision_market_config_admin_insert on public.hikvision_market_config;
drop policy if exists hikvision_market_config_admin_update on public.hikvision_market_config;
drop policy if exists hikvision_market_config_admin_delete on public.hikvision_market_config;

create policy hikvision_market_config_admin_insert
on public.hikvision_market_config for insert
to authenticated
with check (
  market_id = (select auth.uid())
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
      and p.active = true
      and p.approved = true
  )
);

create policy hikvision_market_config_admin_update
on public.hikvision_market_config for update
to authenticated
using (
  market_id = (select auth.uid())
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
      and p.active = true
      and p.approved = true
  )
)
with check (
  market_id = (select auth.uid())
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
      and p.active = true
      and p.approved = true
  )
);

create policy hikvision_market_config_admin_delete
on public.hikvision_market_config for delete
to authenticated
using (
  market_id = (select auth.uid())
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
      and p.active = true
      and p.approved = true
  )
);

drop policy if exists transaction_video_evidence_read on public.transaction_video_evidence;
create policy transaction_video_evidence_read
on public.transaction_video_evidence for select
to authenticated
using (
  market_id = (select auth.uid())
  or exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.active = true
      and p.approved = true
      and p.admin_id = transaction_video_evidence.market_id
      and p.role = 'employee'
      and (p.can_view_transactions = true or p.can_view_audit_log = true)
  )
);

create or replace function private.guard_hikvision_video_jobs()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_recovered integer := 0;
  v_sources integer := 0;
begin
  for r in
    select distinct g.market_id
    from private.hikvision_gateways g
    where g.active = true
  loop
    v_sources := v_sources + 1;
    v_recovered := v_recovered + private.recover_stale_hikvision_video_jobs(r.market_id);
  end loop;

  return jsonb_build_object(
    'markets_checked', v_sources,
    'stale_jobs_recovered', v_recovered,
    'checked_at', now()
  );
end;
$$;

revoke all on function private.guard_hikvision_video_jobs() from public, anon, authenticated;
grant execute on function private.guard_hikvision_video_jobs() to service_role;

-- Keep exactly one guardian schedule.
do $$
declare
  v_jobid bigint;
begin
  for v_jobid in
    select j.jobid from cron.job j where j.jobname = 'hikvision-video-job-guardian'
  loop
    perform cron.unschedule(v_jobid);
  end loop;

  perform cron.schedule(
    'hikvision-video-job-guardian',
    '* * * * *',
    'select private.guard_hikvision_video_jobs();'
  );
end;
$$;
