-- Reduce Daftar mirror pressure after a request storm exhausted Free-plan service quota.
-- Keep the source read-only; only change inbound refresh cadence.

do $runtime$
declare
  v_job_id bigint;
begin
  select jobid into v_job_id
  from cron.job
  where jobname='daftar-sync-multitenant-dispatch'
  limit 1;

  if v_job_id is null then
    perform cron.schedule(
      'daftar-sync-multitenant-dispatch',
      '*/15 * * * *',
      'select private.dispatch_daftar_sync_sources();'
    );
  else
    perform cron.alter_job(
      job_id=>v_job_id,
      schedule=>'*/15 * * * *',
      command=>'select private.dispatch_daftar_sync_sources();',
      active=>true
    );
  end if;
end
$runtime$;
