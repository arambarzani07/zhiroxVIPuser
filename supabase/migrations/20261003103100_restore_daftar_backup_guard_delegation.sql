-- Restore explicit delegation from the Daftar guardian to the canonical backup runtime guard.
-- This keeps the recovery wrapper introduced on 2026-10-02 while preserving the
-- backup scheduling contract expected by Audit40.

create or replace function private.guard_daftar_sync_sources()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_core jsonb;
  v_ext jsonb;
  v_backup jsonb;
begin
  v_core := private.guard_daftar_sync_sources_core();
  v_ext := private.guard_daftar_sync_runtime_extensions();
  v_backup := private.guard_backup_runtime();

  return (coalesce(v_core,'{}'::jsonb)-'runtime_jobs') || jsonb_build_object(
    'runtime_jobs', 8,
    'recovery_guard', v_ext,
    'backup_guard', v_backup
  );
end;
$$;

revoke all on function private.guard_daftar_sync_sources() from public, anon, authenticated;
