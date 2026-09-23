begin;

do $$
declare
  v_source_id uuid;
  v_blocked boolean := false;
  v_rehearsal_def text;
begin
  select id into v_source_id
  from public.daftar_sync_sources
  where legacy_user_id = 28
    and source_fingerprint = 'daftar-live-account-28-v1'
  limit 1;

  if v_source_id is null then
    raise exception 'Daftar account 28 source must exist';
  end if;

  begin
    update public.daftar_sync_sources
    set outbound_sync_enabled = false
    where id = v_source_id;
  exception
    when sqlstate '42501' then
      v_blocked := true;
  end;

  if not v_blocked then
    raise exception 'outbound sync disable must be blocked';
  end if;

  if exists (
    select 1
    from public.daftar_sync_sources
    where id = v_source_id
      and (
        enabled is distinct from true
        or inbound_sync_enabled is distinct from true
        or outbound_sync_enabled is distinct from true
        or outbound_write_contract_status is distinct from 'verified'
      )
  ) then
    raise exception 'permanent bidirectional sync invariant is broken';
  end if;

  select pg_get_functiondef('public.run_daftar_cutover_rehearsal(uuid)'::regprocedure)
    into v_rehearsal_def;

  if position('tombstone.entity_kind = ''debt''' in v_rehearsal_def) = 0
     or position('tombstone.entity_kind = ''payment''' in v_rehearsal_def) = 0
     or position('tombstone.payload_hash = ''__deleted__''' in v_rehearsal_def) = 0 then
    raise exception 'cutover rehearsal must ignore explicit deletion tombstones';
  end if;
end;
$$;

rollback;
