-- Claim/finalize/fail RPCs for the on-device A11 RTSP recorder.
-- Jobs are tenant scoped and fenced by a per-attempt token to prevent stale
-- phones from completing the wrong attempt.

create or replace function private.a11_claim_video()
returns table(
  job_id uuid,
  market_id uuid,
  source_type text,
  source_id uuid,
  transaction_at timestamptz,
  clip_start_at timestamptz,
  clip_end_at timestamptz,
  attempt_count integer,
  attempt_generation bigint,
  attempt_token uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_market_id uuid;
  v_role text;
  v_job_id uuid;
  v_token uuid := gen_random_uuid();
begin
  if v_user_id is null then return; end if;
  v_market_id := private.current_admin_id();
  v_role := private.current_role();
  if v_market_id is null or v_role not in ('admin','employee') then return; end if;

  select j.id into v_job_id
  from private.hikvision_video_jobs j
  where j.market_id = v_market_id
    and j.provider = 'a11_local_rtsp'
    and j.status in ('queued','retrying')
    and j.run_after <= now()
    and j.clip_end_at + interval '1 second' <= now()
    and (j.lease_until is null or j.lease_until < now())
    and j.attempt_count < j.max_attempts
  order by j.transaction_at
  for update skip locked
  limit 1;

  if v_job_id is null then return; end if;

  update private.hikvision_video_jobs j
  set status = 'processing',
      gateway_id = null,
      attempt_count = j.attempt_count + 1,
      attempt_generation = j.attempt_generation + 1,
      active_attempt_token = v_token,
      attempt_started_at = now(),
      last_attempt_heartbeat_at = now(),
      lease_until = now() + interval '2 minutes',
      last_error = null,
      updated_at = now()
  where j.id = v_job_id;

  update public.transaction_video_evidence e
  set status = 'processing', updated_at = now()
  where e.job_id = v_job_id;

  return query
  select j.id, j.market_id, j.source_type, j.source_id, j.transaction_at,
         j.clip_start_at, j.clip_end_at, j.attempt_count,
         j.attempt_generation, j.active_attempt_token
  from private.hikvision_video_jobs j
  where j.id = v_job_id;
end;
$$;

revoke all on function private.a11_claim_video() from public;
grant execute on function private.a11_claim_video() to authenticated;

create or replace function public.a11_video_claim_service()
returns table(
  job_id uuid,
  market_id uuid,
  source_type text,
  source_id uuid,
  transaction_at timestamptz,
  clip_start_at timestamptz,
  clip_end_at timestamptz,
  attempt_count integer,
  attempt_generation bigint,
  attempt_token uuid
)
language sql
security invoker
set search_path = ''
as $$
  select * from private.a11_claim_video();
$$;

revoke all on function public.a11_video_claim_service() from public, anon;
grant execute on function public.a11_video_claim_service() to authenticated;

create or replace function private.a11_complete_video_v2(
  p_job_id uuid,
  p_attempt_token uuid,
  p_object_path text,
  p_byte_size bigint,
  p_duration_seconds integer,
  p_content_sha256 text,
  p_playback_metadata jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_market_id uuid;
  v_role text;
  v_job private.hikvision_video_jobs%rowtype;
begin
  if v_user_id is null then return false; end if;
  v_market_id := private.current_admin_id();
  v_role := private.current_role();
  if v_market_id is null or v_role not in ('admin','employee') then return false; end if;

  select * into v_job
  from private.hikvision_video_jobs j
  where j.id = p_job_id
    and j.market_id = v_market_id
    and j.provider = 'a11_local_rtsp'
    and j.status = 'processing'
    and j.active_attempt_token = p_attempt_token
    and coalesce(j.lease_until, now() - interval '1 second') >= now()
  for update;

  if not found then return false; end if;
  if p_object_path is null or split_part(p_object_path, '/', 1) <> v_market_id::text then return false; end if;
  if p_duration_seconds is null or p_duration_seconds < 28 or p_duration_seconds > 32 then return false; end if;
  if p_byte_size is null or p_byte_size < 20000 then return false; end if;
  if coalesce((p_playback_metadata->>'exact_trim')::boolean, false) is not true then return false; end if;

  update private.hikvision_video_jobs j
  set status = 'ready',
      completed_at = now(),
      lease_until = null,
      active_attempt_token = null,
      last_attempt_heartbeat_at = now(),
      last_error = null,
      playback_metadata = coalesce(p_playback_metadata, '{}'::jsonb)
        || jsonb_build_object(
             'provider', 'a11_local_rtsp',
             'attempt_generation', v_job.attempt_generation,
             'attempt_fenced', true
           ),
      updated_at = now()
  where j.id = p_job_id and j.active_attempt_token = p_attempt_token;

  update public.transaction_video_evidence e
  set status = 'ready',
      object_path = p_object_path,
      content_sha256 = nullif(p_content_sha256, ''),
      byte_size = p_byte_size,
      duration_seconds = p_duration_seconds,
      playback_metadata = coalesce(p_playback_metadata, '{}'::jsonb)
        || jsonb_build_object(
             'provider', 'a11_local_rtsp',
             'attempt_generation', v_job.attempt_generation,
             'attempt_fenced', true
           ),
      captured_at = now(),
      updated_at = now()
  where e.job_id = p_job_id;

  return true;
end;
$$;

revoke all on function private.a11_complete_video_v2(uuid,uuid,text,bigint,integer,text,jsonb) from public;
grant execute on function private.a11_complete_video_v2(uuid,uuid,text,bigint,integer,text,jsonb) to authenticated;

create or replace function public.a11_video_complete_v2_service(
  p_job_id uuid,
  p_attempt_token uuid,
  p_object_path text,
  p_byte_size bigint,
  p_duration_seconds integer,
  p_content_sha256 text default null,
  p_playback_metadata jsonb default '{}'::jsonb
)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  select private.a11_complete_video_v2(
    p_job_id,
    p_attempt_token,
    p_object_path,
    p_byte_size,
    p_duration_seconds,
    p_content_sha256,
    p_playback_metadata
  );
$$;

revoke all on function public.a11_video_complete_v2_service(uuid,uuid,text,bigint,integer,text,jsonb) from public, anon;
grant execute on function public.a11_video_complete_v2_service(uuid,uuid,text,bigint,integer,text,jsonb) to authenticated;

create or replace function private.a11_fail_video_v2(
  p_job_id uuid,
  p_attempt_token uuid,
  p_error text,
  p_retryable boolean default true
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_market_id uuid := private.current_admin_id();
  v_role text := private.current_role();
  v_job private.hikvision_video_jobs%rowtype;
  v_terminal boolean;
begin
  if auth.uid() is null or v_market_id is null or v_role not in ('admin','employee') then return false; end if;

  select * into v_job
  from private.hikvision_video_jobs j
  where j.id = p_job_id
    and j.market_id = v_market_id
    and j.provider = 'a11_local_rtsp'
    and j.status = 'processing'
    and j.active_attempt_token = p_attempt_token
  for update;
  if not found then return false; end if;

  v_terminal := (not coalesce(p_retryable, true)) or v_job.attempt_count >= v_job.max_attempts;

  update private.hikvision_video_jobs j
  set status = case when v_terminal then 'failed' else 'retrying' end,
      run_after = case when v_terminal then j.run_after else now() + interval '5 seconds' end,
      lease_until = null,
      active_attempt_token = null,
      last_attempt_heartbeat_at = now(),
      last_error = left(coalesce(nullif(p_error,''), 'a11_capture_failed'), 1000),
      completed_at = case when v_terminal then now() else null end,
      updated_at = now()
  where j.id = p_job_id and j.active_attempt_token = p_attempt_token;

  update public.transaction_video_evidence e
  set status = case when v_terminal then 'failed' else 'queued' end,
      updated_at = now()
  where e.job_id = p_job_id;

  return true;
end;
$$;

revoke all on function private.a11_fail_video_v2(uuid,uuid,text,boolean) from public;
grant execute on function private.a11_fail_video_v2(uuid,uuid,text,boolean) to authenticated;

create or replace function public.a11_video_fail_v2_service(
  p_job_id uuid,
  p_attempt_token uuid,
  p_error text,
  p_retryable boolean default true
)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  select private.a11_fail_video_v2(p_job_id,p_attempt_token,p_error,p_retryable);
$$;

revoke all on function public.a11_video_fail_v2_service(uuid,uuid,text,boolean) from public, anon;
grant execute on function public.a11_video_fail_v2_service(uuid,uuid,text,boolean) to authenticated;
