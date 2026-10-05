-- ZHIROX Hikvision transaction-video hardening
-- Guarantees the evidence window is the real transaction creation instant
-- with 15 seconds before and 15 seconds after, using Kurdistan/Iraq time config.

update public.hikvision_market_config
set pre_seconds = 15,
    post_seconds = 15,
    timezone = 'Asia/Baghdad',
    updated_at = now()
where enabled = true;

create or replace function private.hikvision_force_transaction_clip_window()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  new.pre_seconds := 15;
  new.post_seconds := 15;
  new.timezone := 'Asia/Baghdad';
  return new;
end;
$function$;

drop trigger if exists trg_hikvision_force_transaction_clip_window on public.hikvision_market_config;
create trigger trg_hikvision_force_transaction_clip_window
before insert or update on public.hikvision_market_config
for each row execute function private.hikvision_force_transaction_clip_window();

create or replace function private.hikvision_enqueue_transaction_video()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_market_id uuid;
  v_source_type text;
  v_source_id uuid;
  v_transaction_at timestamptz;
  v_cfg public.hikvision_market_config%rowtype;
  v_job_id uuid;
begin
  if tg_table_name = 'debts' then
    v_source_type := 'debt';
    v_source_id := new.id;
    -- Camera evidence follows the real creation instant, not a manual business date.
    v_transaction_at := coalesce(new.created_at, now());
    select case when p.role = 'admin' then p.id else p.admin_id end
      into v_market_id
      from public.profiles p
      where p.id = new.customer_id;
  elsif tg_table_name = 'payments' then
    v_source_type := 'payment';
    v_source_id := new.id;
    v_transaction_at := coalesce(new.created_at, now());
    select case when p.role = 'admin' then p.id else p.admin_id end
      into v_market_id
      from public.debts d
      join public.profiles p on p.id = d.customer_id
      where d.id = new.debt_id;
  elsif tg_table_name = 'customer_general_payments' then
    v_source_type := 'general_payment';
    v_source_id := new.id;
    v_transaction_at := coalesce(new.created_at, now());
    v_market_id := new.admin_id;
  else
    return new;
  end if;

  if v_market_id is null then return new; end if;

  select * into v_cfg
  from public.hikvision_market_config c
  where c.market_id = v_market_id and c.enabled = true and c.auto_capture = true;
  if not found then return new; end if;

  insert into private.hikvision_video_jobs (
    market_id, source_type, source_id, transaction_at, channel_id,
    clip_start_at, clip_end_at, status
  ) values (
    v_market_id, v_source_type, v_source_id, v_transaction_at, v_cfg.cashier_channel_id,
    v_transaction_at - interval '15 seconds',
    v_transaction_at + interval '15 seconds',
    'queued'
  )
  on conflict (source_type, source_id) do nothing
  returning id into v_job_id;

  if v_job_id is not null then
    insert into public.transaction_video_evidence (
      market_id, job_id, source_type, source_id, channel_id, transaction_at,
      clip_start_at, clip_end_at, status
    ) values (
      v_market_id, v_job_id, v_source_type, v_source_id, v_cfg.cashier_channel_id, v_transaction_at,
      v_transaction_at - interval '15 seconds',
      v_transaction_at + interval '15 seconds', 'queued'
    ) on conflict (source_type, source_id) do nothing;
  end if;

  return new;
end;
$function$;

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
begin
  if p_source_type not in ('debt','payment','general_payment') then
    return jsonb_build_object('ok',false,'reason','invalid_transaction');
  end if;

  select * into v_job
  from private.hikvision_video_jobs j
  where j.market_id=p_market_id and j.source_type=p_source_type and j.source_id=p_source_id
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
    select d.created_at into v_transaction_at from public.debts d where d.id=p_source_id;
  elsif p_source_type = 'payment' then
    select p.created_at into v_transaction_at from public.payments p where p.id=p_source_id;
  else
    select gp.created_at into v_transaction_at from public.customer_general_payments gp where gp.id=p_source_id;
  end if;
  v_transaction_at := coalesce(v_transaction_at, v_job.transaction_at);

  select to_jsonb(e) into v_previous
  from public.transaction_video_evidence e
  where e.job_id=v_job.id
  for update;

  update private.hikvision_video_jobs j set
    transaction_at=v_transaction_at,
    clip_start_at=v_transaction_at - interval '15 seconds',
    clip_end_at=v_transaction_at + interval '15 seconds',
    status='queued',gateway_id=null,lease_until=null,active_attempt_token=null,
    attempt_generation=j.attempt_generation+1,
    max_attempts=least(30,greatest(j.max_attempts,j.attempt_count+8)),
    run_after=now(),completed_at=null,last_error=null,
    rebuild_requested_at=now(),rebuild_request_count=j.rebuild_request_count+1,
    rebuild_previous_evidence=case when v_previous->>'status'='ready' then v_previous else j.rebuild_previous_evidence end,
    updated_at=now()
  where j.id=v_job.id;

  update public.transaction_video_evidence set
    transaction_at=v_transaction_at,
    clip_start_at=v_transaction_at - interval '15 seconds',
    clip_end_at=v_transaction_at + interval '15 seconds',
    status='queued',object_path=null,thumbnail_path=null,
    content_sha256=null,byte_size=null,duration_seconds=null,
    captured_at=null,updated_at=now()
  where job_id=v_job.id;

  return jsonb_build_object(
    'ok',true,'queued',true,'already_requested',false,
    'transaction_at',v_transaction_at,
    'clip_start_at',v_transaction_at - interval '15 seconds',
    'clip_end_at',v_transaction_at + interval '15 seconds',
    'timezone','Asia/Baghdad'
  );
end;
$function$;

create or replace function private.fail_hikvision_video_job_v2(
  p_gateway_id uuid,
  p_job_id uuid,
  p_attempt_token uuid,
  p_error text,
  p_missing boolean default false
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
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
  set status = case when v_status = 'retrying' then 'processing' else v_status end,
      updated_at = now()
  where e.job_id = p_job_id;

  return true;
end;
$function$;

create or replace function public.hikvision_gateway_complete_v2_service(
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
begin
  -- Only expose clips that are effectively the requested 30-second evidence window.
  if p_duration_seconds is null
     or p_duration_seconds < 28
     or p_duration_seconds > 32
     or p_byte_size is null
     or p_byte_size < 20000
     or coalesce((p_playback_metadata->>'exact_trim')::boolean,false) is not true then
    perform private.fail_hikvision_video_job_v2(
      p_gateway_id,p_job_id,p_attempt_token,
      'clip_quality_gate_failed:duration=' || coalesce(p_duration_seconds::text,'null') ||
      ';bytes=' || coalesce(p_byte_size::text,'null') ||
      ';exact_trim=' || coalesce(p_playback_metadata->>'exact_trim','null'),
      false
    );
    return false;
  end if;

  return private.complete_hikvision_video_job_v2(
    p_gateway_id,p_job_id,p_attempt_token,p_object_path,p_thumbnail_path,
    p_content_sha256,p_byte_size,p_duration_seconds,p_playback_metadata
  );
end;
$function$;

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
      g.gateway_version ~ '^(1\\.(2|[3-9]|[1-9][0-9]+)\\.|[2-9]\\.)',false),
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