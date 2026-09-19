-- Production-grade resilience and observability for Daftar Qarz -> ZHIROX.

alter table public.daftar_sync_sources
  add column if not exists consecutive_failures integer not null default 0,
  add column if not exists total_failures bigint not null default 0,
  add column if not exists next_retry_at timestamptz,
  add column if not exists circuit_open_until timestamptz,
  add column if not exists last_heartbeat_at timestamptz,
  add column if not exists last_duration_ms integer,
  add column if not exists health_status text not null default 'healthy';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'daftar_sync_sources_health_status_check'
      and conrelid = 'public.daftar_sync_sources'::regclass
  ) then
    alter table public.daftar_sync_sources
      add constraint daftar_sync_sources_health_status_check
      check (health_status in ('healthy','degraded','circuit_open','disabled'));
  end if;
end;
$$;

create table if not exists public.daftar_sync_dead_letters (
  id bigint generated always as identity primary key,
  sync_source_id uuid not null references public.daftar_sync_sources(id) on delete cascade,
  entity_kind text not null,
  source_id text,
  error_code text not null,
  error_detail text,
  payload jsonb not null default '{}'::jsonb,
  attempts integer not null default 1,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolution_note text
);

create unique index if not exists daftar_sync_dead_letters_open_unique
  on public.daftar_sync_dead_letters(sync_source_id, entity_kind, coalesce(source_id, ''), error_code)
  where resolved_at is null;
create index if not exists daftar_sync_dead_letters_source_time_idx
  on public.daftar_sync_dead_letters(sync_source_id, last_seen_at desc);

alter table public.daftar_sync_dead_letters enable row level security;
revoke all on public.daftar_sync_dead_letters from public, anon, authenticated;
grant all on public.daftar_sync_dead_letters to service_role;
grant usage, select on sequence public.daftar_sync_dead_letters_id_seq to service_role;

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

revoke all on function public.claim_daftar_sync(uuid) from public, anon, authenticated;
grant execute on function public.claim_daftar_sync(uuid) to service_role;

create or replace function public.record_daftar_sync_failure(
  p_source_id uuid,
  p_error_code text,
  p_error_detail text default null,
  p_entity_kind text default 'sync',
  p_entity_source_id text default null,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_failures integer;
  v_retry_seconds integer;
  v_circuit_until timestamptz;
begin
  select consecutive_failures + 1 into v_failures
  from public.daftar_sync_sources where id = p_source_id for update;
  if v_failures is null then raise exception 'sync_source_not_found'; end if;

  v_retry_seconds := least(900, (15 * power(2, least(v_failures - 1, 6)))::integer);
  if v_failures >= 7 then v_circuit_until := now() + interval '15 minutes'; end if;

  update public.daftar_sync_sources
  set lease_until = null,
      consecutive_failures = v_failures,
      total_failures = total_failures + 1,
      next_retry_at = now() + make_interval(secs => v_retry_seconds),
      circuit_open_until = v_circuit_until,
      last_heartbeat_at = now(),
      last_status = 'failed',
      last_error = left(coalesce(p_error_code, 'unknown_error') || coalesce(': ' || p_error_detail, ''), 2000),
      health_status = case when v_circuit_until is null then 'degraded' else 'circuit_open' end,
      updated_at = now()
  where id = p_source_id;

  insert into public.daftar_sync_dead_letters(
    sync_source_id, entity_kind, source_id, error_code, error_detail, payload
  ) values (
    p_source_id, coalesce(nullif(p_entity_kind,''),'sync'), p_entity_source_id,
    coalesce(nullif(p_error_code,''),'unknown_error'), left(p_error_detail, 4000), coalesce(p_payload,'{}'::jsonb)
  )
  on conflict (sync_source_id, entity_kind, coalesce(source_id, ''), error_code)
    where resolved_at is null
  do update set attempts = public.daftar_sync_dead_letters.attempts + 1,
                last_seen_at = now(),
                error_detail = excluded.error_detail,
                payload = excluded.payload;

  return jsonb_build_object(
    'consecutive_failures', v_failures,
    'retry_after_seconds', v_retry_seconds,
    'circuit_open_until', v_circuit_until
  );
end;
$$;

revoke all on function public.record_daftar_sync_failure(uuid,text,text,text,text,jsonb)
  from public, anon, authenticated;
grant execute on function public.record_daftar_sync_failure(uuid,text,text,text,text,jsonb)
  to service_role;

create or replace function public.record_daftar_sync_success(
  p_source_id uuid,
  p_result jsonb,
  p_duration_ms integer
)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.daftar_sync_sources
  set lease_until = null,
      consecutive_failures = 0,
      next_retry_at = null,
      circuit_open_until = null,
      last_heartbeat_at = now(),
      last_success_at = now(),
      last_duration_ms = greatest(coalesce(p_duration_ms, 0), 0),
      last_status = 'success',
      last_error = null,
      last_result = coalesce(p_result, '{}'::jsonb),
      health_status = 'healthy',
      updated_at = now()
  where id = p_source_id;
$$;

revoke all on function public.record_daftar_sync_success(uuid,jsonb,integer)
  from public, anon, authenticated;
grant execute on function public.record_daftar_sync_success(uuid,jsonb,integer)
  to service_role;

create or replace function public.get_my_daftar_sync_health()
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'source_name', s.source_name,
    'enabled', s.enabled,
    'health_status', s.health_status,
    'last_status', s.last_status,
    'last_started_at', s.last_started_at,
    'last_success_at', s.last_success_at,
    'last_heartbeat_at', s.last_heartbeat_at,
    'last_duration_ms', s.last_duration_ms,
    'consecutive_failures', s.consecutive_failures,
    'next_retry_at', s.next_retry_at,
    'circuit_open_until', s.circuit_open_until,
    'last_error', s.last_error,
    'open_dead_letters', (
      select count(*) from public.daftar_sync_dead_letters d
      where d.sync_source_id = s.id and d.resolved_at is null
    )
  )), '[]'::jsonb)
  from public.daftar_sync_sources s
  where (select auth.uid()) is not null
    and s.admin_id = (select auth.uid());
$$;

revoke all on function public.get_my_daftar_sync_health() from public, anon;
grant execute on function public.get_my_daftar_sync_health() to authenticated;

do $$
declare v_job_id bigint;
begin
  select jobid into v_job_id from cron.job
  where jobname = 'daftar-live-sync-account-28' limit 1;
  if v_job_id is not null then
    perform cron.alter_job(job_id => v_job_id, schedule => '* * * * *', active => true);
  end if;
end;
$$;
