-- Wire restore drills into the Daftar continuity health model and self-healing runtime.

create or replace function private.run_daftar_restore_drill()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  r record;
  v_snapshot uuid;
  v_result jsonb;
  v_pass integer := 0;
  v_fail integer := 0;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('zhirox-daftar-restore-drill',0)) then
    return jsonb_build_object('skipped','already_running');
  end if;

  for r in
    select id from public.daftar_sync_sources
    where enabled=true or inbound_sync_enabled=true or outbound_sync_enabled=true
    order by created_at
  loop
    select id into v_snapshot
    from private.daftar_sync_state_snapshots
    where sync_source_id=r.id
    order by captured_at desc
    limit 1;

    if v_snapshot is null then
      v_result := jsonb_build_object('status','fail','reason','no_snapshot');
    else
      v_result := private.validate_daftar_sync_state_snapshot(v_snapshot);
    end if;

    insert into private.daftar_restore_drill_state(sync_source_id,snapshot_id,checked_at,status,details)
    values(r.id,v_snapshot,now(),case when v_result->>'status'='pass' then 'pass' else 'fail' end,v_result)
    on conflict(sync_source_id) do update
    set snapshot_id=excluded.snapshot_id,checked_at=excluded.checked_at,status=excluded.status,details=excluded.details;

    perform private.set_daftar_integrity_dead_letter(
      r.id,'restore_drill_failed',coalesce(v_result->>'status','fail')<>'pass',v_result
    );

    if v_result->>'status'='pass' then v_pass:=v_pass+1; else v_fail:=v_fail+1; end if;
  end loop;

  return jsonb_build_object('pass',v_pass,'fail',v_fail);
end;
$$;
revoke all on function private.run_daftar_restore_drill() from public,anon,authenticated;

create or replace function private.guard_daftar_restore_drill_runtime()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  r record;
  v_job bigint;
  v_stale integer := 0;
begin
  select jobid into v_job from cron.job where jobname='daftar-sync-restore-drill' limit 1;
  if v_job is null then
    perform cron.schedule('daftar-sync-restore-drill','5,20,35,50 * * * *','select private.run_daftar_restore_drill();');
  else
    perform cron.alter_job(job_id=>v_job,schedule=>'5,20,35,50 * * * *',command=>'select private.run_daftar_restore_drill();',active=>true);
  end if;

  for r in
    select s.id,d.checked_at,d.status,d.details
    from public.daftar_sync_sources s
    left join private.daftar_restore_drill_state d on d.sync_source_id=s.id
    where s.enabled=true or s.inbound_sync_enabled=true or s.outbound_sync_enabled=true
  loop
    if r.checked_at is null or r.checked_at<now()-interval '25 minutes' then
      v_stale:=v_stale+1;
      perform private.set_daftar_integrity_dead_letter(
        r.id,'restore_drill_stale',true,
        jsonb_build_object('last_checked_at',r.checked_at,'last_status',r.status)
      );
    else
      perform private.set_daftar_integrity_dead_letter(r.id,'restore_drill_stale',false,'{}'::jsonb);
    end if;
  end loop;

  return jsonb_build_object('job','daftar-sync-restore-drill','stale_sources',v_stale);
end;
$$;
revoke all on function private.guard_daftar_restore_drill_runtime() from public,anon,authenticated;

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
  v_restore_guard jsonb;
  r record;
  v_dl jsonb;
begin
  perform set_config('zhirox.daftar_sync_guardian','on',true);

  update public.daftar_sync_sources
  set lease_until=null,last_status='failed',last_error='stale_sync_lease_recovered',next_retry_at=now(),circuit_open_until=null,health_status='degraded',updated_at=now()
  where enabled=true and last_status='running' and lease_until is not null and lease_until<now()
    and coalesce(last_heartbeat_at,last_started_at,updated_at)<now()-interval '2 minutes';
  get diagnostics v_source_leases=row_count;

  update public.daftar_outbound_events
  set status='failed',next_attempt_at=now(),last_error='worker_interruption_safe_retry',updated_at=now()
  where status='processing' and operation in ('update','delete') and updated_at<now()-interval '2 minutes';
  get diagnostics v_safe_processing=row_count;

  update public.daftar_outbound_events
  set status='failed',next_attempt_at=now(),last_error='ambiguous_write_safe_retry',updated_at=now()
  where status='blocked' and operation in ('update','delete')
    and (last_error='ambiguous_worker_interruption' or last_error like 'ambiguous_remote_%' or last_error like 'ambiguous_mapping_failed:%');
  get diagnostics v_safe_blocked=row_count;

  update public.daftar_outbound_events
  set status='blocked',next_attempt_at=least(next_attempt_at,now()),last_error='ambiguous_remote_worker_interruption',updated_at=now()
  where entity_kind='customer' and operation='create'
    and ((status='processing' and updated_at<now()-interval '2 minutes') or (status='blocked' and last_error='ambiguous_worker_interruption'));
  get diagnostics v_customer_creates=row_count;

  for r in
    select id from public.daftar_sync_sources
    where enabled=true or inbound_sync_enabled=true or outbound_sync_enabled=true
  loop
    v_dl:=private.resolve_daftar_transient_dead_letters(r.id);
    v_deadletters:=v_deadletters
      + coalesce((v_dl->>'transient_resolved')::int,0)
      + coalesce((v_dl->>'autopilot_permission_resolved')::int,0)
      + coalesce((v_dl->>'identity_resolved')::int,0);
    perform public.resolve_daftar_recovered_dead_letters(r.id);
    perform public.qualify_daftar_outage(r.id);
  end loop;

  v_restore_guard:=private.guard_daftar_restore_drill_runtime();

  return jsonb_build_object(
    'stale_source_leases_recovered',v_source_leases,
    'safe_processing_requeued',v_safe_processing,
    'safe_blocked_requeued',v_safe_blocked,
    'customer_creates_sent_to_reconciliation',v_customer_creates,
    'dead_letters_auto_resolved',v_deadletters,
    'restore_drill_guard',v_restore_guard
  );
end;
$$;
revoke all on function private.recover_daftar_sync_runtime() from public,anon,authenticated;
