-- The legacy API has no webhook/event stream, but it supports conditional ETag
-- requests. Poll each minute while transferring the 3.8 MB payload only when
-- its content actually changes.

alter table public.daftar_sync_sources
  add column if not exists contacts_etag text,
  add column if not exists transactions_etag text;

select cron.alter_job(
  (select jobid from cron.job where jobname = 'daftar-live-sync-account-28'),
  schedule => '* * * * *'
);
