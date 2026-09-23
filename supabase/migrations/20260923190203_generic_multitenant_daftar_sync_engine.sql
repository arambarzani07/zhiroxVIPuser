-- Finalize the generic multi-tenant Daftar sync engine.
-- Production migration version: 20260923190203.
-- Removes the account-28 scheduling exception while preserving the permanent
-- bidirectional lock semantics for every enabled sync source.

create or replace function private.prevent_daftar_sync_source_breakage()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_guardian boolean :=
    coalesce(current_setting('zhirox.daftar_sync_guardian', true), '') = 'on';
  v_unlock boolean :=
    coalesce(current_setting('zhirox.daftar_sync_unlock', true), '') = 'on';
  v_protected boolean;
begin
  if v_unlock or v_guardian then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  v_protected :=
    coalesce(old.enabled, false)
    and old.sync_mode in ('mirror', 'zhirox_primary');

  if tg_op = 'DELETE' then
    if v_protected then
      raise exception 'daftar_sync_source_locked' using errcode = '42501';
    end if;
    return old;
  end if;

  if not v_protected then
    return new;
  end if;

  if new.id is distinct from old.id
     or new.admin_id is distinct from old.admin_id
     or new.legacy_user_id is distinct from old.legacy_user_id
     or new.source_fingerprint is distinct from old.source_fingerprint
     or new.api_base_url is distinct from old.api_base_url
     or new.trigger_secret_hash is distinct from old.trigger_secret_hash
     or new.trigger_secret_vault_name is distinct from old.trigger_secret_vault_name then
    raise exception 'daftar_sync_source_identity_locked' using errcode = '42501';
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

    if new.enabled is distinct from true
       or new.inbound_sync_enabled is distinct from true
       or new.outbound_sync_enabled is distinct from true then
      raise exception 'daftar_bidirectional_sync_must_remain_enabled'
        using errcode = '42501';
    end if;

    if new.outbound_write_contract_status is distinct from 'verified' then
      raise exception 'daftar_outbound_write_contract_must_remain_verified'
        using errcode = '42501';
    end if;
  else
    raise exception 'daftar_sync_unknown_mode_locked' using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function private.prevent_daftar_sync_source_breakage()
  from public, anon, authenticated;

drop trigger if exists zhirox_protect_daftar_sync_account_28
  on public.daftar_sync_sources;
drop trigger if exists zhirox_protect_daftar_sync_sources
  on public.daftar_sync_sources;

create trigger zhirox_protect_daftar_sync_sources
before delete or update on public.daftar_sync_sources
for each row
execute function private.prevent_daftar_sync_source_breakage();

create or replace function private.dispatch_daftar_sync_sources()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  r record;
  v_secret text;
  v_inbound_count integer := 0;
  v_outbound_count integer := 0;
  v_skipped_count integer := 0;
begin
  for r in
    select
      s.id,
      s.trigger_secret_hash,
      s.trigger_secret_vault_name,
      s.sync_mode,
      s.inbound_sync_enabled,
      s.outbound_sync_enabled,
      s.outbound_write_contract_status
    from public.daftar_sync_sources s
    where s.enabled = true
      and nullif(s.trigger_secret_vault_name, '') is not null
    order by s.created_at, s.id
  loop
    v_secret := null;

    select decrypted_secret into v_secret
    from vault.decrypted_secrets
    where name = r.trigger_secret_vault_name
    limit 1;

    if v_secret is null
       or encode(extensions.digest(v_secret, 'sha256'), 'hex')
          is distinct from r.trigger_secret_hash then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    if r.sync_mode = 'mirror'
       or (r.sync_mode = 'zhirox_primary' and r.inbound_sync_enabled = true) then
      perform net.http_post(
        url := 'https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/daftar-sync-gateway',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-daftar-sync-secret', v_secret
        ),
        body := jsonb_build_object('source_id', r.id),
        timeout_milliseconds := 120000
      );
      v_inbound_count := v_inbound_count + 1;
    end if;

    if r.sync_mode = 'zhirox_primary'
       and r.outbound_sync_enabled = true
       and r.outbound_write_contract_status = 'verified' then
      perform net.http_post(
        url := 'https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/daftar-outbound-sync',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-daftar-sync-secret', v_secret
        ),
        body := jsonb_build_object('source_id', r.id, 'action', 'drain'),
        timeout_milliseconds := 120000
      );
      v_outbound_count := v_outbound_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'inbound_dispatched', v_inbound_count,
    'outbound_dispatched', v_outbound_count,
    'skipped_missing_or_invalid_secret', v_skipped_count
  );
end;
$$;

revoke all on function private.dispatch_daftar_sync_sources()
  from public, anon, authenticated;

create or replace function private.reconcile_daftar_sync_sources()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  r record;
  v_result jsonb;
  v_healthy integer := 0;
  v_unhealthy integer := 0;
  v_failed integer := 0;
begin
  for r in
    select s.id
    from public.daftar_sync_sources s
    where s.enabled = true
    order by s.created_at, s.id
  loop
    begin
      v_result := private.run_daftar_sync_reconciliation(r.id);
      if coalesce(v_result->>'status', '') = 'healthy' then
        v_healthy := v_healthy + 1;
      else
        v_unhealthy := v_unhealthy + 1;
      end if;
    exception when others then
      v_failed := v_failed + 1;
    end;
  end loop;

  return jsonb_build_object(
    'healthy', v_healthy,
    'unhealthy', v_unhealthy,
    'failed', v_failed
  );
end;
$$;

revoke all on function private.reconcile_daftar_sync_sources()
  from public, anon, authenticated;

create or replace function private.guard_daftar_sync_sources()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  r record;
  v_secret text;
  v_valid integer := 0;
  v_invalid integer := 0;
  v_dispatch_job_id bigint;
  v_reconcile_job_id bigint;
  v_guard_job_id bigint;
begin
  perform set_config('zhirox.daftar_sync_guardian', 'on', true);

  for r in
    select s.id, s.trigger_secret_hash, s.trigger_secret_vault_name
    from public.daftar_sync_sources s
    where s.enabled = true
    order by s.created_at, s.id
  loop
    v_secret := null;

    if nullif(r.trigger_secret_vault_name, '') is not null then
      select decrypted_secret into v_secret
      from vault.decrypted_secrets
      where name = r.trigger_secret_vault_name
      limit 1;
    end if;

    if v_secret is null
       or encode(extensions.digest(v_secret, 'sha256'), 'hex')
          is distinct from r.trigger_secret_hash then
      v_invalid := v_invalid + 1;
      update public.daftar_sync_sources
      set health_status = 'unhealthy',
          last_status = 'error',
          last_error = 'trigger_secret_missing_or_invalid',
          updated_at = now()
      where id = r.id;
    else
      v_valid := v_valid + 1;
    end if;

    perform public.qualify_daftar_outage(r.id);
  end loop;

  select jobid into v_dispatch_job_id
  from cron.job
  where jobname = 'daftar-sync-multitenant-dispatch'
  limit 1;

  if v_dispatch_job_id is null then
    perform cron.schedule(
      'daftar-sync-multitenant-dispatch',
      '* * * * *',
      'select private.dispatch_daftar_sync_sources();'
    );
  else
    perform cron.alter_job(
      job_id => v_dispatch_job_id,
      schedule => '* * * * *',
      command => 'select private.dispatch_daftar_sync_sources();',
      active => true
    );
  end if;

  select jobid into v_reconcile_job_id
  from cron.job
  where jobname = 'daftar-sync-multitenant-reconcile'
  limit 1;

  if v_reconcile_job_id is null then
    perform cron.schedule(
      'daftar-sync-multitenant-reconcile',
      '17 * * * *',
      'select private.reconcile_daftar_sync_sources();'
    );
  else
    perform cron.alter_job(
      job_id => v_reconcile_job_id,
      schedule => '17 * * * *',
      command => 'select private.reconcile_daftar_sync_sources();',
      active => true
    );
  end if;

  select jobid into v_guard_job_id
  from cron.job
  where jobname = 'daftar-sync-multitenant-guardian'
  limit 1;

  if v_guard_job_id is not null then
    perform cron.alter_job(
      job_id => v_guard_job_id,
      schedule => '* * * * *',
      command => 'select private.guard_daftar_sync_sources();',
      active => true
    );
  end if;

  return jsonb_build_object(
    'valid_sources', v_valid,
    'invalid_sources', v_invalid
  );
end;
$$;

revoke all on function private.guard_daftar_sync_sources()
  from public, anon, authenticated;

do $$
declare
  v_id bigint;
begin
  select jobid into v_id from cron.job
  where jobname = 'daftar-sync-multitenant-dispatch' limit 1;
  if v_id is null then
    perform cron.schedule(
      'daftar-sync-multitenant-dispatch',
      '* * * * *',
      'select private.dispatch_daftar_sync_sources();'
    );
  else
    perform cron.alter_job(
      job_id => v_id,
      schedule => '* * * * *',
      command => 'select private.dispatch_daftar_sync_sources();',
      active => true
    );
  end if;

  select jobid into v_id from cron.job
  where jobname = 'daftar-sync-multitenant-reconcile' limit 1;
  if v_id is null then
    perform cron.schedule(
      'daftar-sync-multitenant-reconcile',
      '17 * * * *',
      'select private.reconcile_daftar_sync_sources();'
    );
  else
    perform cron.alter_job(
      job_id => v_id,
      schedule => '17 * * * *',
      command => 'select private.reconcile_daftar_sync_sources();',
      active => true
    );
  end if;

  select jobid into v_id from cron.job
  where jobname = 'daftar-sync-multitenant-guardian' limit 1;
  if v_id is null then
    perform cron.schedule(
      'daftar-sync-multitenant-guardian',
      '* * * * *',
      'select private.guard_daftar_sync_sources();'
    );
  else
    perform cron.alter_job(
      job_id => v_id,
      schedule => '* * * * *',
      command => 'select private.guard_daftar_sync_sources();',
      active => true
    );
  end if;

  for v_id in
    select jobid from cron.job
    where jobname in (
      'daftar-live-sync-account-28',
      'daftar-outbound-sync-account-28',
      'daftar-sync-guardian-account-28',
      'daftar-sync-reconcile-account-28'
    )
  loop
    perform cron.alter_job(job_id => v_id, active => false);
  end loop;
end;
$$;

revoke all on function public.guard_daftar_sync_account_28()
  from public, anon, authenticated;
revoke all on function public.prevent_daftar_sync_account_28_breakage()
  from public, anon, authenticated;
