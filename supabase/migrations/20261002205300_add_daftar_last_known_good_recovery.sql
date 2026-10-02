-- Select and retain a validated Last Known Good logical recovery point for Daftar sync.

create table if not exists private.daftar_last_known_good_recovery (
  sync_source_id uuid primary key references public.daftar_sync_sources(id) on delete cascade,
  snapshot_id uuid not null references private.daftar_sync_state_snapshots(id) on delete restrict,
  selected_at timestamptz not null default now(),
  captured_at timestamptz not null,
  sequence_no bigint,
  payload_sha256 text not null,
  chain_sha256 text,
  validation jsonb not null
);
revoke all on table private.daftar_last_known_good_recovery from public,anon,authenticated;

create or replace function private.refresh_daftar_last_known_good_recovery(p_source_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  r record;
  v_validation jsonb;
  v_selected uuid;
begin
  for r in
    select * from private.daftar_sync_state_snapshots
    where sync_source_id=p_source_id
    order by captured_at desc
  loop
    v_validation:=private.validate_daftar_sync_state_snapshot(r.id);
    if v_validation->>'status'='pass' then
      insert into private.daftar_last_known_good_recovery(
        sync_source_id,snapshot_id,selected_at,captured_at,sequence_no,payload_sha256,chain_sha256,validation
      ) values(
        p_source_id,r.id,now(),r.captured_at,r.sequence_no,r.payload_sha256,r.chain_sha256,v_validation
      )
      on conflict(sync_source_id) do update
      set snapshot_id=excluded.snapshot_id,
          selected_at=excluded.selected_at,
          captured_at=excluded.captured_at,
          sequence_no=excluded.sequence_no,
          payload_sha256=excluded.payload_sha256,
          chain_sha256=excluded.chain_sha256,
          validation=excluded.validation;
      v_selected:=r.id;
      exit;
    end if;
  end loop;

  if v_selected is null then
    return jsonb_build_object('status','missing','source_id',p_source_id);
  end if;
  return jsonb_build_object('status','ready','source_id',p_source_id,'snapshot_id',v_selected,'validation',v_validation);
end;
$$;
revoke all on function private.refresh_daftar_last_known_good_recovery(uuid) from public,anon,authenticated;

create or replace function private.refresh_all_daftar_last_known_good_recovery()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare r record; v jsonb; v_ready int:=0; v_missing int:=0;
begin
  for r in select id from public.daftar_sync_sources where enabled=true or inbound_sync_enabled=true or outbound_sync_enabled=true
  loop
    v:=private.refresh_daftar_last_known_good_recovery(r.id);
    if v->>'status'='ready' then v_ready:=v_ready+1; else v_missing:=v_missing+1; end if;
  end loop;
  return jsonb_build_object('ready',v_ready,'missing',v_missing);
end;
$$;
revoke all on function private.refresh_all_daftar_last_known_good_recovery() from public,anon,authenticated;

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
      v_result:=jsonb_build_object('status','fail','reason','no_snapshot');
    else
      v_result:=private.validate_daftar_sync_state_snapshot(v_snapshot);
    end if;

    insert into private.daftar_restore_drill_state(sync_source_id,snapshot_id,checked_at,status,details)
    values(r.id,v_snapshot,now(),case when v_result->>'status'='pass' then 'pass' else 'fail' end,v_result)
    on conflict(sync_source_id) do update
    set snapshot_id=excluded.snapshot_id,checked_at=excluded.checked_at,status=excluded.status,details=excluded.details;

    perform private.set_daftar_integrity_dead_letter(r.id,'restore_drill_failed',coalesce(v_result->>'status','fail')<>'pass',v_result);

    if v_result->>'status'='pass' then
      perform private.refresh_daftar_last_known_good_recovery(r.id);
      v_pass:=v_pass+1;
    else
      v_fail:=v_fail+1;
    end if;
  end loop;

  return jsonb_build_object('pass',v_pass,'fail',v_fail);
end;
$$;
revoke all on function private.run_daftar_restore_drill() from public,anon,authenticated;
