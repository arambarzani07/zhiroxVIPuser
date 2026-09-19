-- Permanent connection lock for Daftar Qarz account 28 -> ZHIROX.
-- Critical identity/secret/cron fields are protected from accidental system changes.
-- Intentional maintenance requires an explicit migration and must preserve this contract.

create or replace function public.prevent_daftar_sync_account_28_breakage()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_guardian boolean := coalesce(current_setting('zhirox.daftar_sync_guardian', true), '') = 'on';
  v_unlock boolean := coalesce(current_setting('zhirox.daftar_sync_unlock', true), '') = 'on';
begin
  if v_unlock or v_guardian then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    if old.legacy_user_id = 28
       and old.source_fingerprint = 'daftar-live-account-28-v1' then
      raise exception 'daftar_sync_account_28_locked' using errcode = '42501';
    end if;
    return old;
  end if;

  if old.legacy_user_id = 28
     and old.source_fingerprint = 'daftar-live-account-28-v1' then
    if new.id is distinct from old.id
       or new.admin_id is distinct from old.admin_id
       or new.legacy_user_id is distinct from 28
       or new.source_name is distinct from 'Daftar Qarz / account 28'
       or new.source_fingerprint is distinct from 'daftar-live-account-28-v1'
       or new.api_base_url is distinct from 'https://api-daftar-qarz.kasbkar.net/api/v1'
       or new.trigger_secret_hash is distinct from old.trigger_secret_hash
       or new.enabled is distinct from true then
      raise exception 'daftar_sync_account_28_locked' using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.prevent_daftar_sync_account_28_breakage()
  from public, anon, authenticated;

drop trigger if exists zhirox_protect_daftar_sync_account_28
  on public.daftar_sync_sources;
create trigger zhirox_protect_daftar_sync_account_28
before update or delete on public.daftar_sync_sources
for each row execute function public.prevent_daftar_sync_account_28_breakage();


-- Supabase owns vault.secrets and cron.job, so application migrations cannot
-- install triggers on those managed tables. The guardian below continuously
-- verifies the Vault-backed hash and restores the canonical cron definition.
-- CI separately rejects destructive repository changes to this connection.

create or replace function public.guard_daftar_sync_account_28()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source_id uuid;
  v_secret text;
  v_secret_hash text;
  v_live_job_id bigint;
  v_guardian_job_id bigint;
  v_live_command text := $cmd$
    select net.http_post(
      url := 'https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/daftar-sync-gateway',
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
            and enabled = true
          limit 1
        )
      ),
      timeout_milliseconds := 120000
    );
  $cmd$;
begin
  perform set_config('zhirox.daftar_sync_guardian', 'on', true);

  select s.id into v_source_id
  from public.daftar_sync_sources s
  where s.legacy_user_id = 28
    and s.source_fingerprint = 'daftar-live-account-28-v1'
  order by s.created_at
  limit 1;

  if v_source_id is null then
    raise exception 'daftar_sync_account_28_source_missing';
  end if;

  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'daftar_sync_account_28_trigger'
  limit 1;

  if v_secret is null or length(v_secret) < 32 then
    raise exception 'daftar_sync_account_28_secret_missing';
  end if;

  v_secret_hash := encode(extensions.digest(v_secret, 'sha256'), 'hex');

  update public.daftar_sync_sources
  set source_name = 'Daftar Qarz / account 28',
      source_fingerprint = 'daftar-live-account-28-v1',
      api_base_url = 'https://api-daftar-qarz.kasbkar.net/api/v1',
      trigger_secret_hash = v_secret_hash,
      enabled = true,
      updated_at = now()
  where id = v_source_id;

  select jobid into v_live_job_id
  from cron.job
  where jobname = 'daftar-live-sync-account-28'
  limit 1;

  if v_live_job_id is null then
    perform cron.schedule(
      'daftar-live-sync-account-28',
      '* * * * *',
      v_live_command
    );
  else
    perform cron.alter_job(
      job_id => v_live_job_id,
      schedule => '* * * * *',
      command => v_live_command,
      active => true
    );
  end if;

  select jobid into v_guardian_job_id
  from cron.job
  where jobname = 'daftar-sync-guardian-account-28'
  limit 1;

  if v_guardian_job_id is not null then
    perform cron.alter_job(
      job_id => v_guardian_job_id,
      schedule => '* * * * *',
      command => 'select public.guard_daftar_sync_account_28();',
      active => true
    );
  end if;
end;
$$;

revoke all on function public.guard_daftar_sync_account_28()
  from public, anon, authenticated;
grant execute on function public.guard_daftar_sync_account_28() to service_role;

select cron.schedule(
  'daftar-sync-guardian-account-28',
  '* * * * *',
  'select public.guard_daftar_sync_account_28();'
);

select public.guard_daftar_sync_account_28();
