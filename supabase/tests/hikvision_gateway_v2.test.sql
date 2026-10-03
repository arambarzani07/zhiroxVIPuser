begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

select has_column(
  'private', 'hikvision_video_jobs', 'active_attempt_token',
  'Hikvision jobs keep the active v2 attempt token'
);
select has_column(
  'private', 'hikvision_video_jobs', 'attempt_generation',
  'Hikvision jobs keep a monotonic attempt generation'
);
select has_column(
  'private', 'hikvision_video_jobs', 'attempt_started_at',
  'Hikvision jobs keep attempt start time'
);
select has_column(
  'private', 'hikvision_video_jobs', 'last_attempt_heartbeat_at',
  'Hikvision jobs keep the latest attempt heartbeat'
);

select ok(
  to_regprocedure('public.hikvision_gateway_claim_v2_service(uuid)') is not null,
  'v2 claim service exists'
);
select ok(
  to_regprocedure('public.hikvision_gateway_job_heartbeat_v2_service(uuid,uuid,uuid)') is not null,
  'v2 job heartbeat service exists'
);
select ok(
  to_regprocedure('public.hikvision_gateway_prepare_upload_v2_service(uuid,uuid,uuid)') is not null,
  'v2 upload preparation service exists'
);
select ok(
  to_regprocedure('public.hikvision_gateway_complete_v2_service(uuid,uuid,uuid,text,text,text,bigint,integer,jsonb)') is not null,
  'v2 completion service exists'
);
select ok(
  to_regprocedure('public.hikvision_gateway_fail_v2_service(uuid,uuid,uuid,text,boolean)') is not null,
  'v2 failure service exists'
);

select ok(
  not has_function_privilege(
    'anon', 'public.hikvision_gateway_claim_v2_service(uuid)', 'EXECUTE'
  ),
  'anonymous clients cannot claim Hikvision jobs'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.hikvision_gateway_complete_v2_service(uuid,uuid,uuid,text,text,text,bigint,integer,jsonb)',
    'EXECUTE'
  ),
  'signed-in clients cannot complete Hikvision jobs directly'
);
select ok(
  has_function_privilege(
    'service_role', 'public.hikvision_gateway_claim_v2_service(uuid)', 'EXECUTE'
  ),
  'service role can claim Hikvision jobs'
);

do $test$
declare
  v_admin uuid := '00000000-0000-0000-0000-00000000a101';
  v_gateway uuid := '00000000-0000-0000-0000-00000000a102';
  v_job uuid := '00000000-0000-0000-0000-00000000a103';
  v_source uuid := '00000000-0000-0000-0000-00000000a104';
  v_first record;
  v_second record;
  v_old_token uuid;
  v_new_token uuid;
  v_bool boolean;
  v_count integer;
  v_status text;
  v_token uuid;
  v_generation bigint;
  v_object_path text;
begin
  insert into auth.users(
    id,aud,role,email,encrypted_password,email_confirmed_at,
    raw_app_meta_data,raw_user_meta_data,created_at,updated_at
  ) values (
    v_admin,'authenticated','authenticated','hik-v2@test.local','',now(),
    '{}'::jsonb,'{}'::jsonb,now(),now()
  );

  insert into public.profiles(
    id,name,phone,role,market_name,admin_id,created_by,
    approved,active,subscription_end
  ) values (
    v_admin,'Hikvision V2 Test','hik-v2-admin','admin','Hikvision V2 Test',
    null,v_admin,true,true,now()+interval '30 days'
  );

  insert into private.hikvision_gateways(
    id,market_id,label,active,gateway_version,platform
  ) values (
    v_gateway,v_admin,'V2 test gateway',true,'1.1.0','test'
  );

  insert into private.hikvision_video_jobs(
    id,market_id,source_type,source_id,transaction_at,channel_id,
    clip_start_at,clip_end_at,status,run_after
  ) values (
    v_job,v_admin,'debt',v_source,now()-interval '10 minutes',1,
    now()-interval '11 minutes',now()-interval '1 minute','queued',now()-interval '1 minute'
  );

  insert into public.transaction_video_evidence(
    market_id,job_id,source_type,source_id,channel_id,transaction_at,
    clip_start_at,clip_end_at,status
  ) values (
    v_admin,v_job,'debt',v_source,1,now()-interval '10 minutes',
    now()-interval '11 minutes',now()-interval '1 minute','queued'
  );

  select * into v_first
  from private.claim_hikvision_video_job_v2(v_gateway);

  if v_first.job_id is distinct from v_job
     or v_first.attempt_token is null
     or v_first.attempt_generation <> 1 then
    raise exception 'first v2 claim did not establish generation 1 token fencing';
  end if;
  v_old_token := v_first.attempt_token;

  v_bool := private.heartbeat_hikvision_video_job_v2(
    v_gateway,v_job,gen_random_uuid()
  );
  if v_bool then
    raise exception 'wrong attempt token refreshed a lease';
  end if;

  v_bool := private.heartbeat_hikvision_video_job_v2(
    v_gateway,v_job,v_old_token
  );
  if not v_bool then
    raise exception 'active attempt token failed to refresh a lease';
  end if;

  update private.hikvision_video_jobs
  set lease_until=now()-interval '1 second'
  where id=v_job;

  v_count := private.recover_stale_hikvision_video_jobs(v_admin);
  if v_count <> 1 then
    raise exception 'stale lease recovery count was %, expected 1', v_count;
  end if;

  select j.status,j.active_attempt_token into v_status,v_token
  from private.hikvision_video_jobs j
  where j.id=v_job;
  if v_status <> 'retrying' or v_token is not null then
    raise exception 'stale lease was not safely requeued';
  end if;

  update private.hikvision_video_jobs
  set run_after=now()-interval '1 second'
  where id=v_job;

  select * into v_second
  from private.claim_hikvision_video_job_v2(v_gateway);

  if v_second.job_id is distinct from v_job
     or v_second.attempt_token is null
     or v_second.attempt_token = v_old_token
     or v_second.attempt_generation <> 2 then
    raise exception 'second v2 claim did not rotate token/generation';
  end if;
  v_new_token := v_second.attempt_token;

  v_bool := public.hikvision_gateway_complete_service(
    v_gateway,v_job,'legacy/should-not-win.mp4',null,null,null,null,'{}'::jsonb
  );
  if v_bool then
    raise exception 'legacy completion overwrote a token-fenced v2 attempt';
  end if;

  v_bool := private.complete_hikvision_video_job_v2(
    v_gateway,v_job,v_old_token,'stale/should-not-win.mp4',null,null,null,null,'{}'::jsonb
  );
  if v_bool then
    raise exception 'stale v2 token completed the newer attempt';
  end if;

  select count(*)::integer into v_count
  from private.prepare_hikvision_video_upload_v2(v_gateway,v_job,v_new_token);
  if v_count <> 1 then
    raise exception 'active v2 attempt could not enter upload state';
  end if;

  v_object_path := v_admin::text || '/2026/10/03/debt/' || v_source::text || '-' || v_job::text || '-a2.mp4';
  v_bool := private.complete_hikvision_video_job_v2(
    v_gateway,v_job,v_new_token,v_object_path,null,repeat('a',64),1234,45,
    '{"provider":"test"}'::jsonb
  );
  if not v_bool then
    raise exception 'active v2 attempt could not complete';
  end if;

  v_bool := private.complete_hikvision_video_job_v2(
    v_gateway,v_job,v_new_token,v_object_path,null,repeat('a',64),1234,45,
    '{"provider":"test"}'::jsonb
  );
  if not v_bool then
    raise exception 'idempotent completion replay was rejected';
  end if;

  select j.status,j.attempt_generation,e.object_path
    into v_status,v_generation,v_object_path
  from private.hikvision_video_jobs j
  join public.transaction_video_evidence e on e.job_id=j.id
  where j.id=v_job;

  if v_status <> 'ready' or v_generation <> 2 or v_object_path is null then
    raise exception 'final fenced job/evidence state is not ready';
  end if;
end;
$test$;

select ok(true,
  'v2 attempt fencing rejects stale workers, renews leases, recovers stale jobs, and completes idempotently'
);

select * from finish();
rollback;
