begin;
create extension if not exists pgtap with schema extensions;
select plan(6);
select ok(not has_function_privilege('anon','public.hikvision_gateway_health_service(uuid)','EXECUTE'),'anonymous cannot read gateway health');
select ok(not has_function_privilege('authenticated','public.hikvision_gateway_alerts_setting_service(uuid,boolean)','EXECUTE'),'clients cannot choose another market');
select ok(has_function_privilege('service_role','public.hikvision_gateway_health_service(uuid)','EXECUTE'),'admin Edge can read health');
select ok(not has_function_privilege('authenticated','private.sweep_hikvision_gateway_health()','EXECUTE'),'clients cannot run global monitor');
select ok((select relrowsecurity from pg_class where oid='private.hikvision_gateway_health_events'::regclass),'private history has RLS');
do $test$
declare
 m uuid:='00000000-0000-0000-0000-00000000c201';
 g uuid:='00000000-0000-0000-0000-00000000c202';
 other uuid:='00000000-0000-0000-0000-00000000c203';
 result jsonb; n integer;
begin
 insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 values(m,'authenticated','authenticated','gateway-health@test.local','',now(),'{}','{}',now(),now());
 insert into public.profiles(id,name,phone,role,market_name,admin_id,created_by,approved,active,subscription_end)
 values(m,'Health','health-test','admin','Health',null,m,true,true,now()+interval '30 days');
 insert into public.hikvision_market_config(market_id,enabled,auto_capture,nvr_host,cashier_channel_id) values(m,true,true,'192.168.1.3',10);
 insert into private.hikvision_gateways(id,market_id,label,active,token_sha256,last_seen_at,created_at) values(g,m,'health-test',true,repeat('0',64),now(),now()-interval '1 day');
 perform public.hikvision_gateway_alerts_setting_service(m,true);
 if (select state from private.hikvision_gateway_health where gateway_id=g)<>'online' then raise exception 'baseline not online'; end if;
 if exists(select 1 from private.hikvision_gateway_health_events where market_id=m) then raise exception 'baseline emitted recovery'; end if;
 update private.hikvision_gateways set last_seen_at=now()-interval '180 seconds' where id=g;
 if public.hikvision_gateway_health_service(m)->>'status'<>'online' then raise exception 'threshold early'; end if;
 update private.hikvision_gateways set last_seen_at=now()-interval '181 seconds' where id=g;
 perform private.evaluate_hikvision_gateway_health(g);
 if (select count(*) from private.hikvision_gateway_health_events where market_id=m)<>1 then raise exception 'offline not deduplicated'; end if;
 if (select count(*) from public.app_realtime_notifications where recipient_user_id=m and event_type='hikvision_gateway_offline')<>1 then raise exception 'wrong offline recipient/count'; end if;
 if public.hikvision_gateway_health_service(m)->>'status'<>'offline' then raise exception 'stale heartbeat not offline'; end if;
 if public.hikvision_gateway_health_service(other) is not null then raise exception 'cross tenant history exposed'; end if;
 update private.hikvision_gateways set last_seen_at=now() where id=g;
 update private.hikvision_gateways set last_seen_at=now() where id=g;
 if (select count(*) from private.hikvision_gateway_health_events where market_id=m)<>2 then raise exception 'recovery missing/duplicate'; end if;
 if (select count(*) from public.app_realtime_notifications where recipient_user_id=m and event_type='hikvision_gateway_online')<>1 then raise exception 'recovery alert missing/duplicate'; end if;
 perform public.hikvision_gateway_alerts_setting_service(m,false);
 update private.hikvision_gateways set last_seen_at=now()-interval '10 minutes' where id=g;
 if (select count(*) from private.hikvision_gateway_health_events where market_id=m)<>2 then raise exception 'disabled alerts emitted'; end if;
 perform public.hikvision_gateway_alerts_setting_service(m,true);
 select count(*) into n from private.hikvision_gateway_health_events where market_id=m;
 update public.hikvision_market_config set capture_provider='hikconnect_cloud' where market_id=m;
 update private.hikvision_gateways set last_seen_at=now() where id=g;
 if (select count(*) from private.hikvision_gateway_health_events where market_id=m)<>n then raise exception 'cloud mode emitted gateway event'; end if;
 if public.hikvision_gateway_health_service(m)->>'status'<>'disabled' then raise exception 'cloud mode monitored'; end if;
 update public.hikvision_market_config set capture_provider='local_gateway' where market_id=m;
 update private.hikvision_gateways set last_seen_at=now()+interval '2 minutes' where id=g;
 if public.hikvision_gateway_health_service(m)->>'status'<>'unknown' then raise exception 'future clock treated as healthy'; end if;
 update private.hikvision_gateways set active=false where id=g;
 if public.hikvision_gateway_health_service(m)->>'status'<>'unpaired' then raise exception 'deactivated gateway not unpaired'; end if;
end;
$test$;
select pass('health uses heartbeat age, deduplicates transitions, suppresses disabled/cloud alerts and isolates tenant history');
select * from finish();
rollback;
