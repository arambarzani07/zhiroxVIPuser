-- Disaster-recovery hardening for Daftar <-> ZHIROX logical sync state.
-- Adds a tamper-evident snapshot chain, daily anchors, and non-destructive restore drills.

alter table private.daftar_sync_state_snapshots
  add column if not exists sequence_no bigint,
  add column if not exists prev_chain_sha256 text,
  add column if not exists chain_sha256 text;

create unique index if not exists daftar_sync_state_snapshots_source_sequence_uq
  on private.daftar_sync_state_snapshots(sync_source_id, sequence_no)
  where sequence_no is not null;

create table if not exists private.daftar_snapshot_chain_anchors (
  sync_source_id uuid not null references public.daftar_sync_sources(id) on delete cascade,
  anchor_date date not null,
  snapshot_id uuid not null references private.daftar_sync_state_snapshots(id) on delete cascade,
  sequence_no bigint not null,
  chain_sha256 text not null,
  anchored_at timestamptz not null default now(),
  primary key(sync_source_id,anchor_date)
);
revoke all on table private.daftar_snapshot_chain_anchors from public,anon,authenticated;

do $$
declare r record; v_source uuid; v_seq bigint:=0; v_prev text:=null; v_chain text;
begin
  for r in select id,sync_source_id,payload_sha256,captured_at from private.daftar_sync_state_snapshots order by sync_source_id,captured_at,id
  loop
    if v_source is distinct from r.sync_source_id then v_source:=r.sync_source_id; v_seq:=0; v_prev:=null; end if;
    v_seq:=v_seq+1;
    v_chain:=encode(extensions.digest(coalesce(v_prev,'GENESIS')||':'||r.payload_sha256||':'||v_seq::text||':'||r.sync_source_id::text,'sha256'),'hex');
    update private.daftar_sync_state_snapshots set sequence_no=v_seq,prev_chain_sha256=v_prev,chain_sha256=v_chain where id=r.id;
    v_prev:=v_chain;
  end loop;
end;
$$;

create or replace function private.verify_daftar_snapshot_chain(p_source_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare r record; v_expected_prev text:=null; v_expected_chain text; v_payload_hash text; v_total int:=0; v_payload_invalid int:=0; v_chain_invalid int:=0; v_prev_invalid int:=0; v_last_seq bigint;
begin
  for r in select * from private.daftar_sync_state_snapshots where sync_source_id=p_source_id order by sequence_no,captured_at,id
  loop
    v_total:=v_total+1;
    v_payload_hash:=encode(extensions.digest(jsonb_build_object('source_state',r.source_state,'active_outbox_state',r.active_outbox_state,'unresolved_dead_letters',r.unresolved_dead_letters,'integrity_state',r.integrity_state)::text,'sha256'),'hex');
    if v_payload_hash is distinct from r.payload_sha256 then v_payload_invalid:=v_payload_invalid+1; end if;
    if v_total=1 then v_expected_prev:=r.prev_chain_sha256; elsif r.prev_chain_sha256 is distinct from v_expected_prev then v_prev_invalid:=v_prev_invalid+1; end if;
    v_expected_chain:=encode(extensions.digest(coalesce(r.prev_chain_sha256,'GENESIS')||':'||r.payload_sha256||':'||r.sequence_no::text||':'||r.sync_source_id::text,'sha256'),'hex');
    if v_expected_chain is distinct from r.chain_sha256 then v_chain_invalid:=v_chain_invalid+1; end if;
    v_expected_prev:=r.chain_sha256; v_last_seq:=r.sequence_no;
  end loop;
  return jsonb_build_object('status',case when v_total>0 and v_payload_invalid=0 and v_chain_invalid=0 and v_prev_invalid=0 then 'healthy' else 'critical' end,'snapshots',v_total,'payload_invalid',v_payload_invalid,'chain_invalid',v_chain_invalid,'prev_link_invalid',v_prev_invalid,'last_sequence',v_last_seq);
end;
$$;
revoke all on function private.verify_daftar_snapshot_chain(uuid) from public,anon,authenticated;

create table if not exists private.daftar_restore_drill_state (
  sync_source_id uuid primary key references public.daftar_sync_sources(id) on delete cascade,
  snapshot_id uuid,
  checked_at timestamptz not null default now(),
  status text not null check(status in ('pass','fail')),
  details jsonb not null default '{}'::jsonb
);
revoke all on table private.daftar_restore_drill_state from public,anon,authenticated;

create or replace function private.validate_daftar_sync_state_snapshot(p_snapshot_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare s private.daftar_sync_state_snapshots%rowtype; live public.daftar_sync_sources%rowtype; v_checksum boolean:=false; v_chain jsonb; v_source_match boolean:=false; v_outbox_count int:=0; v_dead_count int:=0; v_duplicate_keys int:=0; v_cursor_regression boolean:=false; v_status text;
begin
  select * into s from private.daftar_sync_state_snapshots where id=p_snapshot_id;
  if s.id is null then raise exception 'snapshot_not_found' using errcode='P0002'; end if;
  select * into live from public.daftar_sync_sources where id=s.sync_source_id;
  if live.id is null then raise exception 'sync_source_not_found' using errcode='P0002'; end if;
  v_checksum:=private.verify_daftar_sync_state_snapshot(s.id);
  v_chain:=private.verify_daftar_snapshot_chain(s.sync_source_id);
  v_source_match:=(s.source_state->>'id')::uuid=live.id and coalesce((s.source_state->>'legacy_user_id')::bigint,-1)=coalesce(live.legacy_user_id,-1) and coalesce(s.source_state->>'source_fingerprint','')=coalesce(live.source_fingerprint,'');
  select count(*) into v_outbox_count from jsonb_array_elements(s.active_outbox_state);
  select count(*) into v_dead_count from jsonb_array_elements(s.unresolved_dead_letters);
  select count(*) into v_duplicate_keys from (select x->>'idempotency_key' k from jsonb_array_elements(s.active_outbox_state) x where nullif(x->>'idempotency_key','') is not null group by x->>'idempotency_key' having count(*)>1) q;
  v_cursor_regression:=coalesce((s.source_state->>'last_contact_id')::bigint,0)<coalesce(live.last_contact_id,0) or coalesce((s.source_state->>'last_transaction_id')::bigint,0)<coalesce(live.last_transaction_id,0);
  v_status:=case when v_checksum and coalesce(v_chain->>'status','critical')='healthy' and v_source_match and v_duplicate_keys=0 then 'pass' else 'fail' end;
  return jsonb_build_object('status',v_status,'snapshot_id',s.id,'captured_at',s.captured_at,'checksum_valid',v_checksum,'chain_status',v_chain->>'status','source_identity_matches',v_source_match,'active_outbox_events',v_outbox_count,'unresolved_dead_letters',v_dead_count,'duplicate_idempotency_keys',v_duplicate_keys,'would_regress_live_cursor',v_cursor_regression,'restore_requires_explicit_break_glass',v_cursor_regression);
end;
$$;
revoke all on function private.validate_daftar_sync_state_snapshot(uuid) from public,anon,authenticated;

create or replace function private.run_daftar_restore_drill()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare r record; v_snapshot uuid; v_result jsonb; v_pass int:=0; v_fail int:=0;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('zhirox-daftar-restore-drill',0)) then return jsonb_build_object('skipped','already_running'); end if;
  for r in select id from public.daftar_sync_sources where enabled=true or inbound_sync_enabled=true or outbound_sync_enabled=true order by created_at
  loop
    select id into v_snapshot from private.daftar_sync_state_snapshots where sync_source_id=r.id order by captured_at desc limit 1;
    if v_snapshot is null then v_result:=jsonb_build_object('status','fail','reason','no_snapshot'); else v_result:=private.validate_daftar_sync_state_snapshot(v_snapshot); end if;
    insert into private.daftar_restore_drill_state(sync_source_id,snapshot_id,checked_at,status,details)
    values(r.id,v_snapshot,now(),case when v_result->>'status'='pass' then 'pass' else 'fail' end,v_result)
    on conflict(sync_source_id) do update set snapshot_id=excluded.snapshot_id,checked_at=excluded.checked_at,status=excluded.status,details=excluded.details;
    if v_result->>'status'='pass' then v_pass:=v_pass+1; else v_fail:=v_fail+1; end if;
  end loop;
  return jsonb_build_object('pass',v_pass,'fail',v_fail);
end;
$$;
revoke all on function private.run_daftar_restore_drill() from public,anon,authenticated;

create or replace function private.capture_daftar_sync_state_snapshots()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare r record; v_source jsonb; v_outbox jsonb; v_dead jsonb; v_integrity jsonb; v_material jsonb; v_hash text; v_prev_chain text; v_seq bigint; v_chain text; v_snapshot_id uuid; v_count int:=0;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('zhirox-daftar-state-snapshot',0)) then return jsonb_build_object('skipped','already_running'); end if;
  for r in select * from public.daftar_sync_sources where enabled=true or inbound_sync_enabled=true or outbound_sync_enabled=true order by created_at
  loop
    v_source:=jsonb_build_object('id',r.id,'legacy_user_id',r.legacy_user_id,'source_name',r.source_name,'source_fingerprint',r.source_fingerprint,'enabled',r.enabled,'last_contact_id',r.last_contact_id,'last_transaction_id',r.last_transaction_id,'contacts_etag',r.contacts_etag,'transactions_etag',r.transactions_etag,'last_started_at',r.last_started_at,'last_success_at',r.last_success_at,'last_status',r.last_status,'consecutive_failures',r.consecutive_failures,'next_retry_at',r.next_retry_at,'circuit_open_until',r.circuit_open_until,'last_heartbeat_at',r.last_heartbeat_at,'health_status',r.health_status,'sync_mode',r.sync_mode,'reconciliation_status',r.reconciliation_status,'reconciliation_missing_contacts',r.reconciliation_missing_contacts,'reconciliation_missing_transactions',r.reconciliation_missing_transactions,'cutover_rehearsal_status',r.cutover_rehearsal_status,'cutover_rehearsal_mismatches',r.cutover_rehearsal_mismatches,'outage_status',r.outage_status,'inbound_sync_enabled',r.inbound_sync_enabled,'outbound_sync_enabled',r.outbound_sync_enabled,'outbound_write_contract_status',r.outbound_write_contract_status);
    select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'entity_kind',o.entity_kind,'entity_id',o.entity_id,'operation',o.operation,'idempotency_key',o.idempotency_key,'status',o.status,'remote_id',o.remote_id,'attempts',o.attempts,'next_attempt_at',o.next_attempt_at,'last_error',o.last_error,'created_at',o.created_at,'updated_at',o.updated_at,'sent_at',o.sent_at,'remote_id_snapshot',o.remote_id_snapshot) order by o.created_at,o.id),'[]'::jsonb) into v_outbox from public.daftar_outbound_events o where o.sync_source_id=r.id and o.status in ('pending','processing','failed','blocked');
    select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'entity_kind',d.entity_kind,'source_id',d.source_id,'error_code',d.error_code,'attempts',d.attempts,'first_seen_at',d.first_seen_at,'last_seen_at',d.last_seen_at) order by d.last_seen_at,d.id),'[]'::jsonb) into v_dead from public.daftar_sync_dead_letters d where d.sync_source_id=r.id and d.resolved_at is null;
    select jsonb_build_object('deep_status',coalesce(di.status,'missing'),'deep_checked_at',di.checked_at,'contact_hash_or_mapping_mismatches',coalesce(di.contact_hash_or_mapping_mismatches,0),'transaction_hash_or_mapping_mismatches',coalesce(di.transaction_hash_or_mapping_mismatches,0),'open_cursor_anomalies',coalesce(di.open_cursor_anomalies,0),'max_contact_id',hw.max_contact_id,'max_transaction_id',hw.max_transaction_id) into v_integrity from (select 1) x left join private.daftar_deep_integrity_state di on di.sync_source_id=r.id left join private.daftar_cursor_high_water hw on hw.sync_source_id=r.id;
    v_material:=jsonb_build_object('source_state',v_source,'active_outbox_state',v_outbox,'unresolved_dead_letters',v_dead,'integrity_state',v_integrity);
    v_hash:=encode(extensions.digest(v_material::text,'sha256'),'hex');
    select chain_sha256,sequence_no into v_prev_chain,v_seq from private.daftar_sync_state_snapshots where sync_source_id=r.id order by sequence_no desc nulls last,captured_at desc limit 1;
    v_seq:=coalesce(v_seq,0)+1;
    v_chain:=encode(extensions.digest(coalesce(v_prev_chain,'GENESIS')||':'||v_hash||':'||v_seq::text||':'||r.id::text,'sha256'),'hex');
    insert into private.daftar_sync_state_snapshots(sync_source_id,source_state,active_outbox_state,unresolved_dead_letters,integrity_state,payload_sha256,sequence_no,prev_chain_sha256,chain_sha256)
    values(r.id,v_source,v_outbox,v_dead,v_integrity,v_hash,v_seq,v_prev_chain,v_chain) returning id into v_snapshot_id;
    insert into private.daftar_snapshot_chain_anchors(sync_source_id,anchor_date,snapshot_id,sequence_no,chain_sha256)
    values(r.id,current_date,v_snapshot_id,v_seq,v_chain) on conflict(sync_source_id,anchor_date) do nothing;
    v_count:=v_count+1;
  end loop;
  delete from private.daftar_sync_state_snapshots s where s.captured_at<now()-interval '7 days' and not exists(select 1 from private.daftar_snapshot_chain_anchors a where a.snapshot_id=s.id);
  delete from private.daftar_snapshot_chain_anchors where anchor_date<current_date-90;
  return jsonb_build_object('captured',v_count);
end;
$$;
revoke all on function private.capture_daftar_sync_state_snapshots() from public,anon,authenticated;

do $$ declare v_job bigint; begin
  select jobid into v_job from cron.job where jobname='daftar-sync-restore-drill' limit 1;
  if v_job is null then perform cron.schedule('daftar-sync-restore-drill','*/30 * * * *','select private.run_daftar_restore_drill();');
  else perform cron.alter_job(job_id=>v_job,schedule=>'*/30 * * * *',command=>'select private.run_daftar_restore_drill();',active=>true); end if;
end $$;
