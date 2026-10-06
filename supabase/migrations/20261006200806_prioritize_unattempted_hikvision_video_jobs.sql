-- Prefer jobs with fewer attempts so historical failures cannot block fresh transaction evidence.
-- Preserve tenant/provider filters, active-job exclusion and per-attempt fencing.
CREATE OR REPLACE FUNCTION private.claim_hikvision_video_job_v2(p_gateway_id uuid)
 RETURNS TABLE(job_id uuid, market_id uuid, source_type text, source_id uuid, transaction_at timestamp with time zone, channel_id integer, clip_start_at timestamp with time zone, clip_end_at timestamp with time zone, attempt_count integer, attempt_generation bigint, attempt_token uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_market_id uuid; v_job_id uuid; v_token uuid := gen_random_uuid();
begin
  select g.market_id into v_market_id from private.hikvision_gateways g where g.id=p_gateway_id and g.active=true; if v_market_id is null then return; end if;
  perform private.recover_stale_hikvision_video_jobs(v_market_id);
  if exists (select 1 from private.hikvision_video_jobs j where j.gateway_id=p_gateway_id and j.provider='local_gateway' and j.status in ('processing','uploading') and coalesce(j.lease_until, now()+interval '1 second')>now()) then return; end if;
  select j.id into v_job_id from private.hikvision_video_jobs j where j.market_id=v_market_id and j.provider='local_gateway' and j.status in ('queued','retrying') and j.run_after<=now() and j.clip_end_at+interval '3 seconds'<=now() and (j.lease_until is null or j.lease_until<now()) order by j.attempt_count asc, j.transaction_at asc, j.id asc for update skip locked limit 1;
  if v_job_id is null then return; end if;
  update private.hikvision_video_jobs j set status='processing',gateway_id=p_gateway_id,attempt_count=j.attempt_count+1,attempt_generation=j.attempt_generation+1,active_attempt_token=v_token,attempt_started_at=now(),last_attempt_heartbeat_at=now(),lease_until=now()+interval '3 minutes',last_error=null,updated_at=now() where j.id=v_job_id;
  update public.transaction_video_evidence e set status='processing',updated_at=now() where e.job_id=v_job_id;
  return query select j.id,j.market_id,j.source_type,j.source_id,j.transaction_at,j.channel_id,j.clip_start_at,j.clip_end_at,j.attempt_count,j.attempt_generation,j.active_attempt_token from private.hikvision_video_jobs j where j.id=v_job_id;
end; $function$
