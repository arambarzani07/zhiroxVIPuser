-- Hikvision gateway v2: per-attempt fencing, heartbeats, and stale-lease recovery.
-- v1 remains usable for installed 1.0 gateways, but v1 callbacks are fenced out
-- as soon as a v2 attempt token owns the job.

alter table private.hikvision_video_jobs
  add column if not exists active_attempt_token uuid,
  add column if not exists attempt_generation bigint not null default 0,
  add column if not exists attempt_started_at timestamptz,
  add column if not exists last_attempt_heartbeat_at timestamptz;

create index if not exists hikvision_video_jobs_active_lease_idx
  on private.hikvision_video_jobs(market_id, lease_until)
  where status in ('processing','uploading');

create or replace function private.recover_stale_hikvision_video_jobs(p_market_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_status text;
  v_count integer := 0;
begin
  for r in
    select j.id, j.attempt_count, j.max_attempts
    from private.hikvision_video_jobs j
    where j.market_id = p_market_id
      and j.status in ('processing','uploading')
      and j.lease_until is not null
      and j.lease_until < now()
    order by j.lease_until
    for update skip locked
    limit 100
  loop
    v_status := case when r.attempt_count >= r.max_attempts then 'failed' else 'retrying' end;

    update private.hikvision_video_jobs j
    set status = v_status,
        gateway_id = case when v_status = 'retrying' then null else j.gateway_id end,
        active_attempt_token = null,
        lease_until = null,
        last_attempt_heartbeat_at = null,
        run_after = case when v_status = 'retrying' then now() + interval '15 seconds' else j.run_after end,
        last_error = 'stale_gateway_lease_recovered',
        completed_at = case when v_status = 'failed' then now() else null end,
        updated_at = now()
    where j.id = r.id;

    update public.transaction_video_evidence e
    set status = case when v_status = 'retrying' then 'queued' else 'failed' end,
        updated_at = now()
    where e.job_id = r.id;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

create or replace function private.claim_hikvision_video_job_v2(p_gateway_id uuid)
returns table (
  job_id uuid, market_id uuid, source_type text, source_id uuid,
  transaction_at timestamptz, channel_id integer,
  clip_start_at timestamptz, clip_end_at timestamptz,
  attempt_count integer, attempt_generation bigint, attempt_token uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_market_id uuid;
  v_job_id uuid;
  v_token uuid := gen_random_uuid();
begin
  select g.market_id into v_market_id
  from private.hikvision_gateways g
  where g.id = p_gateway_id and g.active = true;
  if v_market_id is null then return; end if;

  perform private.recover_stale_hikvision_video_jobs(v_market_id);

  select j.id into v_job_id
  from private.hikvision_video_jobs j
  where j.market_id = v_market_id
    and j.status in ('queued','retrying')
    and j.run_after <= now()
    and j.clip_end_at + interval '3 seconds' <= now()
    and (j.lease_until is null or j.lease_until < now())
  order by j.transaction_at
  for update skip locked
  limit 1;
  if v_job_id is null then return; end if;

  update private.hikvision_video_jobs j
  set status = 'processing',
      gateway_id = p_gateway_id,
      attempt_count = j.attempt_count + 1,
      attempt_generation = j.attempt_generation + 1,
      active_attempt_token = v_token,
      attempt_started_at = now(),
      last_attempt_heartbeat_at = now(),
      lease_until = now() + interval '3 minutes',
      last_error = null,
      updated_at = now()
  where j.id = v_job_id;

  update public.transaction_video_evidence e
  set status = 'processing', updated_at = now()
  where e.job_id = v_job_id;

  return query
  select j.id, j.market_id, j.source_type, j.source_id, j.transaction_at,
         j.channel_id, j.clip_start_at, j.clip_end_at, j.attempt_count,
         j.attempt_generation, j.active_attempt_token
  from private.hikvision_video_jobs j
  where j.id = v_job_id;
end;
$$;

create or replace function private.heartbeat_hikvision_video_job_v2(
  p_gateway_id uuid, p_job_id uuid, p_attempt_token uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.hikvision_video_jobs j
  set last_attempt_heartbeat_at = now(),
      lease_until = now() + interval '3 minutes',
      updated_at = now()
  where j.id = p_job_id
    and j.gateway_id = p_gateway_id
    and j.active_attempt_token = p_attempt_token
    and j.status in ('processing','uploading');
  return found;
end;
$$;

create or replace function private.prepare_hikvision_video_upload_v2(
  p_gateway_id uuid, p_job_id uuid, p_attempt_token uuid
)
returns table (
  market_id uuid, source_type text, source_id uuid, transaction_at timestamptz,
  channel_id integer, clip_start_at timestamptz, clip_end_at timestamptz,
  attempt_generation bigint
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.hikvision_video_jobs j
  set status = 'uploading',
      last_attempt_heartbeat_at = now(),
      lease_until = now() + interval '3 minutes',
      updated_at = now()
  where j.id = p_job_id
    and j.gateway_id = p_gateway_id
    and j.active_attempt_token = p_attempt_token
    and j.status in ('processing','uploading');
  if not found then return; end if;

  update public.transaction_video_evidence e
  set status = 'uploading', updated_at = now()
  where e.job_id = p_job_id;

  return query
  select j.market_id, j.source_type, j.source_id, j.transaction_at,
         j.channel_id, j.clip_start_at, j.clip_end_at, j.attempt_generation
  from private.hikvision_video_jobs j
  where j.id = p_job_id
    and j.gateway_id = p_gateway_id
    and j.active_attempt_token = p_attempt_token;
end;
$$;

create or replace function private.complete_hikvision_video_job_v2(
  p_gateway_id uuid, p_job_id uuid, p_attempt_token uuid,
  p_object_path text, p_thumbnail_path text default null,
  p_content_sha256 text default null, p_byte_size bigint default null,
  p_duration_seconds integer default null,
  p_playback_metadata jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.hikvision_video_jobs j
  set status = 'ready', lease_until = null,
      last_attempt_heartbeat_at = now(), completed_at = now(), updated_at = now(),
      playback_metadata = coalesce(p_playback_metadata,'{}'::jsonb), last_error = null
  where j.id = p_job_id
    and j.gateway_id = p_gateway_id
    and j.active_attempt_token = p_attempt_token
    and j.status in ('processing','uploading');

  if not found then
    return exists (
      select 1
      from private.hikvision_video_jobs j
      join public.transaction_video_evidence e on e.job_id = j.id
      where j.id = p_job_id
        and j.gateway_id = p_gateway_id
        and j.active_attempt_token = p_attempt_token
        and j.status = 'ready'
        and e.status = 'ready'
        and e.object_path = p_object_path
    );
  end if;

  update public.transaction_video_evidence e
  set status = 'ready', object_path = p_object_path, thumbnail_path = p_thumbnail_path,
      content_sha256 = p_content_sha256, byte_size = p_byte_size,
      duration_seconds = p_duration_seconds,
      playback_metadata = coalesce(p_playback_metadata,'{}'::jsonb),
      captured_at = now(), updated_at = now()
  where e.job_id = p_job_id;

  return true;
end;
$$;

create or replace function private.fail_hikvision_video_job_v2(
  p_gateway_id uuid, p_job_id uuid, p_attempt_token uuid,
  p_error text, p_missing boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempt integer;
  v_max integer;
  v_status text;
begin
  select j.attempt_count, j.max_attempts into v_attempt, v_max
  from private.hikvision_video_jobs j
  where j.id = p_job_id
    and j.gateway_id = p_gateway_id
    and j.active_attempt_token = p_attempt_token
    and j.status in ('processing','uploading')
  for update;
  if not found then return false; end if;

  v_status := case
    when p_missing then 'missing'
    when v_attempt >= v_max then 'failed'
    else 'retrying'
  end;

  update private.hikvision_video_jobs j
  set status = v_status,
      run_after = case when v_status = 'retrying'
        then now() + make_interval(secs => least(300, 15 * (2 ^ greatest(0, v_attempt - 1))::int))
        else j.run_after end,
      gateway_id = case when v_status = 'retrying' then null else j.gateway_id end,
      active_attempt_token = case when v_status = 'retrying' then null else j.active_attempt_token end,
      lease_until = null,
      last_attempt_heartbeat_at = now(),
      last_error = left(coalesce(p_error,'unknown_error'),1000),
      completed_at = case when v_status in ('missing','failed') then now() else null end,
      updated_at = now()
  where j.id = p_job_id;

  update public.transaction_video_evidence e
  set status = case when v_status = 'retrying' then 'queued' else v_status end,
      updated_at = now()
  where e.job_id = p_job_id;

  return true;
end;
$$;

-- Public service-role wrappers used by the Edge Function.
create or replace function public.hikvision_gateway_claim_v2_service(p_gateway_id uuid)
returns table (
  job_id uuid, market_id uuid, source_type text, source_id uuid,
  transaction_at timestamptz, channel_id integer,
  clip_start_at timestamptz, clip_end_at timestamptz,
  attempt_count integer, attempt_generation bigint, attempt_token uuid
)
language sql security definer set search_path = ''
as $$ select * from private.claim_hikvision_video_job_v2(p_gateway_id); $$;

create or replace function public.hikvision_gateway_job_heartbeat_v2_service(
  p_gateway_id uuid, p_job_id uuid, p_attempt_token uuid
)
returns boolean
language sql security definer set search_path = ''
as $$ select private.heartbeat_hikvision_video_job_v2(p_gateway_id,p_job_id,p_attempt_token); $$;

create or replace function public.hikvision_gateway_prepare_upload_v2_service(
  p_gateway_id uuid, p_job_id uuid, p_attempt_token uuid
)
returns table (
  market_id uuid, source_type text, source_id uuid, transaction_at timestamptz,
  channel_id integer, clip_start_at timestamptz, clip_end_at timestamptz,
  attempt_generation bigint
)
language sql security definer set search_path = ''
as $$ select * from private.prepare_hikvision_video_upload_v2(p_gateway_id,p_job_id,p_attempt_token); $$;

create or replace function public.hikvision_gateway_complete_v2_service(
  p_gateway_id uuid, p_job_id uuid, p_attempt_token uuid,
  p_object_path text, p_thumbnail_path text default null,
  p_content_sha256 text default null, p_byte_size bigint default null,
  p_duration_seconds integer default null,
  p_playback_metadata jsonb default '{}'::jsonb
)
returns boolean
language sql security definer set search_path = ''
as $$
  select private.complete_hikvision_video_job_v2(
    p_gateway_id,p_job_id,p_attempt_token,p_object_path,p_thumbnail_path,
    p_content_sha256,p_byte_size,p_duration_seconds,p_playback_metadata
  );
$$;

create or replace function public.hikvision_gateway_fail_v2_service(
  p_gateway_id uuid, p_job_id uuid, p_attempt_token uuid,
  p_error text, p_missing boolean default false
)
returns boolean
language sql security definer set search_path = ''
as $$
  select private.fail_hikvision_video_job_v2(
    p_gateway_id,p_job_id,p_attempt_token,p_error,p_missing
  );
$$;

-- Fence v1 upload preparation once a v2 token owns a job.
create or replace function public.hikvision_gateway_prepare_upload_service(
  p_gateway_id uuid, p_job_id uuid
)
returns table (
  market_id uuid, source_type text, source_id uuid, transaction_at timestamptz,
  channel_id integer, clip_start_at timestamptz, clip_end_at timestamptz
)
language plpgsql security definer set search_path = ''
as $$
begin
  update private.hikvision_video_jobs j
  set status = 'uploading', lease_until = now() + interval '10 minutes', updated_at = now()
  where j.id = p_job_id
    and j.gateway_id = p_gateway_id
    and j.active_attempt_token is null
    and j.status = 'processing';
  if not found then return; end if;

  update public.transaction_video_evidence e
  set status = 'uploading', updated_at = now()
  where e.job_id = p_job_id;

  return query
  select j.market_id,j.source_type,j.source_id,j.transaction_at,
         j.channel_id,j.clip_start_at,j.clip_end_at
  from private.hikvision_video_jobs j
  where j.id = p_job_id;
end;
$$;

-- Fence v1 terminal callbacks. They may only finish tokenless v1 attempts.
create or replace function public.hikvision_gateway_complete_service(
  p_gateway_id uuid, p_job_id uuid, p_object_path text,
  p_thumbnail_path text default null, p_content_sha256 text default null,
  p_byte_size bigint default null, p_duration_seconds integer default null,
  p_playback_metadata jsonb default '{}'::jsonb
)
returns boolean
language plpgsql security definer set search_path = ''
as $$
begin
  if exists (
    select 1 from private.hikvision_video_jobs j
    where j.id = p_job_id and j.active_attempt_token is not null
  ) then return false; end if;

  return private.complete_hikvision_video_job(
    p_gateway_id,p_job_id,p_object_path,p_thumbnail_path,p_content_sha256,
    p_byte_size,p_duration_seconds,p_playback_metadata
  );
end;
$$;

create or replace function public.hikvision_gateway_fail_service(
  p_gateway_id uuid, p_job_id uuid, p_error text, p_missing boolean default false
)
returns boolean
language plpgsql security definer set search_path = ''
as $$
begin
  if exists (
    select 1 from private.hikvision_video_jobs j
    where j.id = p_job_id and j.active_attempt_token is not null
  ) then return false; end if;

  return private.fail_hikvision_video_job(p_gateway_id,p_job_id,p_error,p_missing);
end;
$$;

revoke all on function private.recover_stale_hikvision_video_jobs(uuid) from public,anon,authenticated;
revoke all on function private.claim_hikvision_video_job_v2(uuid) from public,anon,authenticated;
revoke all on function private.heartbeat_hikvision_video_job_v2(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function private.prepare_hikvision_video_upload_v2(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function private.complete_hikvision_video_job_v2(uuid,uuid,uuid,text,text,text,bigint,integer,jsonb) from public,anon,authenticated;
revoke all on function private.fail_hikvision_video_job_v2(uuid,uuid,uuid,text,boolean) from public,anon,authenticated;

revoke all on function public.hikvision_gateway_claim_v2_service(uuid) from public,anon,authenticated;
revoke all on function public.hikvision_gateway_job_heartbeat_v2_service(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.hikvision_gateway_prepare_upload_v2_service(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.hikvision_gateway_complete_v2_service(uuid,uuid,uuid,text,text,text,bigint,integer,jsonb) from public,anon,authenticated;
revoke all on function public.hikvision_gateway_fail_v2_service(uuid,uuid,uuid,text,boolean) from public,anon,authenticated;

grant execute on function public.hikvision_gateway_claim_v2_service(uuid) to service_role;
grant execute on function public.hikvision_gateway_job_heartbeat_v2_service(uuid,uuid,uuid) to service_role;
grant execute on function public.hikvision_gateway_prepare_upload_v2_service(uuid,uuid,uuid) to service_role;
grant execute on function public.hikvision_gateway_complete_v2_service(uuid,uuid,uuid,text,text,text,bigint,integer,jsonb) to service_role;
grant execute on function public.hikvision_gateway_fail_v2_service(uuid,uuid,uuid,text,boolean) to service_role;
