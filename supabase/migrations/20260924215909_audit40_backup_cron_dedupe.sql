-- Mirrors production migration 20260924215909: audit40_backup_cron_dedupe.
-- Remove the superseded Daftar-only backup schedule after the all-tenant job is active.

do $$
begin
  if exists(
    select 1 from cron.job
    where jobname='daily-daftar-tenant-backup-all'
  ) then
    perform cron.unschedule('daily-daftar-tenant-backup-all');
  end if;
end
$$;
