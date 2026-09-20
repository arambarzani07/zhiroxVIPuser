-- Activate future-create ZHIROX -> Daftar Qarz one-way outbound sync.
-- Safety gates:
--   * ZHIROX remains primary.
--   * Existing Daftar -> ZHIROX inbound sync remains active.
--   * No historical backfill is enqueued.
--   * Only records inserted after activation are queued by triggers.
--   * The verified API contract is contacts/transactions POST.

create or replace function public.guard_daftar_outbound_account_28()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source_id uuid;
  v_should_run boolean;
  v_job_id bigint;
  v_command text := $cmd$
    select net.http_post(
      url := 'https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/daftar-outbound-sync',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-daftar-sync-secret', (
          select decrypted_secret from vault.decrypted_secrets
          where name = 'daftar_sync_account_28_trigger' limit 1
        )
      ),
      body := jsonb_build_object(
        'source_id', (
          select id from public.daftar_sync_sources
          where legacy_user_id = 28
            and source_fingerprint = 'daftar-live-account-28-v1'
            and sync_mode = 'zhirox_primary'
          limit 1
        ),
        'action', 'drain'
      ),
      timeout_milliseconds := 120000
    );
  $cmd$;
begin
  select s.id,
         (
           s.sync_mode = 'zhirox_primary'
           and s.outbound_sync_enabled = true
           and s.outbound_write_contract_status = 'verified'
         )
    into v_source_id, v_should_run
  from public.daftar_sync_sources s
  where s.legacy_user_id = 28
    and s.source_fingerprint = 'daftar-live-account-28-v1'
  limit 1;

  if v_source_id is null then
    raise exception 'daftar_sync_account_28_source_missing';
  end if;

  select jobid into v_job_id
  from cron.job
  where jobname = 'daftar-outbound-sync-account-28'
  limit 1;

  if v_should_run then
    if v_job_id is null then
      perform cron.schedule(
        'daftar-outbound-sync-account-28',
        '* * * * *',
        v_command
      );
    else
      perform cron.alter_job(
        job_id => v_job_id,
        schedule => '* * * * *',
        command => v_command,
        active => true
      );
    end if;
  elsif v_job_id is not null then
    perform cron.alter_job(job_id => v_job_id, active => false);
  end if;
end;
$$;

revoke all on function public.guard_daftar_outbound_account_28()
  from public, anon, authenticated;
grant execute on function public.guard_daftar_outbound_account_28()
  to service_role;

do $$
declare
  v_source_id uuid;
begin
  select id into v_source_id
  from public.daftar_sync_sources
  where legacy_user_id = 28
    and source_fingerprint = 'daftar-live-account-28-v1'
    and sync_mode = 'zhirox_primary'
    and inbound_sync_enabled = true
    and health_status = 'healthy'
    and consecutive_failures = 0
    and reconciliation_status = 'clean'
    and reconciliation_missing_contacts = 0
    and reconciliation_missing_transactions = 0
  limit 1;

  if v_source_id is null then
    raise exception 'daftar_outbound_activation_safety_gate_failed';
  end if;

  update public.daftar_sync_sources
  set outbound_write_contract_status = 'verified',
      outbound_sync_enabled = true,
      updated_at = now()
  where id = v_source_id;

  perform public.guard_daftar_outbound_account_28();
end;
$$;
