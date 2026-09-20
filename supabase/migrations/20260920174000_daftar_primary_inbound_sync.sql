-- Keep ZHIROX as the source of truth while continuing one-way inbound
-- ingestion of newly-added Daftar Qarz account-28 data.
--
-- sync_mode='zhirox_primary' controls source-of-truth semantics.
-- enabled/inbound_sync_enabled control only the inbound transport.

alter table public.daftar_sync_sources
  add column if not exists inbound_sync_enabled boolean not null default false;

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
       or new.trigger_secret_hash is distinct from old.trigger_secret_hash then
      raise exception 'daftar_sync_account_28_locked' using errcode = '42501';
    end if;

    if old.sync_mode = 'mirror' then
      if new.sync_mode is distinct from 'mirror'
         or new.enabled is distinct from true then
        raise exception 'daftar_sync_mirror_mode_locked' using errcode = '42501';
      end if;
    elsif old.sync_mode = 'zhirox_primary' then
      if new.sync_mode is distinct from 'zhirox_primary' then
        raise exception 'daftar_sync_primary_mode_locked' using errcode = '42501';
      end if;
      if new.enabled is distinct from new.inbound_sync_enabled then
        raise exception 'daftar_primary_inbound_transport_mismatch' using errcode = '42501';
      end if;
    else
      raise exception 'daftar_sync_unknown_mode_locked' using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.prevent_daftar_sync_account_28_breakage()
  from public, anon, authenticated;

create or replace function public.guard_daftar_sync_account_28()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source_id uuid;
  v_mode text;
  v_inbound boolean;
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
            and (
              enabled = true
              or inbound_sync_enabled = true
            )
          limit 1
        )
      ),
      timeout_milliseconds := 120000
    );
  $cmd$;
begin
  perform set_config('zhirox.daftar_sync_guardian', 'on', true);

  select s.id, s.sync_mode, s.inbound_sync_enabled
    into v_source_id, v_mode, v_inbound
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
      enabled = case
        when v_mode = 'mirror' then true
        when v_mode = 'zhirox_primary' then coalesce(v_inbound, false)
        else enabled
      end,
      updated_at = now()
  where id = v_source_id;

  select jobid into v_live_job_id
  from cron.job
  where jobname = 'daftar-live-sync-account-28'
  limit 1;

  if v_mode = 'mirror'
     or (v_mode = 'zhirox_primary' and coalesce(v_inbound, false)) then
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
  elsif v_mode = 'zhirox_primary' then
    if v_live_job_id is not null then
      perform cron.alter_job(job_id => v_live_job_id, active => false);
    end if;
  else
    raise exception 'daftar_sync_unknown_mode';
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

  perform public.qualify_daftar_outage(v_source_id);
end;
$$;

revoke all on function public.guard_daftar_sync_account_28()
  from public, anon, authenticated;
grant execute on function public.guard_daftar_sync_account_28()
  to service_role;

create or replace function public.activate_zhirox_primary_planned(
  p_source_id uuid,
  p_confirmation text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source public.daftar_sync_sources%rowtype;
begin
  if p_confirmation is distinct from 'PLANNED_ACTIVATE_ZHIROX_PRIMARY_ACCOUNT_28' then
    raise exception 'invalid_planned_cutover_confirmation' using errcode = '42501';
  end if;

  select * into v_source
  from public.daftar_sync_sources
  where id = p_source_id
    and legacy_user_id = 28
    and source_fingerprint = 'daftar-live-account-28-v1'
  for update;

  if v_source.id is null then
    raise exception 'daftar_source_not_available' using errcode = '42501';
  end if;

  if v_source.sync_mode = 'zhirox_primary' then
    return jsonb_build_object(
      'activated', true,
      'already_primary', true,
      'inbound_sync_enabled', v_source.inbound_sync_enabled,
      'activated_at', v_source.primary_activated_at
    );
  end if;

  if v_source.sync_mode <> 'mirror'
     or v_source.enabled is distinct from true
     or v_source.health_status <> 'healthy'
     or v_source.consecutive_failures <> 0
     or v_source.outage_status <> 'healthy'
     or v_source.last_success_at is null
     or v_source.last_success_at < now() - interval '5 minutes' then
    raise exception 'daftar_planned_cutover_not_safe' using errcode = '42501';
  end if;

  perform public.run_daftar_cutover_rehearsal(v_source.id);
  perform public.refresh_daftar_failover_readiness(v_source.id);

  select * into v_source
  from public.daftar_sync_sources
  where id = p_source_id
  for update;

  if not v_source.failover_ready
     or v_source.last_safe_cutover_at is null
     or v_source.reconciliation_status <> 'clean'
     or v_source.reconciliation_missing_contacts <> 0
     or v_source.reconciliation_missing_transactions <> 0
     or v_source.cutover_rehearsal_status <> 'pass'
     or v_source.cutover_rehearsal_mismatches <> 0 then
    raise exception 'daftar_planned_cutover_not_ready' using errcode = '42501';
  end if;

  perform set_config('zhirox.daftar_sync_unlock', 'on', true);

  update public.daftar_sync_sources
  set sync_mode = 'zhirox_primary',
      inbound_sync_enabled = true,
      enabled = true,
      live_read_mode = 'off',
      primary_activated_at = now(),
      updated_at = now()
  where id = v_source.id;

  insert into public.daftar_source_mode_events(
    sync_source_id, from_mode, to_mode, reason, snapshot
  ) values (
    v_source.id,
    'mirror',
    'zhirox_primary',
    'planned_primary_cutover_while_source_healthy',
    jsonb_build_object(
      'inbound_sync_enabled', true,
      'last_safe_cutover_at', v_source.last_safe_cutover_at,
      'last_safe_contact_id', v_source.last_safe_contact_id,
      'last_safe_transaction_id', v_source.last_safe_transaction_id,
      'last_safe_mirror_contacts', v_source.last_safe_mirror_contacts,
      'last_safe_mirror_transactions', v_source.last_safe_mirror_transactions,
      'health_status', v_source.health_status,
      'last_success_at', v_source.last_success_at
    )
  );

  perform public.guard_daftar_sync_account_28();

  return jsonb_build_object(
    'activated', true,
    'already_primary', false,
    'previous_mode', 'mirror',
    'new_mode', 'zhirox_primary',
    'planned', true,
    'inbound_sync_enabled', true
  );
end;
$$;

revoke all on function public.activate_zhirox_primary_planned(uuid,text)
  from public, anon, authenticated;
grant execute on function public.activate_zhirox_primary_planned(uuid,text)
  to service_role;

-- Enable the requested one-way inbound transport for the already-cut-over source.
do $$
declare
  v_source_id uuid;
begin
  select id into v_source_id
  from public.daftar_sync_sources
  where legacy_user_id = 28
    and source_fingerprint = 'daftar-live-account-28-v1'
    and sync_mode = 'zhirox_primary'
  limit 1;

  if v_source_id is not null then
    perform set_config('zhirox.daftar_sync_unlock', 'on', true);
    update public.daftar_sync_sources
    set inbound_sync_enabled = true,
        enabled = true,
        updated_at = now()
    where id = v_source_id;
    perform public.guard_daftar_sync_account_28();
  end if;
end;
$$;
