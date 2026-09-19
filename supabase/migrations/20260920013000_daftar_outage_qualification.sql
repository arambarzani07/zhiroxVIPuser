-- Qualify sustained Daftar Qarz outages before allowing failover.
-- A transient API/network error is never sufficient to activate ZHIROX primary.

alter table public.daftar_sync_sources
  add column if not exists outage_status text not null default 'healthy',
  add column if not exists outage_suspected_at timestamptz,
  add column if not exists outage_confirmed_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'daftar_sync_sources_outage_status_check'
      and conrelid = 'public.daftar_sync_sources'::regclass
  ) then
    alter table public.daftar_sync_sources
      add constraint daftar_sync_sources_outage_status_check
      check (outage_status in ('healthy','suspected','confirmed'));
  end if;
end;
$$;

create or replace function public.qualify_daftar_outage(p_source_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source public.daftar_sync_sources%rowtype;
  v_status text;
  v_suspected_at timestamptz;
  v_confirmed_at timestamptz;
begin
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
    v_status := coalesce(nullif(v_source.outage_status, 'healthy'), 'confirmed');
    v_suspected_at := coalesce(v_source.outage_suspected_at, v_source.primary_activated_at, now());
    v_confirmed_at := coalesce(v_source.outage_confirmed_at, v_source.primary_activated_at, now());
  elsif v_source.health_status = 'healthy'
        and v_source.consecutive_failures = 0 then
    v_status := 'healthy';
    v_suspected_at := null;
    v_confirmed_at := null;
  elsif v_source.outage_status = 'confirmed' then
    v_status := 'confirmed';
    v_suspected_at := coalesce(v_source.outage_suspected_at, now());
    v_confirmed_at := coalesce(v_source.outage_confirmed_at, now());
  elsif v_source.consecutive_failures >= 7
        and v_source.circuit_open_until is not null
        and v_source.circuit_open_until > now()
        and (
          v_source.last_success_at is null
          or v_source.last_success_at <= now() - interval '15 minutes'
        ) then
    v_status := 'confirmed';
    v_suspected_at := coalesce(v_source.outage_suspected_at, now());
    v_confirmed_at := coalesce(v_source.outage_confirmed_at, now());
  else
    v_status := 'suspected';
    v_suspected_at := coalesce(v_source.outage_suspected_at, now());
    v_confirmed_at := null;
  end if;

  update public.daftar_sync_sources
  set outage_status = v_status,
      outage_suspected_at = v_suspected_at,
      outage_confirmed_at = v_confirmed_at,
      updated_at = now()
  where id = v_source.id;

  return jsonb_build_object(
    'outage_status', v_status,
    'consecutive_failures', v_source.consecutive_failures,
    'last_success_at', v_source.last_success_at,
    'circuit_open_until', v_source.circuit_open_until,
    'outage_suspected_at', v_suspected_at,
    'outage_confirmed_at', v_confirmed_at
  );
end;
$$;

revoke all on function public.qualify_daftar_outage(uuid)
  from public, anon, authenticated;
grant execute on function public.qualify_daftar_outage(uuid)
  to service_role;

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

  perform public.qualify_daftar_outage(v_source_id);
end;
$;

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

  perform public.qualify_daftar_outage(v_source.id);

  select *
    into v_source
  from public.daftar_sync_sources
  where id = p_source_id
  for update;

  if v_source.outage_status <> 'confirmed' then
    raise exception 'daftar_outage_not_confirmed' using errcode = '42501';
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
      'outage_status', s.outage_status,
      'outage_suspected_at', s.outage_suspected_at,
      'outage_confirmed_at', s.outage_confirmed_at,
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
    perform public.qualify_daftar_outage(v_source_id);
  end if;
end;
$$;
