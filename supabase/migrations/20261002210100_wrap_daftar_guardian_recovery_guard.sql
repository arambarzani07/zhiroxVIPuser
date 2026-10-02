-- Wrap the existing Daftar guardian so restore-drill and break-glass cleanup are guarded too.

do $$
begin
  if exists(
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname='guard_daftar_sync_sources'
  ) and not exists(
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname='guard_daftar_sync_sources_core'
  ) then
    alter function private.guard_daftar_sync_sources() rename to guard_daftar_sync_sources_core;
  end if;
end $$;

create or replace function private.expire_daftar_break_glass_authorizations()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare r record; v_count integer:=0;
begin
  for r in
    select * from private.daftar_break_glass_authorizations
    where consumed_at is null and revoked_at is null and expires_at<=now()
    for update skip locked
  loop
    update private.daftar_break_glass_authorizations set revoked_at=now() where id=r.id;
    perform private.append_daftar_recovery_audit(
      r.sync_source_id,'authorization_expired',r.actor_id,r.snapshot_id,r.reason,
      jsonb_build_object('authorization_id',r.id,'issued_at',r.issued_at,'expired_at',r.expires_at)
    );
    v_count:=v_count+1;
  end loop;
  return jsonb_build_object('expired_authorizations',v_count);
end;
$$;
revoke all on function private.expire_daftar_break_glass_authorizations() from public,anon,authenticated;

create or replace function private.guard_daftar_sync_runtime_extensions()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_restore jsonb; v_expired jsonb;
begin
  v_restore:=private.guard_daftar_restore_drill_runtime();
  v_expired:=private.expire_daftar_break_glass_authorizations();
  return jsonb_build_object('restore_drill',v_restore,'break_glass',v_expired,'runtime_jobs',8);
end;
$$;
revoke all on function private.guard_daftar_sync_runtime_extensions() from public,anon,authenticated;

create or replace function private.guard_daftar_sync_sources()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_core jsonb; v_ext jsonb;
begin
  v_core:=private.guard_daftar_sync_sources_core();
  v_ext:=private.guard_daftar_sync_runtime_extensions();
  return (coalesce(v_core,'{}'::jsonb)-'runtime_jobs') || jsonb_build_object(
    'runtime_jobs',8,
    'recovery_guard',v_ext
  );
end;
$$;
revoke all on function private.guard_daftar_sync_sources() from public,anon,authenticated;
