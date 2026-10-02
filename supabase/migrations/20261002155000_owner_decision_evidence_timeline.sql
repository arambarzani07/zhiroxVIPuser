create table if not exists private.owner_decision_events (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references public.profiles(id) on delete cascade,
  decision_id uuid not null references private.owner_decisions(id) on delete cascade,
  event_type text not null check (event_type in ('created','acknowledged','snoozed','reopened','resolved','reactivated','evidence_changed')),
  actor_type text not null check (actor_type in ('system','owner')),
  actor_user_id uuid null references public.profiles(id) on delete set null,
  status_before text null,
  status_after text null,
  evidence jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  event_seq bigint
);

alter table private.owner_decision_events enable row level security;
revoke all on table private.owner_decision_events from public, anon, authenticated;
grant select, insert, update, delete on table private.owner_decision_events to service_role;

drop policy if exists owner_decision_events_deny_client on private.owner_decision_events;
create policy owner_decision_events_deny_client
on private.owner_decision_events
for all
to anon, authenticated
using (false)
with check (false);

create index if not exists owner_decision_events_owner_created_idx
  on private.owner_decision_events(owner_user_id, created_at desc);
create index if not exists owner_decision_events_decision_created_idx
  on private.owner_decision_events(decision_id, created_at asc);
create index if not exists owner_decision_events_actor_idx
  on private.owner_decision_events(actor_user_id)
  where actor_user_id is not null;

create sequence if not exists private.owner_decision_events_event_seq_seq;
alter sequence private.owner_decision_events_event_seq_seq owned by private.owner_decision_events.event_seq;
alter table private.owner_decision_events
  alter column event_seq set default nextval('private.owner_decision_events_event_seq_seq'::regclass);
update private.owner_decision_events
set event_seq=nextval('private.owner_decision_events_event_seq_seq'::regclass)
where event_seq is null;
alter table private.owner_decision_events alter column event_seq set not null;
create unique index if not exists owner_decision_events_event_seq_uidx
  on private.owner_decision_events(event_seq);

drop trigger if exists preserve_owner_decision_ack_status on private.owner_decisions;
drop function if exists private.preserve_owner_decision_ack_status();

create or replace function private.capture_owner_decision_lifecycle()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_event_type text;
  v_actor_type text := 'system';
  v_actor_user_id uuid := null;
  v_metadata jsonb := '{}'::jsonb;
begin
  if tg_op='INSERT' then
    insert into private.owner_decision_events(
      owner_user_id,decision_id,event_type,actor_type,actor_user_id,
      status_before,status_after,evidence,metadata
    ) values (
      new.owner_user_id,new.id,'created','system',null,
      null,new.status,coalesce(new.evidence,'{}'::jsonb),
      jsonb_build_object('decision_key',new.decision_key,'kind',new.kind,'severity',new.severity)
    );
    return new;
  end if;

  if old.status is distinct from new.status then
    if new.status='resolved' then
      v_event_type := 'resolved';
      v_metadata := jsonb_build_object('resolved_at',new.resolved_at);
    elsif old.status='resolved' and new.status='open' then
      v_event_type := 'reactivated';
      v_metadata := jsonb_build_object('previous_resolved_at',old.resolved_at);
    elsif new.status='acknowledged' and new.snoozed_until is not null
          and old.snoozed_until is distinct from new.snoozed_until then
      v_event_type := 'snoozed';
      v_actor_type := 'owner';
      v_actor_user_id := new.owner_user_id;
      v_metadata := jsonb_build_object('snoozed_until',new.snoozed_until);
    elsif old.status='open' and new.status='acknowledged' then
      v_event_type := 'acknowledged';
      v_actor_type := 'owner';
      v_actor_user_id := new.owner_user_id;
      v_metadata := jsonb_build_object('acknowledged_at',new.acknowledged_at);
    elsif old.status='acknowledged' and new.status='open' then
      v_event_type := 'reopened';
      v_actor_type := 'owner';
      v_actor_user_id := new.owner_user_id;
    end if;
  elsif old.snoozed_until is distinct from new.snoozed_until and new.snoozed_until is not null then
    v_event_type := 'snoozed';
    v_actor_type := 'owner';
    v_actor_user_id := new.owner_user_id;
    v_metadata := jsonb_build_object('snoozed_until',new.snoozed_until);
  elsif (coalesce(old.evidence,'{}'::jsonb)-'generated_at')
        is distinct from
        (coalesce(new.evidence,'{}'::jsonb)-'generated_at') then
    v_event_type := 'evidence_changed';
  end if;

  if v_event_type is not null then
    insert into private.owner_decision_events(
      owner_user_id,decision_id,event_type,actor_type,actor_user_id,
      status_before,status_after,evidence,metadata
    ) values (
      new.owner_user_id,new.id,v_event_type,v_actor_type,v_actor_user_id,
      old.status,new.status,coalesce(new.evidence,'{}'::jsonb),
      jsonb_build_object('decision_key',new.decision_key,'kind',new.kind,'severity',new.severity) || v_metadata
    );
  end if;
  return new;
end;
$$;

revoke all on function private.capture_owner_decision_lifecycle() from public, anon, authenticated;
grant execute on function private.capture_owner_decision_lifecycle() to service_role;

drop trigger if exists owner_decisions_lifecycle_trigger on private.owner_decisions;
create trigger owner_decisions_lifecycle_trigger
after insert or update on private.owner_decisions
for each row execute function private.capture_owner_decision_lifecycle();

create or replace function private.sync_owner_decision_signal(
  p_owner_user_id uuid,
  p_decision_key text,
  p_active boolean,
  p_kind text,
  p_severity text,
  p_title text,
  p_body text,
  p_evidence jsonb,
  p_recommended_actions jsonb
)
returns void
language plpgsql
security definer
set search_path=''
as $$
begin
  if coalesce(p_active,false) then
    insert into private.owner_decisions as d(
      owner_user_id,decision_key,kind,severity,title,body,evidence,recommended_actions,
      status,first_seen_at,last_seen_at,resolved_at,updated_at
    ) values (
      p_owner_user_id,p_decision_key,p_kind,p_severity,p_title,p_body,
      coalesce(p_evidence,'{}'::jsonb),coalesce(p_recommended_actions,'[]'::jsonb),
      'open',now(),now(),null,now()
    )
    on conflict(owner_user_id,decision_key) do update set
      kind=excluded.kind,
      severity=excluded.severity,
      title=excluded.title,
      body=excluded.body,
      evidence=excluded.evidence,
      recommended_actions=excluded.recommended_actions,
      status=case when d.status='resolved' then 'open' else d.status end,
      acknowledged_at=case when d.status='resolved' then null else d.acknowledged_at end,
      snoozed_until=case when d.status='resolved' then null else d.snoozed_until end,
      last_seen_at=now(),
      resolved_at=null,
      updated_at=now();
  else
    update private.owner_decisions d
    set status='resolved',
        evidence=coalesce(p_evidence,'{}'::jsonb) || jsonb_build_object('resolution_verified',true),
        resolved_at=coalesce(d.resolved_at,now()),
        snoozed_until=null,
        updated_at=now()
    where d.owner_user_id=p_owner_user_id
      and d.decision_key=p_decision_key
      and d.status in ('open','acknowledged');
  end if;
end;
$$;

revoke all on function private.sync_owner_decision_signal(uuid,text,boolean,text,text,text,text,jsonb,jsonb) from public, anon, authenticated;
grant execute on function private.sync_owner_decision_signal(uuid,text,boolean,text,text,text,text,jsonb,jsonb) to service_role;

create or replace function private.refresh_owner_decisions_for(p_owner_user_id uuid)
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare
  v_data jsonb;
  v_overview jsonb;
  v_attention integer := 0;
  v_degraded integer := 0;
  v_dead integer := 0;
  v_failed integer := 0;
  v_retrying integer := 0;
  v_risk_critical integer := 0;
  v_risk_high integer := 0;
  v_open integer := 0;
begin
  if not exists(
    select 1 from public.profiles p
    where p.id=p_owner_user_id and p.is_system_owner=true and p.active=true and p.approved=true
  ) then
    raise exception 'owner_required' using errcode='42501';
  end if;

  v_data := public.get_system_owner_autopilot_overview_v2_service('', 'all', 1, 100);
  v_overview := coalesce(v_data->'overview','{}'::jsonb);
  v_attention := coalesce((v_overview->>'attention')::integer,0);
  v_degraded := coalesce((v_overview->>'degraded')::integer,0);
  v_dead := coalesce((v_overview->>'dead_letter')::integer,0);
  v_failed := coalesce((v_overview->>'failed')::integer,0);
  v_retrying := coalesce((v_overview->>'retrying')::integer,0);
  v_risk_critical := coalesce((v_overview->>'risk_critical')::integer,0);
  v_risk_high := coalesce((v_overview->>'risk_high')::integer,0);

  perform private.sync_owner_decision_signal(
    p_owner_user_id,'system_market_health',(v_attention>0 or v_degraded>0),'operations',
    case when v_attention>0 then 'critical' else 'warning' end,
    'دۆخی مارکێت پێویستی بە سەرنج هەیە',format('%s Attention • %s Degraded',v_attention,v_degraded),
    jsonb_build_object('attention',v_attention,'degraded',v_degraded,'generated_at',v_data->'generated_at'),
    '["open_autopilot_control_center","inspect_affected_markets"]'::jsonb
  );

  perform private.sync_owner_decision_signal(
    p_owner_user_id,'autopilot_dead_letter',(v_dead>0),'operations','critical',
    'Dead-letter هەیە',format('%s job لە Dead-letter ـدایە',v_dead),
    jsonb_build_object('dead_letter',v_dead,'generated_at',v_data->'generated_at'),
    '["inspect_dead_letter","retry_safe_jobs_only"]'::jsonb
  );

  perform private.sync_owner_decision_signal(
    p_owner_user_id,'autopilot_delivery_pressure',(v_failed>0 or v_retrying>=5),'operations',
    case when v_failed>0 then 'critical' else 'warning' end,
    'Queue/Retry پێویستی بە پشکنین هەیە',format('%s Failed • %s Retry',v_failed,v_retrying),
    jsonb_build_object('failed',v_failed,'retrying',v_retrying,'generated_at',v_data->'generated_at'),
    '["inspect_queue","inspect_failure_reasons"]'::jsonb
  );

  perform private.sync_owner_decision_signal(
    p_owner_user_id,'critical_customer_risk',(v_risk_critical>0),'risk','critical',
    'Critical Risk پێویستی بە review هەیە',format('%s Critical • %s High',v_risk_critical,v_risk_high),
    jsonb_build_object('critical',v_risk_critical,'high',v_risk_high,'generated_at',v_data->'generated_at'),
    '["open_risk_view","review_critical_customers"]'::jsonb
  );

  select count(*) into v_open
  from private.owner_decisions
  where owner_user_id=p_owner_user_id and status in ('open','acknowledged');
  return v_open;
end;
$$;

revoke all on function private.refresh_owner_decisions_for(uuid) from public, anon, authenticated;
grant execute on function private.refresh_owner_decisions_for(uuid) to service_role;

create or replace function public.get_owner_decision_timeline_service(
  p_owner_user_id uuid,
  p_decision_id uuid,
  p_limit integer default 50
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit,50),1),100);
  v_decision jsonb;
  v_events jsonb := '[]'::jsonb;
  v_episode_started_at timestamptz;
begin
  if not exists(
    select 1 from public.profiles p
    where p.id=p_owner_user_id and p.is_system_owner=true and p.active=true and p.approved=true
  ) then
    raise exception 'owner_required' using errcode='42501';
  end if;

  perform private.refresh_owner_decisions_for(p_owner_user_id);

  select to_jsonb(d) into v_decision
  from private.owner_decisions d
  where d.owner_user_id=p_owner_user_id and d.id=p_decision_id
  limit 1;

  if v_decision is null then
    return jsonb_build_object('ok',false,'reason','not_found');
  end if;

  select e.created_at into v_episode_started_at
  from private.owner_decision_events e
  where e.owner_user_id=p_owner_user_id
    and e.decision_id=p_decision_id
    and e.event_type in ('created','reactivated')
  order by e.event_seq desc
  limit 1;

  select coalesce(jsonb_agg(to_jsonb(q) order by q.event_seq asc),'[]'::jsonb)
  into v_events
  from (
    select e.event_seq,e.event_type,e.actor_type,e.status_before,e.status_after,e.evidence,e.metadata,e.created_at
    from private.owner_decision_events e
    where e.owner_user_id=p_owner_user_id and e.decision_id=p_decision_id
    order by e.event_seq desc
    limit v_limit
  ) q;

  return jsonb_build_object(
    'ok',true,
    'generated_at',now(),
    'decision',v_decision,
    'lifecycle',jsonb_build_object(
      'status',v_decision->>'status',
      'episode_started_at',v_episode_started_at,
      'first_seen_at',v_decision->>'first_seen_at',
      'last_seen_at',v_decision->>'last_seen_at',
      'acknowledged_at',v_decision->>'acknowledged_at',
      'snoozed_until',v_decision->>'snoozed_until',
      'resolved_at',v_decision->>'resolved_at'
    ),
    'events',v_events
  );
end;
$$;

revoke all on function public.get_owner_decision_timeline_service(uuid,uuid,integer) from public, anon, authenticated;
grant execute on function public.get_owner_decision_timeline_service(uuid,uuid,integer) to service_role;