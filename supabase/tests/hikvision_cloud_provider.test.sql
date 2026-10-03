begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

select has_column('public','hikvision_market_config','capture_provider','market config has capture provider');
select has_column('public','hikvision_market_config','hikconnect_camera_id','market config has Hik-Connect camera id');
select has_column('private','hikvision_video_jobs','provider','video jobs keep provider');
select has_column('private','hikvision_video_jobs','cloud_task_id','video jobs keep cloud task id');
select ok(to_regprocedure('public.hikvision_cloud_claim_service()') is not null,'cloud claim service exists');
select ok(to_regprocedure('public.hikvision_cloud_credentials_set_service(uuid,text,text,text)') is not null,'cloud credential service exists');
select ok(not has_function_privilege('authenticated','public.hikvision_cloud_credentials_get_service(uuid)','EXECUTE'),'signed-in clients cannot read cloud credentials');
select ok(not has_function_privilege('anon','public.hikvision_cloud_worker_auth_service(text)','EXECUTE'),'anonymous clients cannot call worker auth RPC');
select ok(has_function_privilege('service_role','public.hikvision_cloud_claim_service()','EXECUTE'),'service role can claim cloud jobs');
select ok((select count(*)=1 from cron.job where jobname='zhirox-hikvision-cloud-worker' and active),'one active Hik-Connect cloud worker cron exists');

do $test$
declare
  v_admin uuid := '00000000-0000-0000-0000-00000000c101';
  v_job uuid := '00000000-0000-0000-0000-00000000c102';
  v_source uuid := '00000000-0000-0000-0000-00000000c103';
  v_ak uuid;
  v_sk uuid;
  v_claim record;
  v_claim2 record;
  v_claim3 record;
  v_bool boolean;
  v_provider text;
  v_status text;
begin
  insert into auth.users(
    id,aud,role,email,encrypted_password,email_confirmed_at,
    raw_app_meta_data,raw_user_meta_data,created_at,updated_at
  ) values (
    v_admin,'authenticated','authenticated','hik-cloud@test.local','',now(),
    '{}'::jsonb,'{}'::jsonb,now(),now()
  );

  insert into public.profiles(
    id,name,phone,role,market_name,admin_id,created_by,
    approved,active,subscription_end
  ) values (
    v_admin,'Hik Cloud Test','hik-cloud-admin','admin','Hik Cloud Test',
    null,v_admin,true,true,now()+interval '30 days'
  );

  insert into public.hikvision_market_config(
    market_id,capture_provider,hikconnect_camera_id,hikconnect_camera_name,
    hikconnect_device_serial,cashier_channel_id
  ) values (
    v_admin,'hikconnect_cloud','camera-cloud-00000001','Cashier Camera','DEVICE001',1
  );

  v_ak := vault.create_secret('test-app-key-123456','test_hik_cloud_ak_'||v_admin::text,'test');
  v_sk := vault.create_secret('test-secret-key-123456','test_hik_cloud_sk_'||v_admin::text,'test');
  insert into private.hikvision_cloud_credentials(
    market_id,server_address,app_key_secret_id,secret_key_secret_id
  ) values (
    v_admin,'https://ieu.hikcentralconnect.com',v_ak,v_sk
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

  select provider into v_provider from private.hikvision_video_jobs where id=v_job;
  if v_provider <> 'hikconnect_cloud' then
    raise exception 'provider stamp failed: %',v_provider;
  end if;

  select * into v_claim from public.hikvision_cloud_claim_service();
  if v_claim.job_id is distinct from v_job or v_claim.stage <> 'save' or v_claim.attempt_token is null then
    raise exception 'initial cloud claim failed';
  end if;

  v_bool := public.hikvision_cloud_task_started_service(v_job,v_claim.attempt_token,'task-test-1');
  if not v_bool then raise exception 'cloud task start rejected'; end if;

  update private.hikvision_video_jobs set run_after=now()-interval '1 second' where id=v_job;
  select * into v_claim2 from public.hikvision_cloud_claim_service();
  if v_claim2.job_id is distinct from v_job or v_claim2.stage <> 'poll' or v_claim2.cloud_task_id <> 'task-test-1' then
    raise exception 'cloud poll claim failed';
  end if;

  v_bool := public.hikvision_cloud_wait_service(v_job,v_claim2.attempt_token,10);
  if not v_bool then raise exception 'cloud wait rejected'; end if;

  update private.hikvision_video_jobs set run_after=now()-interval '1 second' where id=v_job;
  select * into v_claim3 from public.hikvision_cloud_claim_service();
  v_bool := public.hikvision_cloud_complete_service(
    v_job,v_claim3.attempt_token,
    v_admin::text||'/2026/10/03/cloud/debt/test.mp4',repeat('a',64),2048,45,
    '{"provider":"hikconnect_cloud"}'::jsonb
  );
  if not v_bool then raise exception 'cloud completion rejected'; end if;

  select status into v_status from private.hikvision_video_jobs where id=v_job;
  if v_status <> 'ready' then raise exception 'cloud final status is %',v_status; end if;
end;
$test$;

select ok(true,'cloud provider stamps, claims, polls and completes without a local gateway');
select ok((select count(*)=1 from private.hikvision_cloud_worker_runtime),'worker runtime secret is installed exactly once');
select * from finish();
rollback;
