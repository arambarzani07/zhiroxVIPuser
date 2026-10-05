create or replace function private.complete_hikvision_video_job_v2(
  p_gateway_id uuid,
  p_job_id uuid,
  p_attempt_token uuid,
  p_object_path text,
  p_thumbnail_path text default null,
  p_content_sha256 text default null,
  p_byte_size bigint default null,
  p_duration_seconds integer default null,
  p_playback_metadata jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_market_id uuid;
  v_transaction_at timestamptz;
  v_attempt integer;
  v_max integer;
  v_duplicate boolean := false;
  v_status text;
begin
  select j.market_id, j.transaction_at, j.attempt_count, j.max_attempts
    into v_market_id, v_transaction_at, v_attempt, v_max
  from private.hikvision_video_jobs j
  where j.id = p_job_id
    and j.gateway_id = p_gateway_id
    and j.active_attempt_token = p_attempt_token
    and j.status in ('processing','uploading')
  for update;

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

  if p_content_sha256 is not null and length(trim(p_content_sha256)) = 64 then
    select exists (
      select 1
      from public.transaction_video_evidence e2
      join private.hikvision_video_jobs j2 on j2.id = e2.job_id
      where e2.market_id = v_market_id
        and e2.status = 'ready'
        and e2.content_sha256 = lower(trim(p_content_sha256))
        and e2.job_id <> p_job_id
        and abs(extract(epoch from (j2.transaction_at - v_transaction_at))) > 5
    ) into v_duplicate;
  end if;

  if v_duplicate then
    v_status := case when v_attempt >= v_max then 'failed' else 'retrying' end;

    update private.hikvision_video_jobs j
    set status = v_status,
        run_after = case when v_status = 'retrying' then now() + interval '15 seconds' else j.run_after end,
        gateway_id = case when v_status = 'retrying' then null else j.gateway_id end,
        active_attempt_token = null,
        lease_until = null,
        last_attempt_heartbeat_at = now(),
        last_error = 'duplicate_clip_sha256_detected',
        completed_at = case when v_status = 'failed' then now() else null end,
        updated_at = now()
    where j.id = p_job_id;

    update public.transaction_video_evidence e
    set status = case when v_status = 'retrying' then 'queued' else 'failed' end,
        updated_at = now()
    where e.job_id = p_job_id;

    return false;
  end if;

  update private.hikvision_video_jobs j
  set status = 'ready',
      lease_until = null,
      last_attempt_heartbeat_at = now(),
      completed_at = now(),
      updated_at = now(),
      playback_metadata = coalesce(p_playback_metadata,'{}'::jsonb),
      last_error = null
  where j.id = p_job_id
    and j.gateway_id = p_gateway_id
    and j.active_attempt_token = p_attempt_token
    and j.status in ('processing','uploading');

  if not found then
    return false;
  end if;

  update public.transaction_video_evidence e
  set status = 'ready',
      object_path = p_object_path,
      thumbnail_path = p_thumbnail_path,
      content_sha256 = case when p_content_sha256 is null then null else lower(trim(p_content_sha256)) end,
      byte_size = p_byte_size,
      duration_seconds = p_duration_seconds,
      playback_metadata = coalesce(p_playback_metadata,'{}'::jsonb),
      captured_at = now(),
      updated_at = now()
  where e.job_id = p_job_id;

  return true;
end;
$function$;
