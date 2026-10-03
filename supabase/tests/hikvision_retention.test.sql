begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

select has_column(
  'public', 'transaction_video_evidence', 'expires_at',
  'video evidence stores a retention deadline'
);
select has_column(
  'public', 'transaction_video_evidence', 'expired_at',
  'video evidence stores physical expiry time'
);
select has_column(
  'private', 'hikvision_gateways', 'last_retention_sweep_at',
  'gateway stores retention sweep throttle state'
);

select ok(
  to_regprocedure('public.hikvision_gateway_retention_due_service(uuid)') is not null,
  'retention throttle service exists'
);
select ok(
  to_regprocedure('public.hikvision_retention_candidates_service(uuid,integer)') is not null,
  'retention candidate service exists'
);
select ok(
  to_regprocedure('public.hikvision_mark_video_expired_service(uuid,uuid,text)') is not null,
  'retention expiry service exists'
);

select ok(
  not has_function_privilege(
    'anon', 'public.hikvision_retention_candidates_service(uuid,integer)', 'EXECUTE'
  ),
  'anonymous clients cannot enumerate retention candidates'
);
select ok(
  not has_function_privilege(
    'authenticated', 'public.hikvision_mark_video_expired_service(uuid,uuid,text)', 'EXECUTE'
  ),
  'signed-in clients cannot mark video evidence expired directly'
);
select ok(
  has_function_privilege(
    'service_role', 'public.hikvision_gateway_retention_due_service(uuid)', 'EXECUTE'
  ),
  'service role can run the throttled retention sweep'
);

do $test$
declare
  v_admin uuid := '00000000-0000-0000-0000-00000000b101';
  v_gateway uuid := '00000000-0000-0000-0000-00000000b102';
  v_job uuid := '00000000-0000-0000-0000-00000000b103';
  v_source uuid := '00000000-0000-0000-0000-00000000b104';
  v_evidence uuid := '00000000-0000-0000-0000-00000000b105';
  v_path text;
  v_expires timestamptz;
  v_expired timestamptz;
  v_status text;
  v_object text;
  v_bool boolean;
  v_count integer;
begin
  insert into auth.users(
    id,aud,role,email,encrypted_password,email_confirmed_at,
    raw_app_meta_data,raw_user_meta_data,created_at,updated_at
  ) values (
    v_admin,'authenticated','authenticated','hik-retention@test.local','',now(),
    '{}'::jsonb,'{}'::jsonb,now(),now()
  );

  insert into public.profiles(
    id,name,phone,role,market_name,admin_id,created_by,
    approved,active,subscription_end
  ) values (
    v_admin,'Hikvision Retention Test','hik-retention-admin','admin',
    'Hikvision Retention Test',null,v_admin,true,true,now()+interval '30 days'
  );

  insert into public.hikvision_market_config(
    market_id,enabled,auto_capture,retention_days
  ) values (v_admin,true,true,1);

  insert into private.hikvision_gateways(
    id,market_id,label,active,gateway_version,platform
  ) values (
    v_gateway,v_admin,'Retention test gateway',true,'1.1.0','test'
  );

  insert into private.hikvision_video_jobs(
    id,market_id,source_type,source_id,transaction_at,channel_id,
    clip_start_at,clip_end_at,status,gateway_id,attempt_count
  ) values (
    v_job,v_admin,'debt',v_source,now()-interval '5 minutes',1,
    now()-interval '6 minutes',now()-interval '4 minutes',
    'processing',v_gateway,1
  );

  insert into public.transaction_video_evidence(
    id,market_id,job_id,source_type,source_id,channel_id,transaction_at,
    clip_start_at,clip_end_at,status
  ) values (
    v_evidence,v_admin,v_job,'debt',v_source,1,now()-interval '5 minutes',
    now()-interval '6 minutes',now()-interval '4 minutes','processing'
  );

  v_path := v_admin::text || '/2026/10/03/debt/' || v_source::text || '-' || v_job::text || '.mp4';

  v_bool := private.complete_hikvision_video_job(
    v_gateway,v_job,v_path,null,repeat('b',64),2048,60,
    '{"provider":"retention-test"}'::jsonb
  );
  if not v_bool then
    raise exception 'legacy fenced completion did not succeed in retention test';
  end if;

  select e.expires_at into v_expires
  from public.transaction_video_evidence e
  where e.id=v_evidence;
  if v_expires is null
     or v_expires < now()+interval '23 hours'
     or v_expires > now()+interval '25 hours' then
    raise exception 'completion did not apply the 1-day retention deadline: %', v_expires;
  end if;

  v_bool := public.hikvision_gateway_retention_due_service(v_gateway);
  if not v_bool then
    raise exception 'first retention sweep was not due';
  end if;
  v_bool := public.hikvision_gateway_retention_due_service(v_gateway);
  if v_bool then
    raise exception 'retention sweep throttle allowed an immediate duplicate sweep';
  end if;

  update public.transaction_video_evidence
  set expires_at=now()-interval '1 second'
  where id=v_evidence;

  select count(*)::integer into v_count
  from public.hikvision_retention_candidates_service(v_admin,20)
  where evidence_id=v_evidence and object_path=v_path;
  if v_count <> 1 then
    raise exception 'expired ready video was not returned as one retention candidate';
  end if;

  v_bool := public.hikvision_mark_video_expired_service(
    v_admin,v_evidence,'wrong/path.mp4'
  );
  if v_bool then
    raise exception 'wrong object path was allowed to expire evidence';
  end if;

  v_bool := public.hikvision_mark_video_expired_service(
    v_admin,v_evidence,v_path
  );
  if not v_bool then
    raise exception 'correct expired evidence could not be marked expired';
  end if;

  select e.status,e.object_path,e.expired_at
    into v_status,v_object,v_expired
  from public.transaction_video_evidence e
  where e.id=v_evidence;
  if v_status <> 'expired' or v_object is not null or v_expired is null then
    raise exception 'expired evidence did not preserve metadata while clearing storage paths';
  end if;
end;
$test$;

select ok(true,
  'retention deadlines, throttle, candidate fencing, and expiry transition work end-to-end'
);

select * from finish();
rollback;
