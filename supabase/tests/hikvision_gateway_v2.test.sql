begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

select has_column('private','hikvision_video_jobs','active_attempt_token',
  'Hikvision jobs carry an active attempt token');
select has_column('private','hikvision_video_jobs','attempt_generation',
  'Hikvision jobs carry an attempt generation');
select ok(to_regprocedure('public.hikvision_gateway_claim_v2_service(uuid)') is not null,
  'v2 claim service exists');
select ok(to_regprocedure('public.hikvision_gateway_job_heartbeat_v2_service(uuid,uuid,uuid)') is not null,
  'v2 job heartbeat service exists');
select ok(to_regprocedure('public.hikvision_gateway_complete_v2_service(uuid,uuid,uuid,text,text,text,bigint,integer,jsonb)') is not null,
  'v2 complete service exists');
select ok(not has_function_privilege('anon','public.hikvision_gateway_claim_v2_service(uuid)','EXECUTE'),
  'anonymous clients cannot claim camera jobs');
select ok(not has_function_privilege('authenticated','public.hikvision_gateway_claim_v2_service(uuid)','EXECUTE'),
  'signed-in app clients cannot claim camera jobs');
select ok(position('active_attempt_token is null' in lower(pg_get_functiondef(
  'public.hikvision_gateway_prepare_upload_service(uuid,uuid)'::regprocedure))) > 0,
  'legacy upload preparation is fenced from v2 attempts');
select ok(position('active_attempt_token is not null' in lower(pg_get_functiondef(
  'public.hikvision_gateway_complete_service(uuid,uuid,text,text,text,bigint,integer,jsonb)'::regprocedure))) > 0,
  'legacy completion is fenced from v2 attempts');
select is((select count(*)::bigint from storage.buckets
  where id='transaction-camera-clips' and public=false), 1::bigint,
  'transaction camera bucket remains private');
select is((select count(*)::bigint from pg_indexes
  where schemaname='private' and indexname='hikvision_video_jobs_active_lease_idx'), 1::bigint,
  'active Hikvision leases have a recovery index');

do $test$
declare
  admin_id uuid := '00000000-0000-0000-0000-00000000a901';
  gateway_id uuid := '00000000-0000-0000-0000-00000000a902';
  job_id uuid := '00000000-0000-0000-0000-00000000a903';
  source_id uuid := '00000000-0000-0000-0000-00000000a904';
  token_1 uuid;
  token_2 uuid;
  claimed record;
  prepared record;
  result boolean;
begin
  insert into auth.users(
    id,aud,role,email,encrypted_password,email_confirmed_at,
    raw_app_meta_data,raw_user_meta_data,created_at,updated_at
  ) values (
    admin_id,'authenticated','authenticated','hikvision-v2@test.local','',now(),
    '{}','{}',now(),now()
  );

  insert into public.profiles(
    id,name,phone,role,market_name,admin_id,created_by,
    approved,active,subscription_end
  ) values (
    admin_id,'Hikvision Test Market','hik-v2-admin','admin','Hikvision Test Market',
    null,admin_id,true,true,now()+interval '30 days'
  );

  insert into private.hikvision_gateways(id,market_id,label,active)
  values (gateway_id,admin_id,'test-gateway',true);

  insert into private.hikvision_video_jobs(
    id,market_id,source_type,source_id,transaction_at,channel_id,
    clip_start_at,clip_end_at,status,run_after
  ) values (
    job_id,admin_id,'debt',source_id,now()-interval '40 seconds',1,
    now()-interval '70 seconds',now()-interval '10 seconds','queued',now()-interval '1 second'
  );

  insert into public.transaction_video_evidence(
    market_id,job_id,source_type,source_id,channel_id,transaction_at,
    clip_start_at,clip_end_at,status
  ) values (
    admin_id,job_id,'debt',source_id,1,now()-interval '40 seconds',
    now()-interval '70 seconds',now()-interval '10 seconds','queued'
  );

  select * into claimed from public.hikvision_gateway_claim_v2_service(gateway_id);
  token_1 := claimed.attempt_token;
  if token_1 is null then raise exception 'first v2 claim did not return a token'; end if;

  update private.hikvision_video_jobs
  set lease_until=now()-interval '1 second'
  where id=job_id;

  if private.recover_stale_hikvision_video_jobs(admin_id) <> 1 then
    raise exception 'stale v2 attempt was not recovered';
  end if;

  update private.hikvision_video_jobs
  set run_after=now()-interval '1 second'
  where id=job_id;

  select * into claimed from public.hikvision_gateway_claim_v2_service(gateway_id);
  token_2 := claimed.attempt_token;
  if token_2 is null or token_2 = token_1 then
    raise exception 'reclaimed attempt did not rotate fencing token';
  end if;

  select public.hikvision_gateway_complete_v2_service(
    p_gateway_id=>gateway_id,
    p_job_id=>job_id,
    p_attempt_token=>token_1,
    p_object_path=>admin_id::text||'/stale.mp4'
  ) into result;
  if result then raise exception 'stale attempt was able to complete newer work'; end if;

  select public.hikvision_gateway_job_heartbeat_v2_service(
    gateway_id,job_id,token_2
  ) into result;
  if not result then raise exception 'current attempt heartbeat was rejected'; end if;

  select * into prepared from public.hikvision_gateway_prepare_upload_v2_service(
    gateway_id,job_id,token_2
  );
  if prepared.attempt_generation <> 2 then
    raise exception 'attempt generation did not advance to 2';
  end if;

  select public.hikvision_gateway_complete_v2_service(
    p_gateway_id=>gateway_id,
    p_job_id=>job_id,
    p_attempt_token=>token_2,
    p_object_path=>admin_id::text||'/ready.mp4',
    p_content_sha256=>repeat('a',64),
    p_byte_size=>1234,
    p_duration_seconds=>60,
    p_playback_metadata=>'{}'::jsonb
  ) into result;
  if not result then raise exception 'current attempt could not complete'; end if;

  if not exists (
    select 1 from public.transaction_video_evidence
    where job_id=job_id and status='ready'
      and object_path=admin_id::text||'/ready.mp4'
  ) then
    raise exception 'winning evidence was not persisted';
  end if;
end;
$test$;
select ok(true, 'stale worker is fenced and current attempt completes successfully');

select * from finish();
rollback;
