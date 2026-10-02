-- Enterprise continuity hardening for Daftar <-> ZHIROX.
-- Adds dispatch fencing, health history/integrity sentinel, a shorter stale
-- lease window, and immediate success-state healing.

create table if not exists private.daftar_dispatch_fence (
  sync_source_id uuid not null references public.daftar_sync_sources(id) on delete cascade,
  direction text not null check (direction in ('inbound','outbound')),
  slot bigint not null,
  created_at timestamptz not null default now(),
  primary key (sync_source_id, direction, slot)
);

create index if not exists daftar_dispatch_fence_created_idx
  on private.daftar_dispatch_fence (created_at);

revoke all on table private.daftar_dispatch_fence from public, anon, authenticated;

create table if not exists private.daftar_sync_health_samples (
  id bigint generated always as identity primary key,
  sync_source_id uuid not null references public.daftar_sync_sources(id) on delete cascade,
  observed_at timestamptz not null default now(),
  status text not null check (status in ('healthy','degraded','critical')),
  heartbeat_age_seconds integer,
  success_age_seconds integer,
  queue_waiting integer not null default 0,
  stale_processing integer not null default 0,
  blocked_events integer not null default 0,
  failed_events integer not null default 0,
  open_dead_letters integer not null default 0,
  missing_contacts bigint not null default 0,
  missing_transactions bigint not null default 0,
  details jsonb not null default '{}'::jsonb
);

create index if not exists daftar_sync_health_samples_source_time_idx
  on private.daftar_sync_health_samples (sync_source_id, observed_at desc);

revoke all on table private.daftar_sync_health_samples from public, anon, authenticated;

create or replace function private.claim_daftar_dispatch_slot(
  p_source_id uuid,
  p_direction text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_slot bigint := floor(extract(epoch from clock_timestamp()) / 30)::bigint;
begin
  if p_direction not in ('inbound','outbound') then
    raise exception 'invalid_dispatch_direction';
  end if;

  insert into private.daftar_dispatch_fence(sync_source_id,direction,slot)
  values (p_source_id,p_direction,v_slot)
  on conflict do nothing;

  return found;
end;
$$;

revoke all on function private.claim_daftar_dispatch_slot(uuid,text) from public, anon, authenticated;

create or replace function private.check_daftar_sync_integrity(p_source_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.daftar_sync_sources%rowtype;
  v_heartbeat_age integer;
  v_success_age integer;
  v_queue integer := 0;
  v_stale integer := 0;
  v_blocked integer := 0;
  v_failed integer := 0;
  v_dead integer := 0;
  v_status text := 'healthy';
  v_result jsonb;
begin
  select * into s from public.daftar_sync_sources where id=p_source_id;
  if s.id is null then raise exception 'sync_source_not_found'; end if;

  v_heartbeat_age := case when s.last_heartbeat_at is null then null else greatest(0, extract(epoch from (now()-s.last_heartbeat_at))::int) end;
  v_success_age := case when s.last_success_at is null then null else greatest(0, extract(epoch from (now()-s.last_success_at))::int) end;

  select
    count(*) filter (where status in ('pending','failed') and next_attempt_at <= now()),
    count(*) filter (where status='processing' and updated_at < now()-interval '2 minutes'),
    count(*) filter (where status='blocked'),
    count(*) filter (where status='failed')
  into v_queue,v_stale,v_blocked,v_failed
  from public.daftar_outbound_events
  where sync_source_id=s.id;

  select count(*) into v_dead
  from public.daftar_sync_dead_letters
  where sync_source_id=s.id and resolved_at is null;

  if s.last_status='failed'
     or s.health_status in ('circuit_open','disabled')
     or s.outage_status='confirmed'
     or coalesce(v_success_age,2147483647) > 300
     or coalesce(s.reconciliation_missing_contacts,0) > 0
     or coalesce(s.reconciliation_missing_transactions,0) > 0
     or v_stale > 0
     or v_blocked > 0
     or v_dead > 0 then
    v_status := 'critical';
  elsif s.health_status='degraded'
     or s.outage_status='suspected'
     or coalesce(v_success_age,2147483647) > 90
     or v_failed > 0
     or v_queue > 25 then
    v_status := 'degraded';
  end if;

  v_result := jsonb_build_object(
    'status',v_status,
    'heartbeat_age_seconds',v_heartbeat_age,
    'success_age_seconds',v_success_age,
    'queue_waiting',v_queue,
    'stale_processing',v_stale,
    'blocked_events',v_blocked,
    'failed_events',v_failed,
    'open_dead_letters',v_dead,
    'missing_contacts',coalesce(s.reconciliation_missing_contacts,0),
    'missing_transactions',coalesce(s.reconciliation_missing_transactions,0),
    'source_health',s.health_status,
    'outage_status',s.outage_status,
    'last_status',s.last_status
  );

  insert into private.daftar_sync_health_samples(
    sync_source_id,status,heartbeat_age_seconds,success_age_seconds,
    queue_waiting,stale_processing,blocked_events,failed_events,open_dead_letters,
    missing_contacts,missing_transactions,details
  ) values (
    s.id,v_status,v_heartbeat_age,v_success_age,v_queue,v_stale,v_blocked,v_failed,v_dead,
    coalesce(s.reconciliation_missing_contacts,0),coalesce(s.reconciliation_missing_transactions,0),v_result
  );

  delete from private.daftar_sync_health_samples
  where observed_at < now()-interval '30 days';

  return v_result;
end;
$$;

revoke all on function private.check_daftar_sync_integrity(uuid) from public, anon, authenticated;

create or replace function private.run_daftar_integrity_sentinel()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_result jsonb;
  v_healthy integer := 0;
  v_degraded integer := 0;
  v_critical integer := 0;
  v_reconciled integer := 0;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('zhirox-daftar-integrity-sentinel',0)) then
    return jsonb_build_object('skipped','already_running');
  end if;

  for r in
    select id,last_reconciled_at,lease_until
    from public.daftar_sync_sources
    where enabled=true or inbound_sync_enabled=true or outbound_sync_enabled=true
    order by created_at
  loop
    v_result := private.check_daftar_sync_integrity(r.id);

    case v_result->>'status'
      when 'healthy' then v_healthy := v_healthy + 1;
      when 'degraded' then v_degraded := v_degraded + 1;
      else v_critical := v_critical + 1;
    end case;

    if (v_result->>'status') in ('degraded','critical')
       and (r.lease_until is null or r.lease_until <= now())
       and (r.last_reconciled_at is null or r.last_reconciled_at < now()-interval '5 minutes') then
      perform private.reconcile_daftar_source(r.id);
      perform private.run_daftar_sync_reconciliation(r.id);
      v_reconciled := v_reconciled + 1;
    end if;
  end loop;

  delete from private.daftar_dispatch_fence
  where created_at < now()-interval '1 day';

  return jsonb_build_object(
    'healthy',v_healthy,
    'degraded',v_degraded,
    'critical',v_critical,
    'reconciled',v_reconciled
  );
end;
$$;

revoke all on function private.run_daftar_integrity_sentinel() from public, anon, authenticated;

create or replace function private.dispatch_daftar_sync_sources()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_secret text;
  v_inbound_count integer := 0;
  v_outbound_count integer := 0;
  v_skipped_count integer := 0;
  v_backoff_skipped integer := 0;
  v_fence_skipped integer := 0;
  v_inbound_allowed boolean;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('zhirox-daftar-dispatch',0)) then
    return jsonb_build_object('skipped','dispatcher_already_running');
  end if;

  for r in
    select
      s.id,s.legacy_user_id,s.source_fingerprint,s.trigger_secret_hash,
      s.trigger_secret_vault_name,s.sync_mode,s.inbound_sync_enabled,
      s.outbound_sync_enabled,s.outbound_write_contract_status,
      s.lease_until,s.next_retry_at,s.circuit_open_until
    from public.daftar_sync_sources s
    where s.enabled = true
      and nullif(s.trigger_secret_vault_name, '') is not null
    order by s.created_at
  loop
    v_secret := null;
    select decrypted_secret into v_secret
    from vault.decrypted_secrets
    where name = r.trigger_secret_vault_name
    limit 1;

    if v_secret is null
       or encode(extensions.digest(v_secret, 'sha256'), 'hex') is distinct from r.trigger_secret_hash then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    v_inbound_allowed :=
      (r.lease_until is null or r.lease_until <= now())
      and (r.next_retry_at is null or r.next_retry_at <= now())
      and (r.circuit_open_until is null or r.circuit_open_until <= now());

    if (r.sync_mode = 'mirror' or (r.sync_mode = 'zhirox_primary' and r.inbound_sync_enabled = true)) then
      if v_inbound_allowed then
        if private.claim_daftar_dispatch_slot(r.id,'inbound') then
          perform net.http_post(
            url := 'https://madoflmbretqghqbqaak.supabase.co/functions/v1/daftar-sync-gateway',
            headers := jsonb_build_object('Content-Type','application/json','x-daftar-sync-secret',v_secret),
            body := jsonb_build_object('source_id',r.id),
            timeout_milliseconds := 120000
          );
          v_inbound_count := v_inbound_count + 1;
        else
          v_fence_skipped := v_fence_skipped + 1;
        end if;
      else
        v_backoff_skipped := v_backoff_skipped + 1;
      end if;
    end if;

    if r.sync_mode = 'zhirox_primary'
       and r.outbound_sync_enabled = true
       and r.outbound_write_contract_status = 'verified' then
      if private.claim_daftar_dispatch_slot(r.id,'outbound') then
        perform net.http_post(
          url := 'https://madoflmbretqghqbqaak.supabase.co/functions/v1/daftar-outbound-sync',
          headers := jsonb_build_object('Content-Type','application/json','x-daftar-sync-secret',v_secret),
          body := jsonb_build_object('source_id',r.id,'action','drain'),
          timeout_milliseconds := 120000
        );
        v_outbound_count := v_outbound_count + 1;
      else
        v_fence_skipped := v_fence_skipped + 1;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'inbound_dispatched',v_inbound_count,
    'outbound_dispatched',v_outbound_count,
    'skipped_missing_or_invalid_secret',v_skipped_count,
    'inbound_skipped_backoff_or_lease',v_backoff_skipped,
    'dispatch_fence_skipped',v_fence_skipped
  );
end;
$$;

revoke all on function private.dispatch_daftar_sync_sources() from public, anon, authenticated;

create or replace function public.claim_daftar_sync(p_source_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.daftar_sync_sources
  set lease_until = now() + interval '3 minutes',
      last_started_at = now(),
      last_heartbeat_at = now(),
      last_status = 'running',
      last_error = null,
      updated_at = now()
  where id = p_source_id
    and enabled = true
    and (lease_until is null or lease_until < now())
    and (next_retry_at is null or next_retry_at <= now())
    and (circuit_open_until is null or circuit_open_until <= now());
  return found;
end;
$$;

create or replace function public.record_daftar_sync_success(
  p_source_id uuid,
  p_result jsonb,
  p_duration_ms integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.daftar_sync_sources
  set lease_until = null,
      consecutive_failures = 0,
      next_retry_at = null,
      circuit_open_until = null,
      last_heartbeat_at = now(),
      last_success_at = now(),
      last_duration_ms = greatest(coalesce(p_duration_ms,0),0),
      last_status = 'success',
      last_error = null,
      last_result = coalesce(p_result,'{}'::jsonb),
      health_status = 'healthy',
      outage_status = 'healthy',
      outage_suspected_at = null,
      outage_confirmed_at = null,
      updated_at = now()
  where id = p_source_id;

  perform private.resolve_daftar_transient_dead_letters(p_source_id);
end;
$$;

revoke all on function public.claim_daftar_sync(uuid) from public, anon, authenticated;
revoke all on function public.record_daftar_sync_success(uuid,jsonb,integer) from public, anon, authenticated;
grant execute on function public.claim_daftar_sync(uuid) to service_role;
grant execute on function public.record_daftar_sync_success(uuid,jsonb,integer) to service_role;

do $$
declare v_job_id bigint;
begin
  select jobid into v_job_id from cron.job where jobname='daftar-sync-integrity-sentinel' limit 1;
  if v_job_id is null then
    perform cron.schedule('daftar-sync-integrity-sentinel','* * * * *','select private.run_daftar_integrity_sentinel();');
  else
    perform cron.alter_job(job_id=>v_job_id,schedule=>'* * * * *',command=>'select private.run_daftar_integrity_sentinel();',active=>true);
  end if;
end;
$$;