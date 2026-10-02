-- Strengthen Daftar <-> ZHIROX continuity with real dispatcher backoff,
-- self-healing dead-letter resolution, recovered outage state, and dual watchdogs.

create or replace function public.record_daftar_sync_failure(
  p_source_id uuid,
  p_error_code text,
  p_error_detail text default null,
  p_entity_kind text default 'sync',
  p_entity_source_id text default null,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_failures integer;
  v_retry_seconds integer;
  v_circuit_until timestamptz;
begin
  select consecutive_failures + 1 into v_failures
  from public.daftar_sync_sources where id = p_source_id for update;
  if v_failures is null then raise exception 'sync_source_not_found'; end if;

  v_retry_seconds := least(300, (15 * power(2, least(v_failures - 1, 5)))::integer);
  if v_failures >= 7 then v_circuit_until := now() + interval '3 minutes'; end if;

  update public.daftar_sync_sources
  set lease_until = null,
      consecutive_failures = v_failures,
      total_failures = total_failures + 1,
      next_retry_at = now() + make_interval(secs => v_retry_seconds),
      circuit_open_until = v_circuit_until,
      last_heartbeat_at = now(),
      last_status = 'failed',
      last_error = left(coalesce(p_error_code, 'unknown_error') || coalesce(': ' || p_error_detail, ''), 2000),
      health_status = case when v_circuit_until is null then 'degraded' else 'circuit_open' end,
      updated_at = now()
  where id = p_source_id;

  insert into public.daftar_sync_dead_letters(
    sync_source_id, entity_kind, source_id, error_code, error_detail, payload
  ) values (
    p_source_id, coalesce(nullif(p_entity_kind,''),'sync'), p_entity_source_id,
    coalesce(nullif(p_error_code,''),'unknown_error'), left(p_error_detail, 4000), coalesce(p_payload,'{}'::jsonb)
  )
  on conflict (sync_source_id, entity_kind, coalesce(source_id, ''), error_code)
    where resolved_at is null
  do update set attempts = public.daftar_sync_dead_letters.attempts + 1,
                last_seen_at = now(),
                error_detail = excluded.error_detail,
                payload = excluded.payload;

  return jsonb_build_object(
    'consecutive_failures', v_failures,
    'retry_after_seconds', v_retry_seconds,
    'circuit_open_until', v_circuit_until
  );
end;
$$;

create or replace function private.dispatch_daftar_sync_sources()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_secret text;
  v_inbound_count integer := 0;
  v_outbound_count integer := 0;
  v_skipped_count integer := 0;
  v_backoff_skipped integer := 0;
  v_inbound_allowed boolean;
begin
  for r in
    select
      s.id,
      s.legacy_user_id,
      s.source_fingerprint,
      s.trigger_secret_hash,
      s.trigger_secret_vault_name,
      s.sync_mode,
      s.inbound_sync_enabled,
      s.outbound_sync_enabled,
      s.outbound_write_contract_status,
      s.lease_until,
      s.next_retry_at,
      s.circuit_open_until
    from public.daftar_sync_sources s
    where s.enabled = true
      and nullif(s.trigger_secret_vault_name, '') is not null
    order by s.created_at
  loop
    v_secret := null;

    select decrypted_secret into v_secret
    from vault.decrypted_secrets
    where name = r.trigger_secret_vault_name
    limit 1;

    if v_secret is null
       or encode(extensions.digest(v_secret, 'sha256'), 'hex')
          is distinct from r.trigger_secret_hash then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    v_inbound_allowed :=
      (r.lease_until is null or r.lease_until <= now())
      and (r.next_retry_at is null or r.next_retry_at <= now())
      and (r.circuit_open_until is null or r.circuit_open_until <= now());

    if (r.sync_mode = 'mirror'
        or (r.sync_mode = 'zhirox_primary' and r.inbound_sync_enabled = true)) then
      if v_inbound_allowed then
        perform net.http_post(
          url := 'https://madoflmbretqghqbqaak.supabase.co/functions/v1/daftar-sync-gateway',
          headers := jsonb_build_object(
            'Content-Type','application/json',
            'x-daftar-sync-secret',v_secret
          ),
          body := jsonb_build_object('source_id',r.id),
          timeout_milliseconds := 120000
        );
        v_inbound_count := v_inbound_count + 1;
      else
        v_backoff_skipped := v_backoff_skipped + 1;
      end if;
    end if;

    if r.sync_mode = 'zhirox_primary'
       and r.outbound_sync_enabled = true
       and r.outbound_write_contract_status = 'verified' then
      perform net.http_post(
        url := 'https://madoflmbretqghqbqaak.supabase.co/functions/v1/daftar-outbound-sync',
        headers := jsonb_build_object(
          'Content-Type','application/json',
          'x-daftar-sync-secret',v_secret
        ),
        body := jsonb_build_object('source_id',r.id,'action','drain'),
        timeout_milliseconds := 120000
      );
      v_outbound_count := v_outbound_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'inbound_dispatched',v_inbound_count,
    'outbound_dispatched',v_outbound_count,
    'skipped_missing_or_invalid_secret',v_skipped_count,
    'inbound_skipped_backoff_or_lease',v_backoff_skipped
  );
end;
$$;

revoke all on function private.dispatch_daftar_sync_sources() from public;
revoke all on function private.dispatch_daftar_sync_sources() from anon;
revoke all on function private.dispatch_daftar_sync_sources() from authenticated;

create or replace function public.qualify_daftar_outage(p_source_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source public.daftar_sync_sources%rowtype;
  v_status text;
  v_suspected_at timestamptz;
  v_confirmed_at timestamptz;
  v_primary_reason text;
begin
  select * into v_source
  from public.daftar_sync_sources
  where id = p_source_id
    and legacy_user_id = 28
    and source_fingerprint = 'daftar-live-account-28-v1'
  for update;

  if v_source.id is null then
    raise exception 'daftar_source_not_available' using errcode = '42501';
  end if;

  select e.reason into v_primary_reason
  from public.daftar_source_mode_events e
  where e.sync_source_id = v_source.id
    and e.to_mode = 'zhirox_primary'
  order by e.created_at desc
  limit 1;

  if v_source.health_status = 'healthy'
     and v_source.consecutive_failures = 0
     and v_source.last_success_at is not null
     and v_source.last_success_at >= now() - interval '5 minutes' then
    v_status := 'healthy';
    v_suspected_at := null;
    v_confirmed_at := null;
  elsif v_source.sync_mode = 'zhirox_primary'
        and v_primary_reason = 'planned_primary_cutover_while_source_healthy' then
    v_status := 'healthy';
    v_suspected_at := null;
    v_confirmed_at := null;
  elsif v_source.consecutive_failures >= 7
        and v_source.circuit_open_until is not null
        and v_source.circuit_open_until > now()
        and (v_source.last_success_at is null
             or v_source.last_success_at <= now() - interval '5 minutes') then
    v_status := 'confirmed';
    v_suspected_at := coalesce(v_source.outage_suspected_at, now());
    v_confirmed_at := coalesce(v_source.outage_confirmed_at, now());
  elsif v_source.last_success_at is null
        or v_source.last_success_at <= now() - interval '5 minutes' then
    v_status := case when v_source.outage_status = 'confirmed' then 'confirmed' else 'suspected' end;
    v_suspected_at := coalesce(v_source.outage_suspected_at, now());
    v_confirmed_at := case when v_status='confirmed' then coalesce(v_source.outage_confirmed_at, now()) else null end;
  else
    v_status := 'suspected';
    v_suspected_at := coalesce(v_source.outage_suspected_at, now());
    v_confirmed_at := null;
  end if;

  update public.daftar_sync_sources
  set outage_status = v_status,
      outage_suspected_at = v_suspected_at,
      outage_confirmed_at = v_confirmed_at,
      updated_at = now()
  where id = v_source.id;

  return jsonb_build_object(
    'outage_status', v_status,
    'consecutive_failures', v_source.consecutive_failures,
    'last_success_at', v_source.last_success_at,
    'circuit_open_until', v_source.circuit_open_until,
    'outage_suspected_at', v_suspected_at,
    'outage_confirmed_at', v_confirmed_at,
    'primary_reason', v_primary_reason
  );
end;
$$;

create or replace function private.resolve_daftar_transient_dead_letters(p_source_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source public.daftar_sync_sources%rowtype;
  v_transient integer := 0;
  v_identity integer := 0;
  v_autopilot integer := 0;
  v_autopilot_safe boolean := false;
begin
  select * into v_source from public.daftar_sync_sources where id = p_source_id;
  if v_source.id is null then raise exception 'sync_source_not_found'; end if;

  select count(*) = 2 and coalesce(bool_and(p.prosecdef), false)
    into v_autopilot_safe
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private'
    and p.proname in ('enqueue_autopilot_debt_event','enqueue_autopilot_payment_event');

  if v_source.health_status='healthy'
     and v_source.consecutive_failures=0
     and v_source.last_success_at is not null
     and v_source.reconciliation_status='clean'
     and v_source.reconciliation_missing_contacts=0
     and v_source.reconciliation_missing_transactions=0
     and v_source.cutover_rehearsal_status='pass'
     and v_source.cutover_rehearsal_mismatches=0 then

    update public.daftar_sync_dead_letters d
    set resolved_at=now(),
        resolution_note='auto_resolved_after_newer_healthy_sync_and_clean_reconciliation'
    where d.sync_source_id=p_source_id
      and d.resolved_at is null
      and d.last_seen_at < v_source.last_success_at
      and (
        d.error_code in ('Gateway Timeout','Bad Gateway','source_http_502')
        or d.error_code ~ '^source_http_5[0-9][0-9]$'
        or d.error_code in ('source_http_408','source_http_425','source_http_429')
      );
    get diagnostics v_transient=row_count;

    if v_autopilot_safe then
      update public.daftar_sync_dead_letters d
      set resolved_at=now(),
          resolution_note='auto_resolved_after_autopilot_trigger_permission_fix_and_newer_healthy_sync'
      where d.sync_source_id=p_source_id
        and d.resolved_at is null
        and d.last_seen_at < v_source.last_success_at
        and d.error_code='permission denied for table autopilot_events';
      get diagnostics v_autopilot=row_count;
    end if;

    if v_source.last_reconciled_at is not null then
      update public.daftar_sync_dead_letters d
      set resolved_at=now(),
          resolution_note='auto_resolved_after_newer_clean_customer_identity_reconciliation'
      where d.sync_source_id=p_source_id
        and d.resolved_at is null
        and d.error_code='customer_identity_reconciliation_failed'
        and d.last_seen_at < v_source.last_reconciled_at;
      get diagnostics v_identity=row_count;
    end if;
  end if;

  return jsonb_build_object(
    'transient_resolved',v_transient,
    'autopilot_permission_resolved',v_autopilot,
    'identity_resolved',v_identity,
    'autopilot_safe',v_autopilot_safe
  );
end;
$$;

revoke all on function private.resolve_daftar_transient_dead_letters(uuid) from public;
revoke all on function private.resolve_daftar_transient_dead_letters(uuid) from anon;
revoke all on function private.resolve_daftar_transient_dead_letters(uuid) from authenticated;

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
  v_deadletters integer := 0;
  r record;
  v_dl jsonb;
begin
  perform set_config('zhirox.daftar_sync_guardian', 'on', true);

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
    and coalesce(last_heartbeat_at, last_started_at, updated_at) < now() - interval '2 minutes';
  get diagnostics v_source_leases = row_count;

  update public.daftar_outbound_events
  set status = 'failed', next_attempt_at = now(),
      last_error = 'worker_interruption_safe_retry', updated_at = now()
  where status = 'processing'
    and operation in ('update', 'delete')
    and updated_at < now() - interval '2 minutes';
  get diagnostics v_safe_processing = row_count;

  update public.daftar_outbound_events
  set status = 'failed', next_attempt_at = now(),
      last_error = 'ambiguous_write_safe_retry', updated_at = now()
  where status = 'blocked'
    and operation in ('update', 'delete')
    and (
      last_error = 'ambiguous_worker_interruption'
      or last_error like 'ambiguous_remote_%'
      or last_error like 'ambiguous_mapping_failed:%'
    );
  get diagnostics v_safe_blocked = row_count;

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

  for r in
    select id from public.daftar_sync_sources
    where enabled=true or inbound_sync_enabled=true or outbound_sync_enabled=true
  loop
    v_dl := private.resolve_daftar_transient_dead_letters(r.id);
    v_deadletters := v_deadletters
      + coalesce((v_dl->>'transient_resolved')::int,0)
      + coalesce((v_dl->>'autopilot_permission_resolved')::int,0)
      + coalesce((v_dl->>'identity_resolved')::int,0);
    perform public.resolve_daftar_recovered_dead_letters(r.id);
    perform public.qualify_daftar_outage(r.id);
  end loop;

  return jsonb_build_object(
    'stale_source_leases_recovered', v_source_leases,
    'safe_processing_requeued', v_safe_processing,
    'safe_blocked_requeued', v_safe_blocked,
    'customer_creates_sent_to_reconciliation', v_customer_creates,
    'dead_letters_auto_resolved', v_deadletters
  );
end;
$$;

revoke all on function private.recover_daftar_sync_runtime() from public;
revoke all on function private.recover_daftar_sync_runtime() from anon;
revoke all on function private.recover_daftar_sync_runtime() from authenticated;

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
  if v_job_id is null then
    perform cron.schedule('daftar-sync-multitenant-dispatch','30 seconds','select private.dispatch_daftar_sync_sources();');
  else
    perform cron.alter_job(job_id=>v_job_id,schedule=>'30 seconds',command=>'select private.dispatch_daftar_sync_sources();',active=>true);
  end if;

  select jobid into v_job_id from cron.job where jobname='daftar-sync-multitenant-reconcile' limit 1;
  if v_job_id is null then
    perform cron.schedule('daftar-sync-multitenant-reconcile','17 * * * *','select private.reconcile_daftar_sync_sources();');
  else
    perform cron.alter_job(job_id=>v_job_id,schedule=>'17 * * * *',command=>'select private.reconcile_daftar_sync_sources();',active=>true);
  end if;

  select jobid into v_job_id from cron.job where jobname='daftar-sync-multitenant-guardian' limit 1;
  if v_job_id is null then
    perform cron.schedule('daftar-sync-multitenant-guardian','* * * * *','select private.guard_daftar_sync_sources();');
  else
    perform cron.alter_job(job_id=>v_job_id,schedule=>'* * * * *',command=>'select private.guard_daftar_sync_sources();',active=>true);
  end if;

  select jobid into v_job_id from cron.job where jobname='daftar-sync-runtime-recovery' limit 1;
  if v_job_id is null then
    perform cron.schedule('daftar-sync-runtime-recovery','* * * * *','select private.recover_daftar_sync_runtime();');
  else
    perform cron.alter_job(job_id=>v_job_id,schedule=>'* * * * *',command=>'select private.recover_daftar_sync_runtime();',active=>true);
  end if;

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
    'runtime_jobs',4,
    'forced_liveness_dispatch',v_forced_dispatch
  );
end;
$$;

revoke all on function private.guard_daftar_sync_sources() from public;
revoke all on function private.guard_daftar_sync_sources() from anon;
revoke all on function private.guard_daftar_sync_sources() from authenticated;
