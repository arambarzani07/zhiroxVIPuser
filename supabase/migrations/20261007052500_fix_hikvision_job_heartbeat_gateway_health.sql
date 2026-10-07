-- Keep Gateway health online while a long video job is actively heartbeating.
-- A valid fenced job heartbeat proves the Gateway process is alive, so refresh
-- the Gateway last_seen_at timestamp as part of the same successful operation.
create or replace function private.heartbeat_hikvision_video_job_v2(
  p_gateway_id uuid,
  p_job_id uuid,
  p_attempt_token uuid
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
begin
  update private.hikvision_video_jobs j
  set last_attempt_heartbeat_at = now(),
      lease_until = now() + interval '3 minutes',
      updated_at = now()
  where j.id = p_job_id
    and j.gateway_id = p_gateway_id
    and j.active_attempt_token = p_attempt_token
    and j.status in ('processing','uploading');

  if not found then
    return false;
  end if;

  update private.hikvision_gateways g
  set last_seen_at = now(),
      last_error = null,
      updated_at = now()
  where g.id = p_gateway_id
    and g.active = true;

  perform private.evaluate_hikvision_gateway_health(p_gateway_id);
  return true;
end;
$function$;
