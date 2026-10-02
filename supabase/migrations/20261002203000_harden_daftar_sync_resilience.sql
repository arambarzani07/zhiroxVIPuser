-- Harden Daftar <-> ZHIROX sync against worker interruption, stale leases,
-- and recoverable outbound ambiguity without exposing private runtime state.

create index if not exists daftar_outbound_events_processing_stale_idx
  on public.daftar_outbound_events (updated_at, sync_source_id, operation)
  where status = 'processing';

create index if not exists daftar_sync_sources_running_lease_idx
  on public.daftar_sync_sources (lease_until, last_heartbeat_at)
  where enabled = true and last_status = 'running';

create or replace function private.recover_daftar_sync_runtime()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source_leases integer := 0;
  v_safe_processing integer := 0;
  v_safe_blocked integer := 0;
  v_customer_creates integer := 0;
begin
  perform set_config('zhirox.daftar_sync_guardian', 'on', true);

  -- Release an expired inbound lease after a crashed/interrupted worker and
  -- immediately hand it back to the existing retry/circuit-breaker path.
  update public.daftar_sync_sources
  set lease_until = null,
      last_status = 'failed',
      last_error = 'stale_sync_lease_recovered',
      next_retry_at = now(),
      circuit_open_until = null,
      health_status = 'degraded',
      updated_at = now()
  where enabled = true
    and last_status = 'running'
    and lease_until is not null
    and lease_until < now()
    and coalesce(last_heartbeat_at, last_started_at, updated_at)
        < now() - interval '2 minutes';
  get diagnostics v_source_leases = row_count;

  -- PUT/DELETE operations are idempotent in the Daftar adapter. A stale claim
  -- can therefore return to the durable retry queue without risking duplicates.
  update public.daftar_outbound_events
  set status = 'failed',
      next_attempt_at = now(),
      last_error = 'worker_interruption_safe_retry',
      updated_at = now()
  where status = 'processing'
    and operation in ('update', 'delete')
    and updated_at < now() - interval '2 minutes';
  get diagnostics v_safe_processing = row_count;

  -- Recover safe writes that older workers stranded as blocked. Real remote 4xx
  -- rejections intentionally remain blocked for investigation.
  update public.daftar_outbound_events
  set status = 'failed',
      next_attempt_at = now(),
      last_error = 'ambiguous_write_safe_retry',
      updated_at = now()
  where status = 'blocked'
    and operation in ('update', 'delete')
    and (
      last_error = 'ambiguous_worker_interruption'
      or last_error like 'ambiguous_remote_%'
      or last_error like 'ambiguous_mapping_failed:%'
    );
  get diagnostics v_safe_blocked = row_count;

  -- CREATE is deliberately not blindly retried. A customer POST may have
  -- committed remotely even if the response was lost. Feed stale customer
  -- creates into the existing live/mirror reconciliation path instead.
  update public.daftar_outbound_events
  set status = 'blocked',
      next_attempt_at = least(next_attempt_at, now()),
      last_error = 'ambiguous_remote_worker_interruption',
      updated_at = now()
  where entity_kind = 'customer'
    and operation = 'create'
    and (
      (status = 'processing' and updated_at < now() - interval '2 minutes')
      or (status = 'blocked' and last_error = 'ambiguous_worker_interruption')
    );
  get diagnostics v_customer_creates = row_count;

  return jsonb_build_object(
    'stale_source_leases_recovered', v_source_leases,
    'safe_processing_requeued', v_safe_processing,
    'safe_blocked_requeued', v_safe_blocked,
    'customer_creates_sent_to_reconciliation', v_customer_creates
  );
end;
$$;

revoke all on function private.recover_daftar_sync_runtime() from public;
revoke all on function private.recover_daftar_sync_runtime() from anon;
revoke all on function private.recover_daftar_sync_runtime() from authenticated;

-- Keep the main guardian authoritative over all Daftar runtime jobs, including
-- the recovery watchdog, so a deleted/disabled cron is repaired within a minute.
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
begin
  perform set_config('zhirox.daftar_sync_guardian','on',true);

  insert into private.daftar_source_fingerprint_aliases(
    sync_source_id,source_fingerprint,alias_kind
  )
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
       or encode(extensions.digest(v_secret,'sha256'),'hex')
          is distinct from r.trigger_secret_hash then
      v_invalid := v_invalid + 1;

      update public.daftar_sync_sources
      set health_status='degraded',
          last_status='failed',
          last_error='trigger_secret_missing_or_invalid',
          updated_at=now()
      where id=r.id;
    else
      v_valid := v_valid + 1;

      update public.daftar_sync_sources
      set last_error=null,
          updated_at=now()
      where id=r.id
        and last_error='trigger_secret_missing_or_invalid';
    end if;

    perform public.qualify_daftar_outage(r.id);
  end loop;

  for j in
    select jobid
    from cron.job
    where jobname in (
      'daftar-live-sync-account-28',
      'daftar-sync-reconcile-account-28',
      'daily-tenant-backup-account-28',
      'daily-daftar-tenant-backup-all',
      'daftar-sync-guardian-account-28',
      'daftar-outbound-sync-account-28',
      'daftar-sync-dispatch-all',
      'daftar-sync-reconcile-all',
      'daftar-sync-guardian-all'
    )
  loop
    perform cron.unschedule(j.jobid);
    v_removed_legacy := v_removed_legacy + 1;
  end loop;

  select jobid into v_job_id
  from cron.job
  where jobname='daftar-sync-multitenant-dispatch'
  limit 1;
  if v_job_id is null then
    perform cron.schedule(
      'daftar-sync-multitenant-dispatch', '30 seconds',
      'select private.dispatch_daftar_sync_sources();'
    );
  else
    perform cron.alter_job(
      job_id=>v_job_id, schedule=>'30 seconds',
      command=>'select private.dispatch_daftar_sync_sources();', active=>true
    );
  end if;

  select jobid into v_job_id
  from cron.job
  where jobname='daftar-sync-multitenant-reconcile'
  limit 1;
  if v_job_id is null then
    perform cron.schedule(
      'daftar-sync-multitenant-reconcile', '17 * * * *',
      'select private.reconcile_daftar_sync_sources();'
    );
  else
    perform cron.alter_job(
      job_id=>v_job_id, schedule=>'17 * * * *',
      command=>'select private.reconcile_daftar_sync_sources();', active=>true
    );
  end if;

  select jobid into v_job_id
  from cron.job
  where jobname='daftar-sync-multitenant-guardian'
  limit 1;
  if v_job_id is null then
    perform cron.schedule(
      'daftar-sync-multitenant-guardian', '* * * * *',
      'select private.guard_daftar_sync_sources();'
    );
  else
    perform cron.alter_job(
      job_id=>v_job_id, schedule=>'* * * * *',
      command=>'select private.guard_daftar_sync_sources();', active=>true
    );
  end if;

  select jobid into v_job_id
  from cron.job
  where jobname='daftar-sync-runtime-recovery'
  limit 1;
  if v_job_id is null then
    perform cron.schedule(
      'daftar-sync-runtime-recovery', '* * * * *',
      'select private.recover_daftar_sync_runtime();'
    );
  else
    perform cron.alter_job(
      job_id=>v_job_id, schedule=>'* * * * *',
      command=>'select private.recover_daftar_sync_runtime();', active=>true
    );
  end if;

  perform private.guard_backup_runtime();

  return jsonb_build_object(
    'valid_sources',v_valid,
    'invalid_sources',v_invalid,
    'deprecated_jobs_removed',v_removed_legacy,
    'runtime_jobs',4
  );
end;
$$;

revoke all on function private.guard_daftar_sync_sources() from public;
revoke all on function private.guard_daftar_sync_sources() from anon;
revoke all on function private.guard_daftar_sync_sources() from authenticated;

do $$
declare
  v_job_id bigint;
begin
  select jobid into v_job_id
  from cron.job
  where jobname = 'daftar-sync-runtime-recovery'
  limit 1;

  if v_job_id is null then
    perform cron.schedule(
      'daftar-sync-runtime-recovery', '* * * * *',
      'select private.recover_daftar_sync_runtime();'
    );
  else
    perform cron.alter_job(
      job_id => v_job_id,
      schedule => '* * * * *',
      command => 'select private.recover_daftar_sync_runtime();',
      active => true
    );
  end if;
end;
$$;