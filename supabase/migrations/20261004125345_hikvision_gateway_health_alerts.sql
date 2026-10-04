alter table public.hikvision_market_config add column if not exists gateway_alerts_enabled boolean not null default false;

create table private.hikvision_gateway_health (
 gateway_id uuid primary key references private.hikvision_gateways(id) on delete cascade,
 state text not null check(state in ('online','offline','paused')),
 changed_at timestamptz not null default now(),
 outage_started_at timestamptz,
 updated_at timestamptz not null default now()
);
create table private.hikvision_gateway_health_events (
 id uuid primary key default gen_random_uuid(),
 gateway_id uuid not null references private.hikvision_gateways(id) on delete cascade,
 market_id uuid not null references public.profiles(id) on delete cascade,
 state text not null check(state in ('online','offline')),
 occurred_at timestamptz not null default now(),
 last_seen_at timestamptz,
 outage_started_at timestamptz,
 notification_id uuid references public.app_realtime_notifications(id) on delete set null
);
create index hikvision_health_events_market_time on private.hikvision_gateway_health_events(market_id,occurred_at desc);
alter table private.hikvision_gateway_health enable row level security;
alter table private.hikvision_gateway_health_events enable row level security;
revoke all on private.hikvision_gateway_health,private.hikvision_gateway_health_events from public,anon,authenticated;

create or replace function private.evaluate_hikvision_gateway_health(p_gateway_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare
 g private.hikvision_gateways%rowtype;
 c public.hikvision_market_config%rowtype;
 h private.hikvision_gateway_health%rowtype;
 next_state text;
 event_id uuid;
 notice_id uuid;
 outage_at timestamptz;
 initial boolean;
begin
 -- Same lock order as gateway heartbeat. Serializes watchdog/recovery and prevents duplicate alerts.
 select * into g from private.hikvision_gateways where id=p_gateway_id for update;
 if not found then return; end if;
 select * into c from public.hikvision_market_config where market_id=g.market_id;
 if not found or not c.enabled or c.capture_provider<>'local_gateway' or not c.gateway_alerts_enabled or not g.active or g.token_sha256 is null then
  update private.hikvision_gateway_health set state='paused',outage_started_at=null,updated_at=now() where gateway_id=g.id and state<>'paused';
  return;
 end if;
 if g.last_seen_at>now()+interval '30 seconds' then return; end if;
 if g.last_seen_at is null and g.created_at>now()-interval '3 minutes' then return; end if;
 next_state:=case when g.last_seen_at>=now()-interval '3 minutes' then 'online' else 'offline' end;
 select * into h from private.hikvision_gateway_health where gateway_id=g.id;
 initial:=not found;
 if not initial and h.state=next_state then return; end if;
 outage_at:=case when next_state='offline' then coalesce(g.last_seen_at,g.created_at)+interval '3 minutes' else h.outage_started_at end;
 insert into private.hikvision_gateway_health(gateway_id,state,changed_at,outage_started_at,updated_at)
 values(g.id,next_state,now(),case when next_state='offline' then outage_at end,now())
 on conflict(gateway_id) do update set state=excluded.state,changed_at=excluded.changed_at,outage_started_at=excluded.outage_started_at,updated_at=excluded.updated_at;
 -- Initial healthy pairing / re-enabling is not a recovery notification.
 if next_state='online' and (initial or h.state<>'offline') then return; end if;
 event_id:=gen_random_uuid();
 if exists(select 1 from public.profiles where id=g.market_id and role='admin' and active=true and approved=true) then
  insert into public.app_realtime_notifications(recipient_user_id,market_id,title,body,event_type,data,expires_at)
  values(g.market_id,g.market_id,
   case when next_state='offline' then 'پەیوەندی Gateway پچڕاوە' else 'Gateway دووبارە چالاک بوو' end,
   case when next_state='offline' then 'زیاتر لە سێ خولەکە پەیامی Gateway نەهاتووە. PC، ئینتەرنێت و بەرنامەی Gateway بپشکنە.' else 'پەیامی Gateway دووبارە گەیشت. وەرگرتنی کلیپ دەتوانێت بەردەوام بێت؛ ئەمە دروستی کلیپ پشتڕاست ناکاتەوە.' end,
   'hikvision_gateway_'||next_state,
   jsonb_build_object('type','hikvision_gateway_'||next_state,'gateway_event_id',event_id,'gateway_id',g.id,'state',next_state,'occurred_at',now()),
   now()+interval '1 day') returning id into notice_id;
 end if;
 insert into private.hikvision_gateway_health_events(id,gateway_id,market_id,state,last_seen_at,outage_started_at,notification_id)
 values(event_id,g.id,g.market_id,next_state,g.last_seen_at,outage_at,notice_id);
end $$;
revoke all on function private.evaluate_hikvision_gateway_health(uuid) from public,anon,authenticated;

create or replace function private.hikvision_gateway_health_after_heartbeat()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform private.evaluate_hikvision_gateway_health(new.id);
 return new;
end $$;
revoke all on function private.hikvision_gateway_health_after_heartbeat() from public,anon,authenticated;
create trigger hikvision_health_heartbeat after update of last_seen_at,active on private.hikvision_gateways
 for each row execute function private.hikvision_gateway_health_after_heartbeat();

create or replace function private.sweep_hikvision_gateway_health()
returns integer language plpgsql security definer set search_path='' as $$
declare g record; total integer:=0;
begin
 for g in select x.id from private.hikvision_gateways x join public.hikvision_market_config c on c.market_id=x.market_id
 where c.gateway_alerts_enabled=true or exists(select 1 from private.hikvision_gateway_health h where h.gateway_id=x.id and h.state<>'paused') order by x.id
 loop
  perform private.evaluate_hikvision_gateway_health(g.id); total:=total+1;
 end loop;
 return total;
end $$;
revoke all on function private.sweep_hikvision_gateway_health() from public,anon,authenticated;

create or replace function public.hikvision_gateway_health_service(p_market_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
 'status',case when not c.enabled or c.capture_provider<>'local_gateway' then 'disabled'
 when g.id is null or not g.active or g.token_sha256 is null then 'unpaired'
 when g.last_seen_at>now()+interval '30 seconds' then 'unknown'
 when g.last_seen_at is null and g.created_at>now()-interval '3 minutes' then 'starting'
 when g.last_seen_at>=now()-interval '3 minutes' then 'online' else 'offline' end,
 'alerts_enabled',c.gateway_alerts_enabled,'server_time',now(),'offline_after_seconds',180,
 'last_seen_at',g.last_seen_at,'gateway_version',g.gateway_version,
 'events',coalesce((select jsonb_agg(e order by e.occurred_at desc) from
 (select id,state,occurred_at,last_seen_at,outage_started_at from private.hikvision_gateway_health_events where market_id=p_market_id order by occurred_at desc limit 20) e),'[]'::jsonb))
 from public.hikvision_market_config c left join private.hikvision_gateways g on g.market_id=c.market_id
 where c.market_id=p_market_id;
$$;
revoke all on function public.hikvision_gateway_health_service(uuid) from public,anon,authenticated;
grant execute on function public.hikvision_gateway_health_service(uuid) to service_role;

create or replace function public.hikvision_gateway_alerts_setting_service(p_market_id uuid,p_enabled boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare gateway uuid;
begin
 if p_enabled is null then raise exception 'invalid_enabled'; end if;
 update public.hikvision_market_config set gateway_alerts_enabled=p_enabled,updated_at=now() where market_id=p_market_id;
 if not found then raise exception 'config_not_found'; end if;
 select id into gateway from private.hikvision_gateways where market_id=p_market_id;
 if gateway is not null then perform private.evaluate_hikvision_gateway_health(gateway); end if;
 return jsonb_build_object('ok',true,'alerts_enabled',p_enabled);
end $$;
revoke all on function public.hikvision_gateway_alerts_setting_service(uuid,boolean) from public,anon,authenticated;
grant execute on function public.hikvision_gateway_alerts_setting_service(uuid,boolean) to service_role;

do $$begin
 if exists(select 1 from pg_extension where extname='pg_cron') then
  perform cron.schedule('hikvision-gateway-health-watchdog','* * * * *','select private.sweep_hikvision_gateway_health();');
 end if;
end $$;
