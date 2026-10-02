-- Logical sync-control snapshots for Daftar <-> ZHIROX.
-- Captures control-plane state without copying business payload bodies.

create table if not exists private.daftar_sync_state_snapshots (
  id uuid primary key default gen_random_uuid(),
  sync_source_id uuid not null references public.daftar_sync_sources(id) on delete cascade,
  captured_at timestamptz not null default now(),
  source_state jsonb not null,
  active_outbox_state jsonb not null default '[]'::jsonb,
  unresolved_dead_letters jsonb not null default '[]'::jsonb,
  integrity_state jsonb not null default '{}'::jsonb,
  payload_sha256 text not null
);

create index if not exists daftar_sync_state_snapshots_source_time_idx
  on private.daftar_sync_state_snapshots(sync_source_id,captured_at desc);

revoke all on table private.daftar_sync_state_snapshots from public, anon, authenticated;

create or replace function private.capture_daftar_sync_state_snapshots()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_source jsonb;
  v_outbox jsonb;
  v_dead jsonb;
  v_integrity jsonb;
  v_material jsonb;
  v_hash text;
  v_count integer := 0;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('zhirox-daftar-state-snapshot',0)) then
    return jsonb_build_object('skipped','already_running');
  end if;

  for r in
    select * from public.daftar_sync_sources
    where enabled=true or inbound_sync_enabled=true or outbound_sync_enabled=true
    order by created_at
  loop
    v_source := jsonb_build_object(
      'id',r.id,
      'legacy_user_id',r.legacy_user_id,
      'source_name',r.source_name,
      'source_fingerprint',r.source_fingerprint,
      'enabled',r.enabled,
      'last_contact_id',r.last_contact_id,
      'last_transaction_id',r.last_transaction_id,
      'contacts_etag',r.contacts_etag,
      'transactions_etag',r.transactions_etag,
      'last_started_at',r.last_started_at,
      'last_success_at',r.last_success_at,
      'last_status',r.last_status,
      'consecutive_failures',r.consecutive_failures,
      'next_retry_at',r.next_retry_at,
      'circuit_open_until',r.circuit_open_until,
      'last_heartbeat_at',r.last_heartbeat_at,
      'health_status',r.health_status,
      'sync_mode',r.sync_mode,
      'reconciliation_status',r.reconciliation_status,
      'reconciliation_missing_contacts',r.reconciliation_missing_contacts,
      'reconciliation_missing_transactions',r.reconciliation_missing_transactions,
      'cutover_rehearsal_status',r.cutover_rehearsal_status,
      'cutover_rehearsal_mismatches',r.cutover_rehearsal_mismatches,
      'outage_status',r.outage_status,
      'inbound_sync_enabled',r.inbound_sync_enabled,
      'outbound_sync_enabled',r.outbound_sync_enabled,
      'outbound_write_contract_status',r.outbound_write_contract_status
    );

    select coalesce(jsonb_agg(jsonb_build_object(
      'id',o.id,
      'entity_kind',o.entity_kind,
      'entity_id',o.entity_id,
      'operation',o.operation,
      'idempotency_key',o.idempotency_key,
      'status',o.status,
      'remote_id',o.remote_id,
      'attempts',o.attempts,
      'next_attempt_at',o.next_attempt_at,
      'last_error',o.last_error,
      'created_at',o.created_at,
      'updated_at',o.updated_at,
      'sent_at',o.sent_at,
      'remote_id_snapshot',o.remote_id_snapshot
    ) order by o.created_at,o.id),'[]'::jsonb)
    into v_outbox
    from public.daftar_outbound_events o
    where o.sync_source_id=r.id and o.status in ('pending','processing','failed','blocked');

    select coalesce(jsonb_agg(jsonb_build_object(
      'id',d.id,
      'entity_kind',d.entity_kind,
      'source_id',d.source_id,
      'error_code',d.error_code,
      'attempts',d.attempts,
      'first_seen_at',d.first_seen_at,
      'last_seen_at',d.last_seen_at
    ) order by d.last_seen_at,d.id),'[]'::jsonb)
    into v_dead
    from public.daftar_sync_dead_letters d
    where d.sync_source_id=r.id and d.resolved_at is null;

    select jsonb_build_object(
      'deep_status',coalesce(di.status,'missing'),
      'deep_checked_at',di.checked_at,
      'contact_hash_or_mapping_mismatches',coalesce(di.contact_hash_or_mapping_mismatches,0),
      'transaction_hash_or_mapping_mismatches',coalesce(di.transaction_hash_or_mapping_mismatches,0),
      'open_cursor_anomalies',coalesce(di.open_cursor_anomalies,0),
      'max_contact_id',hw.max_contact_id,
      'max_transaction_id',hw.max_transaction_id
    )
    into v_integrity
    from (select 1) x
    left join private.daftar_deep_integrity_state di on di.sync_source_id=r.id
    left join private.daftar_cursor_high_water hw on hw.sync_source_id=r.id;

    v_material := jsonb_build_object(
      'source_state',v_source,
      'active_outbox_state',v_outbox,
      'unresolved_dead_letters',v_dead,
      'integrity_state',v_integrity
    );
    v_hash := encode(extensions.digest(v_material::text,'sha256'),'hex');

    insert into private.daftar_sync_state_snapshots(
      sync_source_id,source_state,active_outbox_state,unresolved_dead_letters,integrity_state,payload_sha256
    ) values(r.id,v_source,v_outbox,v_dead,v_integrity,v_hash);
    v_count := v_count + 1;
  end loop;

  delete from private.daftar_sync_state_snapshots where captured_at < now()-interval '7 days';
  return jsonb_build_object('captured',v_count);
end;
$$;
revoke all on function private.capture_daftar_sync_state_snapshots() from public, anon, authenticated;

create or replace function private.verify_daftar_sync_state_snapshot(p_snapshot_id uuid)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select coalesce(
    encode(extensions.digest(jsonb_build_object(
      'source_state',s.source_state,
      'active_outbox_state',s.active_outbox_state,
      'unresolved_dead_letters',s.unresolved_dead_letters,
      'integrity_state',s.integrity_state
    )::text,'sha256'),'hex') = s.payload_sha256,
    false
  )
  from private.daftar_sync_state_snapshots s
  where s.id=p_snapshot_id;
$$;
revoke all on function private.verify_daftar_sync_state_snapshot(uuid) from public, anon, authenticated;

do $$
declare v_job_id bigint;
begin
  select jobid into v_job_id from cron.job where jobname='daftar-sync-state-snapshot' limit 1;
  if v_job_id is null then
    perform cron.schedule('daftar-sync-state-snapshot','*/15 * * * *','select private.capture_daftar_sync_state_snapshots();');
  else
    perform cron.alter_job(job_id=>v_job_id,schedule=>'*/15 * * * *',command=>'select private.capture_daftar_sync_state_snapshots();',active=>true);
  end if;
end;
$$;