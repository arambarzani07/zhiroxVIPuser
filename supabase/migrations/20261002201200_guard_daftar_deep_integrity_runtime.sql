-- Keep all Daftar continuity jobs self-healing, including the deep-integrity job.
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
  select id,source_fingerprint,'current'
  from public.daftar_sync_sources
  where nullif(source_fingerprint,'') is not null
  on conflict(sync_source_id,source_fingerprint)
  do update set alias_kind='current';

  for r in
    select id,trigger_secret_hash,trigger_secret_vault_name
    from public.daftar_sync_sources
    where enabled=true
    order by created_at,id
  loop
    v_secret := null;
    if nullif(r.trigger_secret_vault_name,'') is not null then
      select decrypted_secret into v_secret
      from vault.decrypted_secrets
      where name=r.trigger_secret_vault_name
      limit 1;
    end if;

    if v_secret is null
       or encode(extensions.digest(v_secret,'sha256'),'hex') is distinct from r.trigger_secret_hash then
      v_invalid := v_invalid + 1;
      update public.daftar_sync_sources
      set health_status='degraded',last_status='failed',last_error='trigger_secret_missing_or_invalid',updated_at=now()
      where id=r.id;
    else
      v_valid := v_valid + 1;
      update public.daftar_sync_sources
      set last_error=null,updated_at=now()
      where id=r.id and last_error='trigger_secret_missing_or_invalid';
    end if;
    perform public.qualify_daftar_outage(r.id);
  end loop;

  for j in
    select jobid from cron.job
    where jobname in (
      'daftar-live-sync-account-28','daftar-sync-reconcile-account-28','daily-tenant-backup-account-28',
      'daily-daftar-tenant-backup-all','daftar-sync-guardian-account-28','daftar-outbound-sync-account-28',
      'daftar-sync-dispatch-all','daftar-sync-reconcile-all','daftar-sync-guardian-all'
    )
  loop
    perform cron.unschedule(j.jobid);
    v_removed_legacy := v_removed_legacy + 1;
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

  perform private.recover_daftar_sync_runtime();

  if exists (
    select 1 from public.daftar_sync_sources s
    where s.enabled=true
      and (s.sync_mode='mirror' or (s.sync_mode='zhirox_primary' and s.inbound_sync_enabled=true))
      and (s.last_success_at is null or s.last_success_at < now()-interval '90 seconds')
      and (s.lease_until is null or s.lease_until <= now())
      and (s.next_retry_at is null or s.next_retry_at <= now())
      and (s.circuit_open_until is null or s.circuit_open_until <= now())
  ) then
    perform private.dispatch_daftar_sync_sources();
    v_forced_dispatch := 1;
  end if;

  perform private.guard_backup_runtime();

  return jsonb_build_object(
    'valid_sources',v_valid,
    'invalid_sources',v_invalid,
    'deprecated_jobs_removed',v_removed_legacy,
    'runtime_jobs',6,
    'forced_liveness_dispatch',v_forced_dispatch
  );
end;
$$;

revoke all on function private.guard_daftar_sync_sources() from public, anon, authenticated;