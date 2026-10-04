-- Only the authenticated-admin Edge endpoint may request recorder rebuilds.
-- Keep generation/attempt counters monotonic and preserve the previous evidence
-- privately. No storage object or financial transaction is deleted here.
alter table private.hikvision_video_jobs
  add column if not exists rebuild_requested_at timestamptz,
  add column if not exists rebuild_request_count integer not null default 0,
  add column if not exists rebuild_previous_evidence jsonb;

create or replace function private.hikvision_rebuild_status(p_market_id uuid,p_source_type text,p_source_id uuid)
returns jsonb language sql security definer set search_path=''
as $$
  select jsonb_build_object(
    'can_rebuild',coalesce(
      j.status in ('ready','failed','missing') and j.attempt_count<30 and
      (j.rebuild_requested_at is null or j.rebuild_requested_at<now()-interval '1 minute') and
      c.enabled and c.capture_provider='local_gateway' and g.active and
      g.last_seen_at>now()-interval '3 minutes' and g.last_seen_at<=now()+interval '30 seconds' and
      g.gateway_version ~ '^(1\.(2|[3-9]|[1-9][0-9]+)\.|[2-9]\.)',false),
    'job_status',j.status,'requested_at',j.rebuild_requested_at,'request_count',j.rebuild_request_count)
  from private.hikvision_video_jobs j
  join public.hikvision_market_config c on c.market_id=j.market_id
  left join private.hikvision_gateways g on g.market_id=j.market_id
  where j.market_id=p_market_id and j.source_type=p_source_type and j.source_id=p_source_id;
$$;
revoke all on function private.hikvision_rebuild_status(uuid,text,uuid) from public,anon,authenticated;

create or replace function public.hikvision_video_rebuild_status_service(p_market_id uuid,p_source_type text,p_source_id uuid)
returns jsonb language sql security definer set search_path=''
as $$ select coalesce(private.hikvision_rebuild_status(p_market_id,p_source_type,p_source_id),'{}'::jsonb); $$;
revoke all on function public.hikvision_video_rebuild_status_service(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.hikvision_video_rebuild_status_service(uuid,text,uuid) to service_role;

create or replace function public.hikvision_video_rebuild_service(p_market_id uuid,p_source_type text,p_source_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_job private.hikvision_video_jobs%rowtype; v_previous jsonb;
begin
  if p_source_type not in ('debt','payment','general_payment') then
    return jsonb_build_object('ok',false,'reason','invalid_transaction');
  end if;
  select * into v_job from private.hikvision_video_jobs j
    where j.market_id=p_market_id and j.source_type=p_source_type and j.source_id=p_source_id for update;
  if not found then return jsonb_build_object('ok',false,'reason','video_not_found'); end if;
  if v_job.status in ('queued','retrying','processing','uploading') then
    return jsonb_build_object('ok',true,'queued',true,'already_requested',true);
  end if;
  if not coalesce((private.hikvision_rebuild_status(p_market_id,p_source_type,p_source_id)->>'can_rebuild')::boolean,false) then
    return jsonb_build_object('ok',false,'reason','updated_gateway_required_or_cooldown');
  end if;
  select to_jsonb(e) into v_previous from public.transaction_video_evidence e where e.job_id=v_job.id for update;
  update private.hikvision_video_jobs j set
    status='queued',gateway_id=null,lease_until=null,active_attempt_token=null,
    attempt_generation=j.attempt_generation+1,
    max_attempts=least(30,greatest(j.max_attempts,j.attempt_count+8)),
    run_after=now(),completed_at=null,last_error=null,
    rebuild_requested_at=now(),rebuild_request_count=j.rebuild_request_count+1,
    rebuild_previous_evidence=case when v_previous->>'status'='ready' then v_previous else j.rebuild_previous_evidence end,
    updated_at=now()
    where j.id=v_job.id;
  update public.transaction_video_evidence set status='queued',updated_at=now() where job_id=v_job.id;
  return jsonb_build_object('ok',true,'queued',true,'already_requested',false);
end;
$$;
revoke all on function public.hikvision_video_rebuild_service(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.hikvision_video_rebuild_service(uuid,text,uuid) to service_role;
