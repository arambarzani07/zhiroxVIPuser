create or replace function public.hikvision_video_rebuild_service(
  p_market_id uuid,
  p_source_type text,
  p_source_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_job private.hikvision_video_jobs%rowtype;
  v_previous jsonb;
  v_transaction_at timestamptz;
  v_current_channel integer;
  v_target_channel integer;
  v_channel_rebound boolean := false;
begin
  if p_source_type not in ('debt','payment','general_payment') then
    return jsonb_build_object('ok',false,'reason','invalid_transaction');
  end if;

  select * into v_job
  from private.hikvision_video_jobs j
  where j.market_id=p_market_id
    and j.source_type=p_source_type
    and j.source_id=p_source_id
  for update;
  if not found then
    return jsonb_build_object('ok',false,'reason','video_not_found');
  end if;

  if v_job.status in ('queued','retrying','processing','uploading') then
    return jsonb_build_object('ok',true,'queued',true,'already_requested',true);
  end if;

  if not coalesce((private.hikvision_rebuild_status(p_market_id,p_source_type,p_source_id)->>'can_rebuild')::boolean,false) then
    return jsonb_build_object('ok',false,'reason','updated_gateway_required_or_cooldown');
  end if;

  if p_source_type = 'debt' then
    select d.created_at into v_transaction_at
    from public.debts d where d.id=p_source_id;
  elsif p_source_type = 'payment' then
    select p.created_at into v_transaction_at
    from public.payments p where p.id=p_source_id;
  else
    select gp.created_at into v_transaction_at
    from public.customer_general_payments gp where gp.id=p_source_id;
  end if;
  v_transaction_at := coalesce(v_transaction_at, v_job.transaction_at);

  select to_jsonb(e) into v_previous
  from public.transaction_video_evidence e
  where e.job_id=v_job.id
  for update;

  v_target_channel := v_job.channel_id;
  if v_job.status in ('failed','missing') then
    select c.cashier_channel_id into v_current_channel
    from public.hikvision_market_config c
    where c.market_id=p_market_id
      and c.enabled=true
      and c.auto_capture=true
      and c.capture_provider='local_gateway';

    if v_current_channel is not null and v_current_channel <> v_job.channel_id then
      v_target_channel := v_current_channel;
      v_channel_rebound := true;
    end if;
  end if;

  update private.hikvision_video_jobs j set
    transaction_at=v_transaction_at,
    channel_id=v_target_channel,
    clip_start_at=v_transaction_at - interval '15 seconds',
    clip_end_at=v_transaction_at + interval '15 seconds',
    status='queued',
    gateway_id=null,
    lease_until=null,
    active_attempt_token=null,
    attempt_generation=j.attempt_generation+1,
    max_attempts=least(30,greatest(j.max_attempts,j.attempt_count+8)),
    run_after=now(),
    completed_at=null,
    last_error=null,
    rebuild_requested_at=now(),
    rebuild_request_count=j.rebuild_request_count+1,
    rebuild_previous_evidence=case
      when v_previous->>'status'='ready' then v_previous
      when v_channel_rebound then
        coalesce(j.rebuild_previous_evidence,'{}'::jsonb) || jsonb_build_object(
          'stale_channel_recovery',jsonb_build_object(
            'previous_channel_id',v_job.channel_id,
            'new_channel_id',v_target_channel,
            'previous_evidence',v_previous,
            'rebound_at',now()
          )
        )
      else j.rebuild_previous_evidence
    end,
    updated_at=now()
  where j.id=v_job.id;

  update public.transaction_video_evidence set
    transaction_at=v_transaction_at,
    channel_id=v_target_channel,
    clip_start_at=v_transaction_at - interval '15 seconds',
    clip_end_at=v_transaction_at + interval '15 seconds',
    status='queued',
    object_path=null,
    thumbnail_path=null,
    content_sha256=null,
    byte_size=null,
    duration_seconds=null,
    captured_at=null,
    updated_at=now()
  where job_id=v_job.id;

  return jsonb_build_object(
    'ok',true,
    'queued',true,
    'already_requested',false,
    'transaction_at',v_transaction_at,
    'clip_start_at',v_transaction_at - interval '15 seconds',
    'clip_end_at',v_transaction_at + interval '15 seconds',
    'channel_id',v_target_channel,
    'channel_rebound',v_channel_rebound,
    'previous_channel_id',case when v_channel_rebound then v_job.channel_id else null end,
    'timezone','Asia/Baghdad'
  );
end;
$function$;
