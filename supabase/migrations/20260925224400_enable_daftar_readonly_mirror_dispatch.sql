-- Keep Daftar -> ZHIROX mirror refresh active every minute.
-- In mirror mode private.dispatch_daftar_sync_sources() dispatches inbound only;
-- it does not call daftar-outbound-sync.

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
      '* * * * *',
      'select private.dispatch_daftar_sync_sources();'
    );
  else
    perform cron.alter_job(
      job_id=>v_job_id,
      schedule=>'* * * * *',
      command=>'select private.dispatch_daftar_sync_sources();',
      active=>true
    );
  end if;
end
$runtime$;
