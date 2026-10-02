-- Monitor logical sync snapshots and keep all seven Daftar continuity jobs self-healing.

alter table private.daftar_sync_health_samples
  add column if not exists snapshot_age_seconds integer,
  add column if not exists snapshot_valid boolean;

create or replace function private.check_daftar_sync_integrity(p_source_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.daftar_sync_sources%rowtype;
  v_heartbeat_age integer;
  v_success_age integer;
  v_queue integer := 0;
  v_stale integer := 0;
  v_blocked integer := 0;
  v_failed integer := 0;
  v_dead integer := 0;
  v_cursor integer := 0;
  v_oldest_wait integer := 0;
  v_deep_status text;
  v_deep_checked timestamptz;
  v_snapshot_id uuid;
  v_snapshot_at timestamptz;
  v_snapshot_age integer;
  v_snapshot_valid boolean := false;
  v_status text := 'healthy';
  v_result jsonb;
begin
  select * into s from public.daftar_sync_sources where id=p_source_id;
  if s.id is null then raise exception 'sync_source_not_found'; end if;

  v_heartbeat_age := case when s.last_heartbeat_at is null then null else greatest(0,extract(epoch from (now()-s.last_heartbeat_at))::int) end;
  v_success_age := case when s.last_success_at is null then null else greatest(0,extract(epoch from (now()-s.last_success_at))::int) end;

  select
    count(*) filter (where status in ('pending','failed') and next_attempt_at <= now()),
    count(*) filter (where status='processing' and updated_at < now()-interval '2 minutes'),
    count(*) filter (where status='blocked'),
    count(*) filter (where status='failed'),
    coalesce(extract(epoch from (now()-min(created_at) filter (where status in ('pending','processing','failed','blocked'))))::int,0)
  into v_queue,v_stale,v_blocked,v_failed,v_oldest_wait
  from public.daftar_outbound_events where sync_source_id=s.id;

  select count(*) into v_dead from public.daftar_sync_dead_letters where sync_source_id=s.id and resolved_at is null;
  select count(*) into v_cursor from private.daftar_cursor_anomalies where sync_source_id=s.id and resolved_at is null;
  select status,checked_at into v_deep_status,v_deep_checked from private.daftar_deep_integrity_state where sync_source_id=s.id;

  select ss.id,ss.captured_at into v_snapshot_id,v_snapshot_at
  from private.daftar_sync_state_snapshots ss
  where ss.sync_source_id=s.id
  order by ss.captured_at desc
  limit 1;

  if v_snapshot_at is not null then
    v_snapshot_age := greatest(0,extract(epoch from (now()-v_snapshot_at))::int);
    v_snapshot_valid := private.verify_daftar_sync_state_snapshot(v_snapshot_id);
  end if;

  if s.last_status='failed'
     or s.health_status in ('circuit_open','disabled')
     or s.outage_status='confirmed'
     or coalesce(v_success_age,2147483647) > 300
     or coalesce(s.reconciliation_missing_contacts,0) > 0
     or coalesce(s.reconciliation_missing_transactions,0) > 0
     or v_stale > 0 or v_blocked > 0 or v_dead > 0 or v_cursor > 0
     or v_oldest_wait > 300
     or v_deep_status='critical'
     or v_deep_checked is null or v_deep_checked < now()-interval '10 minutes'
     or v_snapshot_at is null or v_snapshot_age > 2700 or not v_snapshot_valid then
    v_status := 'critical';
  elsif s.health_status='degraded'
     or s.outage_status='suspected'
     or coalesce(v_success_age,2147483647) > 90
     or v_failed > 0 or v_queue > 25 or v_oldest_wait > 60
     or v_snapshot_age > 1500 then
    v_status := 'degraded';
  end if;

  v_result := jsonb_build_object(
    'status',v_status,
    'heartbeat_age_seconds',v_heartbeat_age,
    'success_age_seconds',v_success_age,
    'queue_waiting',v_queue,
    'oldest_waiting_age_seconds',v_oldest_wait,
    'stale_processing',v_stale,
    'blocked_events',v_blocked,
    'failed_events',v_failed,
    'open_dead_letters',v_dead,
    'cursor_anomalies',v_cursor,
    'deep_integrity_status',coalesce(v_deep_status,'missing'),
    'deep_integrity_checked_at',v_deep_checked,
    'snapshot_age_seconds',v_snapshot_age,
    'snapshot_valid',v_snapshot_valid,
    'missing_contacts',coalesce(s.reconciliation_missing_contacts,0),
    'missing_transactions',coalesce(s.reconciliation_missing_transactions,0),
    'source_health',s.health_status,
    'outage_status',s.outage_status,
    'last_status',s.last_status
  );

  insert into private.daftar_sync_health_samples(
    sync_source_id,status,heartbeat_age_seconds,success_age_seconds,
    queue_waiting,oldest_waiting_age_seconds,stale_processing,blocked_events,failed_events,open_dead_letters,
    cursor_anomalies,deep_integrity_status,snapshot_age_seconds,snapshot_valid,
    missing_contacts,missing_transactions,details
  ) values (
    s.id,v_status,v_heartbeat_age,v_success_age,v_queue,v_oldest_wait,v_stale,v_blocked,v_failed,v_dead,
    v_cursor,coalesce(v_deep_status,'missing'),v_snapshot_age,v_snapshot_valid,
    coalesce(s.reconciliation_missing_contacts,0),coalesce(s.reconciliation_missing_transactions,0),v_result
  );

  delete from private.daftar_sync_health_samples where observed_at < now()-interval '30 days';
  return v_result;
end;
$$;
revoke all on function private.check_daftar_sync_integrity(uuid) from public, anon, authenticated;

create or replace function private.guard_daftar_sync_sources()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  j record;
  v_secret text;
  v_valid integer := 0;
  v_invalid integer := 0;
  v_job_id bigint;
  v_removed_legacy integer := 0;
  v_forced_dispatch integer := 0;
begin
  perform set_config('zhirox.daftar_sync_guardian','on',true);

  insert into private.daftar_source_fingerprint_aliases(sync_source_id,source_fingerprint,alias_kind)
  select id,source_fingerprint,'current' from public.daftar_sync_sources
  where nullif(source_fingerprint,'') is not null
  on conflict(sync_source_id,source_fingerprint) do update set alias_kind='current';

  for r in select id,trigger_secret_hash,trigger_secret_vault_name from public.daftar_sync_sources where enabled=true order by created_at,id
  loop
    v_secret := null;
    if nullif(r.trigger_secret_vault_name,'') is not null then
      select decrypted_secret into v_secret from vault.decrypted_secrets where name=r.trigger_secret_vault_name limit 1;
    end if;
    if v_secret is null or encode(extensions.digest(v_secret,'sha256'),'hex') is distinct from r.trigger_secret_hash then
      v_invalid := v_invalid + 1;
      update public.daftar_sync_sources set health_status='degraded',last_status='failed',last_error='trigger_secret_missing_or_invalid',updated_at=now() where id=r.id;
    else
      v_valid := v_valid + 1;
      update public.daftar_sync_sources set last_error=null,updated_at=now() where id=r.id and last_error='trigger_secret_missing_or_invalid';
    end if;
    perform public.qualify_daftar_outage(r.id);
  end loop;

  for j in select jobid from cron.job where jobname in (
    'daftar-live-sync-account-28','daftar-sync-reconcile-account-28','daily-tenant-backup-account-28',
    'daily-daftar-tenant-backup-all','daftar-sync-guardian-account-28','daftar-outbound-sync-account-28',
    'daftar-sync-dispatch-all','daftar-sync-reconcile-all','daftar-sync-guardian-all')
  loop
    perform cron.unschedule(j.jobid); v_removed_legacy := v_removed_legacy + 1;
  end loop;

  select jobid into v_job_id from cron.job where jobname='daftar-sync-multitenant-dispatch' limit 1;
  if v_job_id is null then perform cron.schedule('daftar-sync-multitenant-dispatch','30 seconds','select private.dispatch_daftar_sync_sources();');
  else perform cron.alter_job(job_id=>v_job_id,schedule=>'30 seconds',command=>'select private.dispatch_daftar_sync_sources();',active=>true); end if;

  select jobid into v_job_id from cron.job where jobname='daftar-sync-multitenant-reconcile' limit 1;
  if v_job_id is null then perform cron.schedule('daftar-sync-multitenant-reconcile','17 * * * *','select private.reconcile_daftar_sync_sources();');
  else perform cron.alter_job(job_id=>v_job_id,schedule=>'17 * * * *',command=>'select private.reconcile_daftar_sync_sources();',active=>true); end if;

  select jobid into v_job_id from cron.job where jobname='daftar-sync-multitenant-guardian' limit 1;
  if v_job_id is null then perform cron.schedule('daftar-sync-multitenant-guardian','* * * * *','select private.guard_daftar_sync_sources();');
  else perform cron.alter_job(job_id=>v_job_id,schedule=>'* * * * *',command=>'select private.guard_daftar_sync_sources();',active=>true); end if;

  select jobid into v_job_id from cron.job where jobname='daftar-sync-runtime-recovery' limit 1;
  if v_job_id is null then perform cron.schedule('daftar-sync-runtime-recovery','* * * * *','select private.recover_daftar_sync_runtime();');
  else perform cron.alter_job(job_id=>v_job_id,schedule=>'* * * * *',command=>'select private.recover_daftar_sync_runtime();',active=>true); end if;

  select jobid into v_job_id from cron.job where jobname='daftar-sync-integrity-sentinel' limit 1;
  if v_job_id is null then perform cron.schedule('daftar-sync-integrity-sentinel','* * * * *','select private.run_daftar_integrity_sentinel();');
  else perform cron.alter_job(job_id=>v_job_id,schedule=>'* * * * *',command=>'select private.run_daftar_integrity_sentinel();',active=>true); end if;

  select jobid into v_job_id from cron.job where jobname='daftar-sync-deep-integrity' limit 1;
  if v_job_id is null then perform cron.schedule('daftar-sync-deep-integrity','*/5 * * * *','select private.run_daftar_deep_integrity_check();');
  else perform cron.alter_job(job_id=>v_job_id,schedule=>'*/5 * * * *',command=>'select private.run_daftar_deep_integrity_check();',active=>true); end if;

  select jobid into v_job_id from cron.job where jobname='daftar-sync-state-snapshot' limit 1;
  if v_job_id is null then perform cron.schedule('daftar-sync-state-snapshot','*/15 * * * *','select private.capture_daftar_sync_state_snapshots();');
  else perform cron.alter_job(job_id=>v_job_id,schedule=>'*/15 * * * *',command=>'select private.capture_daftar_sync_state_snapshots();',active=>true); end if;

  perform private.recover_daftar_sync_runtime();

  if exists (
    select 1 from public.daftar_sync_sources s where s.enabled=true
      and (s.sync_mode='mirror' or (s.sync_mode='zhirox_primary' and s.inbound_sync_enabled=true))
      and (s.last_success_at is null or s.last_success_at < now()-interval '90 seconds')
      and (s.lease_until is null or s.lease_until <= now())
      and (s.next_retry_at is null or s.next_retry_at <= now())
      and (s.circuit_open_until is null or s.circuit_open_until <= now())
  ) then
    perform private.dispatch_daftar_sync_sources(); v_forced_dispatch := 1;
  end if;

  perform private.guard_backup_runtime();

  return jsonb_build_object('valid_sources',v_valid,'invalid_sources',v_invalid,
    'deprecated_jobs_removed',v_removed_legacy,'runtime_jobs',7,'forced_liveness_dispatch',v_forced_dispatch);
end;
$$;
revoke all on function private.guard_daftar_sync_sources() from public, anon, authenticated;