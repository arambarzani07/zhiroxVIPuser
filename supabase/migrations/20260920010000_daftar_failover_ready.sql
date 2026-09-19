-- Guarded failover readiness for Daftar Qarz account 28.
-- This migration DOES NOT activate ZHIROX primary mode. It only records a
-- last-known-safe cutover point and installs a guarded future switch.

alter table public.daftar_sync_sources
  add column if not exists failover_ready boolean not null default false,
  add column if not exists last_safe_cutover_at timestamptz,
  add column if not exists last_safe_contact_id bigint,
  add column if not exists last_safe_transaction_id bigint,
  add column if not exists last_safe_mirror_contacts bigint,
  add column if not exists last_safe_mirror_transactions bigint,
  add column if not exists primary_activated_at timestamptz;

create table if not exists public.daftar_source_mode_events (
  id bigint generated always as identity primary key,
  sync_source_id uuid not null
    references public.daftar_sync_sources(id) on delete restrict,
  from_mode text not null,
  to_mode text not null,
  reason text not null,
  snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists daftar_source_mode_events_source_time_idx
  on public.daftar_source_mode_events(sync_source_id, created_at desc);

alter table public.daftar_source_mode_events enable row level security;
revoke all on public.daftar_source_mode_events from public, anon, authenticated;
grant all on public.daftar_source_mode_events to service_role;
grant usage, select on sequence public.daftar_source_mode_events_id_seq
  to service_role;

create or replace function public.refresh_daftar_failover_readiness(p_source_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source public.daftar_sync_sources%rowtype;
  v_ready boolean := false;
  v_contacts bigint := 0;
  v_transactions bigint := 0;
begin
  select *
    into v_source
  from public.daftar_sync_sources
  where id = p_source_id
    and legacy_user_id = 28
    and source_fingerprint = 'daftar-live-account-28-v1';

  if v_source.id is null then
    raise exception 'daftar_source_not_available' using errcode = '42501';
  end if;

  select count(*)
    into v_contacts
  from public.daftar_mirror_contacts
  where sync_source_id = v_source.id;

  select count(*)
    into v_transactions
  from public.daftar_mirror_transactions
  where sync_source_id = v_source.id;

  v_ready :=
    v_source.sync_mode = 'mirror'
    and v_source.mirror_bootstrapped_at is not null
    and v_source.reconciliation_status = 'clean'
    and v_source.reconciliation_missing_contacts = 0
    and v_source.reconciliation_missing_transactions = 0
    and v_source.cutover_rehearsal_status = 'pass'
    and v_source.cutover_rehearsal_mismatches = 0
    and v_contacts > 0
    and v_transactions > 0;

  update public.daftar_sync_sources
  set failover_ready = v_ready,
      last_safe_cutover_at = case when v_ready then now() else last_safe_cutover_at end,
      last_safe_contact_id = case when v_ready then last_contact_id else last_safe_contact_id end,
      last_safe_transaction_id = case when v_ready then last_transaction_id else last_safe_transaction_id end,
      last_safe_mirror_contacts = case when v_ready then v_contacts else last_safe_mirror_contacts end,
      last_safe_mirror_transactions = case when v_ready then v_transactions else last_safe_mirror_transactions end,
      updated_at = now()
  where id = v_source.id;

  return jsonb_build_object(
    'failover_ready', v_ready,
    'contacts', v_contacts,
    'transactions', v_transactions,
    'last_contact_id', v_source.last_contact_id,
    'last_transaction_id', v_source.last_transaction_id
  );
end;
$$;

revoke all on function public.refresh_daftar_failover_readiness(uuid)
  from public, anon, authenticated;
grant execute on function public.refresh_daftar_failover_readiness(uuid)
  to service_role;


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
      if new.sync_mode is distinct from 'zhirox_primary'
         or new.enabled is distinct from false then
        raise exception 'daftar_sync_primary_mode_locked' using errcode = '42501';
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

  select s.id, s.sync_mode
    into v_source_id, v_mode
  from public.daftar_sync_sources s
  where s.legacy_user_id = 28
    and s.source_fingerprint = 'daftar-live-account-28-v1'
  order by s.created_at
  limit 1;

  if v_source_id is null then
    raise exception 'daftar_sync_account_28_source_missing';
  end if;

  select jobid into v_live_job_id
  from cron.job
  where jobname = 'daftar-live-sync-account-28'
  limit 1;

  if v_mode = 'zhirox_primary' then
    update public.daftar_sync_sources
    set enabled = false,
        updated_at = now()
    where id = v_source_id;

    if v_live_job_id is not null then
      perform cron.alter_job(
        job_id => v_live_job_id,
        active => false
      );
    end if;
  elsif v_mode = 'mirror' then
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
end;
$$;

revoke all on function public.guard_daftar_sync_account_28()
  from public, anon, authenticated;
grant execute on function public.guard_daftar_sync_account_28()
  to service_role;


create or replace function public.activate_zhirox_primary(
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
  v_live_job_id bigint;
begin
  if p_confirmation is distinct from 'ACTIVATE_ZHIROX_PRIMARY_ACCOUNT_28' then
    raise exception 'invalid_cutover_confirmation' using errcode = '42501';
  end if;

  select *
    into v_source
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
      'activated_at', v_source.primary_activated_at
    );
  end if;

  if v_source.health_status = 'healthy' then
    raise exception 'daftar_source_still_healthy' using errcode = '42501';
  end if;

  if not v_source.failover_ready
     or v_source.last_safe_cutover_at is null
     or v_source.reconciliation_status <> 'clean'
     or v_source.reconciliation_missing_contacts <> 0
     or v_source.reconciliation_missing_transactions <> 0
     or v_source.cutover_rehearsal_status <> 'pass'
     or v_source.cutover_rehearsal_mismatches <> 0 then
    raise exception 'daftar_failover_not_ready' using errcode = '42501';
  end if;

  perform set_config('zhirox.daftar_sync_unlock', 'on', true);

  update public.daftar_sync_sources
  set sync_mode = 'zhirox_primary',
      enabled = false,
      primary_activated_at = now(),
      updated_at = now()
  where id = v_source.id;

  select jobid into v_live_job_id
  from cron.job
  where jobname = 'daftar-live-sync-account-28'
  limit 1;

  if v_live_job_id is not null then
    perform cron.alter_job(
      job_id => v_live_job_id,
      active => false
    );
  end if;

  insert into public.daftar_source_mode_events(
    sync_source_id,
    from_mode,
    to_mode,
    reason,
    snapshot
  ) values (
    v_source.id,
    'mirror',
    'zhirox_primary',
    'confirmed_failover_after_source_unavailable',
    jsonb_build_object(
      'last_safe_cutover_at', v_source.last_safe_cutover_at,
      'last_safe_contact_id', v_source.last_safe_contact_id,
      'last_safe_transaction_id', v_source.last_safe_transaction_id,
      'last_safe_mirror_contacts', v_source.last_safe_mirror_contacts,
      'last_safe_mirror_transactions', v_source.last_safe_mirror_transactions,
      'health_status', v_source.health_status,
      'consecutive_failures', v_source.consecutive_failures
    )
  );

  return jsonb_build_object(
    'activated', true,
    'already_primary', false,
    'previous_mode', 'mirror',
    'new_mode', 'zhirox_primary'
  );
end;
$$;

revoke all on function public.activate_zhirox_primary(uuid,text)
  from public, anon, authenticated;
grant execute on function public.activate_zhirox_primary(uuid,text)
  to service_role;


create or replace function public.get_my_daftar_mirror_status()
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_build_object(
      'sync_mode', s.sync_mode,
      'mirror_bootstrapped_at', s.mirror_bootstrapped_at,
      'mirror_last_full_at', s.mirror_last_full_at,
      'contacts_count', (
        select count(*)
        from public.daftar_mirror_contacts c
        where c.sync_source_id = s.id
      ),
      'transactions_count', (
        select count(*)
        from public.daftar_mirror_transactions t
        where t.sync_source_id = s.id
      ),
      'last_success_at', s.last_success_at,
      'health_status', s.health_status,
      'consecutive_failures', s.consecutive_failures,
      'reconciliation_status', s.reconciliation_status,
      'reconciliation_missing_contacts', s.reconciliation_missing_contacts,
      'reconciliation_missing_transactions', s.reconciliation_missing_transactions,
      'last_reconciled_at', s.last_reconciled_at,
      'cutover_rehearsal_status', s.cutover_rehearsal_status,
      'cutover_rehearsal_mismatches', s.cutover_rehearsal_mismatches,
      'last_cutover_rehearsal_at', s.last_cutover_rehearsal_at,
      'failover_ready', s.failover_ready,
      'last_safe_cutover_at', s.last_safe_cutover_at,
      'last_safe_contact_id', s.last_safe_contact_id,
      'last_safe_transaction_id', s.last_safe_transaction_id,
      'last_safe_mirror_contacts', s.last_safe_mirror_contacts,
      'last_safe_mirror_transactions', s.last_safe_mirror_transactions,
      'primary_activated_at', s.primary_activated_at,
      'cutover_ready',
        s.sync_mode = 'mirror'
        and s.mirror_bootstrapped_at is not null
        and s.health_status = 'healthy'
        and s.consecutive_failures = 0
        and s.reconciliation_status = 'clean'
        and s.reconciliation_missing_contacts = 0
        and s.reconciliation_missing_transactions = 0
        and s.cutover_rehearsal_status = 'pass'
        and s.cutover_rehearsal_mismatches = 0
        and s.last_success_at is not null
        and s.last_success_at >= now() - interval '5 minutes'
    ),
    '{}'::jsonb
  )
  from public.daftar_sync_sources s
  where (select auth.uid()) is not null
    and s.admin_id = (select auth.uid())
    and s.legacy_user_id = 28
    and s.source_fingerprint = 'daftar-live-account-28-v1'
  order by s.created_at
  limit 1;
$$;

revoke all on function public.get_my_daftar_mirror_status()
  from public, anon;
grant execute on function public.get_my_daftar_mirror_status()
  to authenticated;


do $$
declare
  v_source_id uuid;
begin
  select id into v_source_id
  from public.daftar_sync_sources
  where legacy_user_id = 28
    and source_fingerprint = 'daftar-live-account-28-v1'
  limit 1;

  if v_source_id is not null then
    perform public.refresh_daftar_failover_readiness(v_source_id);
  end if;
end;
$$;
