-- Fix the Hikvision rebuild gateway version gate.
-- The previous pattern was double-escaped by a later hardening migration,
-- causing valid versions such as 1.2.x, 1.3.x and 2.x to be rejected.
-- Character classes avoid backslash escaping entirely.

create or replace function private.hikvision_rebuild_status(
  p_market_id uuid,
  p_source_type text,
  p_source_id uuid
)
returns jsonb
language sql
security definer
set search_path to ''
as $function$
  select jsonb_build_object(
    'can_rebuild',coalesce(
      j.status in ('ready','failed','missing') and j.attempt_count<30 and
      (j.rebuild_requested_at is null or j.rebuild_requested_at<now()-interval '1 minute') and
      c.enabled and c.capture_provider='local_gateway' and g.active and
      g.last_seen_at>now()-interval '3 minutes' and g.last_seen_at<=now()+interval '30 seconds' and
      g.gateway_version ~ '^(1[.](2|[3-9]|[1-9][0-9]+)[.]|[2-9][.])',false),
    'job_status',j.status,
    'attempt_count',j.attempt_count,
    'max_attempts',j.max_attempts,
    'last_error_code',case
      when j.last_error is null then null
      when j.last_error like '%unsupported_hevc_payload%' then 'unsupported_hevc_payload'
      when j.last_error like '%download_rejected%' then 'download_rejected'
      when j.last_error like '%recording_not_found%' then 'recording_not_found'
      when j.last_error like '%duplicate_clip_sha256_detected%' then 'duplicate_clip'
      when j.last_error like '%clip_quality_gate_failed%' then 'clip_quality_gate_failed'
      else 'gateway_error'
    end,
    'requested_at',j.rebuild_requested_at,
    'request_count',j.rebuild_request_count)
  from private.hikvision_video_jobs j
  join public.hikvision_market_config c on c.market_id=j.market_id
  left join private.hikvision_gateways g on g.market_id=j.market_id
  where j.market_id=p_market_id and j.source_type=p_source_type and j.source_id=p_source_id;
$function$;

revoke all on function private.hikvision_rebuild_status(uuid,text,uuid) from public,anon,authenticated;

-- Migration-level sanity guard so this regression cannot silently return.
do $test$
begin
  if not ('1.2.0' ~ '^(1[.](2|[3-9]|[1-9][0-9]+)[.]|[2-9][.])')
     or not ('1.3.3+bounded-fallback-1' ~ '^(1[.](2|[3-9]|[1-9][0-9]+)[.]|[2-9][.])')
     or not ('2.0.0' ~ '^(1[.](2|[3-9]|[1-9][0-9]+)[.]|[2-9][.])')
     or ('1.1.9' ~ '^(1[.](2|[3-9]|[1-9][0-9]+)[.]|[2-9][.])') then
    raise exception 'hikvision gateway version gate regression';
  end if;
end;
$test$;