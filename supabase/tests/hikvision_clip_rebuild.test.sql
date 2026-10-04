begin;
create extension if not exists pgtap with schema extensions;
select plan(5);
select ok(not has_function_privilege('anon','public.hikvision_video_rebuild_service(uuid,text,uuid)','EXECUTE'),'anonymous cannot rebuild');
select ok(not has_function_privilege('authenticated','public.hikvision_video_rebuild_service(uuid,text,uuid)','EXECUTE'),'clients cannot choose a market and rebuild directly');
select ok(has_function_privilege('service_role','public.hikvision_video_rebuild_service(uuid,text,uuid)','EXECUTE'),'authenticated-admin Edge service can rebuild');
select ok(not has_function_privilege('authenticated','public.hikvision_video_rebuild_status_service(uuid,text,uuid)','EXECUTE'),'private job status stays server-only');
do $test$
declare
 m uuid:='00000000-0000-0000-0000-00000000b101';
 other uuid:='00000000-0000-0000-0000-00000000b102';
 g uuid:='00000000-0000-0000-0000-00000000b103';
 j uuid:='00000000-0000-0000-0000-00000000b104';
 source uuid:='00000000-0000-0000-0000-00000000b105';
 token uuid:=gen_random_uuid(); result jsonb; state record;
begin
 insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 values(m,'authenticated','authenticated','hik-rebuild@test.local','',now(),'{}','{}',now(),now());
 insert into public.profiles(id,name,phone,role,market_name,admin_id,created_by,approved,active,subscription_end)
 values(m,'Rebuild','rebuild-test','admin','Rebuild',null,m,true,true,now()+interval '30 days');
 insert into public.hikvision_market_config(market_id,enabled,auto_capture,nvr_host,cashier_channel_id) values(m,true,true,'192.168.1.3',10);
 insert into private.hikvision_gateways(id,market_id,label,active,gateway_version,platform,last_seen_at) values(g,m,'test',true,'1.1.0','windows',now());
 insert into private.hikvision_video_jobs(id,market_id,source_type,source_id,transaction_at,channel_id,clip_start_at,clip_end_at,status,gateway_id,attempt_count,attempt_generation,active_attempt_token)
 values(j,m,'debt',source,now()-interval '1 day',10,now()-interval '1 day 15 seconds',now()-interval '23 hours 59 minutes 45 seconds','ready',g,2,2,token);
 insert into public.transaction_video_evidence(market_id,job_id,source_type,source_id,channel_id,transaction_at,clip_start_at,clip_end_at,status,object_path)
 select m,id,source_type,source_id,10,transaction_at,clip_start_at,clip_end_at,'ready','old-private.mp4' from private.hikvision_video_jobs where id=j;
 result:=public.hikvision_video_rebuild_service(other,'debt',source);
 if result->>'reason'<>'video_not_found' then raise exception 'cross-market rebuild allowed'; end if;
 result:=public.hikvision_video_rebuild_service(m,'debt',source);
 if result->>'ok'<>'false' then raise exception 'old gateway allowed'; end if;
 update private.hikvision_gateways set gateway_version='1.2.0+osd-1',last_seen_at=now()-interval '10 minutes' where id=g;
 if (public.hikvision_video_rebuild_status_service(m,'debt',source)->>'can_rebuild')::boolean then raise exception 'offline gateway allowed'; end if;
 update private.hikvision_gateways set last_seen_at=now() where id=g;
 result:=public.hikvision_video_rebuild_service(m,'debt',source);
 if result->>'ok'<>'true' then raise exception 'fresh updated gateway refused'; end if;
 select * into state from private.hikvision_video_jobs where id=j;
 if state.status<>'queued' or state.active_attempt_token is not null or state.gateway_id is not null or state.attempt_count<>2 or state.attempt_generation<=2 or state.max_attempts<10 then raise exception 'rebuild did not fence old attempts'; end if;
 if state.rebuild_previous_evidence->>'object_path'<>'old-private.mp4' then raise exception 'previous clip snapshot lost'; end if;
 result:=public.hikvision_video_rebuild_service(m,'debt',source);
 if result->>'already_requested'<>'true' then raise exception 'duplicate requests are not idempotent'; end if;
 if (select rebuild_request_count from private.hikvision_video_jobs where id=j)<>1 then raise exception 'repeated request counted twice'; end if;
 update private.hikvision_video_jobs set status='ready' where id=j;
 if (public.hikvision_video_rebuild_status_service(m,'debt',source)->>'can_rebuild')::boolean then raise exception 'cooldown ignored'; end if;
end;
$test$;
select pass('rebuild scopes tenant, requires active updated gateway, preserves evidence and fences attempts');
select * from finish();
rollback;
