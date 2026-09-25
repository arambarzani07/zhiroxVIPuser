-- The legacy API has no webhook/event stream, but it supports conditional ETag
-- requests. Poll each minute while transferring the 3.8 MB payload only when
-- its content actually changes.

alter table public.daftar_sync_sources
  add column if not exists contacts_etag text,
  add column if not exists transactions_etag text;

do $near_live$
declare
  v_job_id bigint;
begin
  select jobid into v_job_id
  from cron.job
  where jobname = 'daftar-live-sync-account-28'
  limit 1;

  if v_job_id is not null then
    perform cron.alter_job(
      v_job_id,
      schedule => '* * * * *'
    );
  else
    raise notice 'Daftar live sync cron is absent; skipping near-live schedule update on fresh install';
  end if;
end
$near_live$;