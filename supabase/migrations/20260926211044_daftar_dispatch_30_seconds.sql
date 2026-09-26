-- Keep the generic Daftar dispatcher at a 30-second cadence.
-- The guardian otherwise restores the previous one-minute schedule on each run.
-- This does not change source mode or outbound write permissions.
do $fix$
declare
  v_def text;
  v_old text := 'schedule=>''* * * * *'',
      command=>''select private.dispatch_daftar_sync_sources();''';
  v_new text := 'schedule=>''30 seconds'',
      command=>''select private.dispatch_daftar_sync_sources();''';
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='guard_daftar_sync_sources';
  if v_def is null then raise exception 'daftar_guardian_missing'; end if;
  if position(v_old in v_def)>0 then
    v_def := replace(v_def,v_old,v_new);
    v_def := replace(v_def,
      '''daftar-sync-multitenant-dispatch'',
      ''* * * * *'',',
      '''daftar-sync-multitenant-dispatch'',
      ''30 seconds'',');
    execute v_def;
  elsif position(v_new in v_def)=0 then
    raise exception 'unexpected_daftar_guardian_definition';
  end if;
  perform cron.alter_job(
    job_id := (select jobid from cron.job
      where jobname='daftar-sync-multitenant-dispatch'),
    schedule := '30 seconds'
  );
end $fix$;
