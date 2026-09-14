-- Keep the one-minute Daftar Qarz sync cadence while avoiding a full sync run
-- when both legacy API resources are unchanged. The gateway authenticates with
-- the same Vault-backed trigger secret and only forwards to daftar-sync after
-- an ETag change is detected.

select cron.alter_job(
  (select jobid from cron.job where jobname = 'daftar-live-sync-account-28'),
  schedule => '* * * * *',
  command => $cron$
  select net.http_post(
    url := 'https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/daftar-sync-gateway',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-daftar-sync-secret', (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'daftar_sync_account_28_trigger'
        limit 1
      )
    ),
    body := jsonb_build_object(
      'source_id', (
        select id
        from public.daftar_sync_sources
        where legacy_user_id = 28 and enabled = true
        limit 1
      )
    ),
    timeout_milliseconds := 120000
  );
  $cron$
);
