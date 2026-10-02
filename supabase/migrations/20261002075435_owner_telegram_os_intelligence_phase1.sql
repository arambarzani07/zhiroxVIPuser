create table if not exists private.owner_intelligence_snapshots (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references public.profiles(id) on delete cascade,
  captured_at timestamptz not null default now(),
  payload jsonb not null default '{}'::jsonb
);

create index if not exists owner_intelligence_snapshots_owner_captured_idx
  on private.owner_intelligence_snapshots(owner_user_id, captured_at desc);

alter table private.owner_intelligence_snapshots enable row level security;
revoke all on table private.owner_intelligence_snapshots from public, anon, authenticated;
grant select, insert, update, delete on table private.owner_intelligence_snapshots to service_role;

drop policy if exists owner_intelligence_snapshots_deny_client on private.owner_intelligence_snapshots;
create policy owner_intelligence_snapshots_deny_client
  on private.owner_intelligence_snapshots
  for all to anon, authenticated
  using (false) with check (false);

create table if not exists private.owner_decisions (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references public.profiles(id) on delete cascade,
  decision_key text not null,
  kind text not null,
  severity text not null check (severity in ('info','warning','critical')),
  title text not null,
  body text not null,
  evidence jsonb not null default '{}'::jsonb,
  recommended_actions jsonb not null default '[]'::jsonb,
  status text not null default 'open' check (status in ('open','acknowledged','resolved','dismissed')),
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  resolved_at timestamptz,
  updated_at timestamptz not null default now(),
  unique(owner_user_id, decision_key)
);

create index if not exists owner_decisions_open_idx
  on private.owner_decisions(owner_user_id, status, severity, last_seen_at desc);

alter table private.owner_decisions enable row level security;
revoke all on table private.owner_decisions from public, anon, authenticated;
grant select, insert, update, delete on table private.owner_decisions to service_role;

drop policy if exists owner_decisions_deny_client on private.owner_decisions;
create policy owner_decisions_deny_client
  on private.owner_decisions
  for all to anon, authenticated
  using (false) with check (false);

create table if not exists private.owner_telegram_os_context (
  owner_user_id uuid primary key references public.profiles(id) on delete cascade,
  last_changes_seen_at timestamptz,
  last_brief_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table private.owner_telegram_os_context enable row level security;
revoke all on table private.owner_telegram_os_context from public, anon, authenticated;
grant select, insert, update, delete on table private.owner_telegram_os_context to service_role;

drop policy if exists owner_telegram_os_context_deny_client on private.owner_telegram_os_context;
create policy owner_telegram_os_context_deny_client
  on private.owner_telegram_os_context
  for all to anon, authenticated
  using (false) with check (false);

create or replace function private.capture_owner_intelligence_snapshot()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_payload jsonb;
  v_count integer := 0;
begin
  for r in
    select p.id
    from public.profiles p
    where p.is_system_owner = true
      and p.active = true
      and p.approved = true
  loop
    v_payload := public.get_system_owner_autopilot_overview_v2_service('', 'all', 1, 100);
    insert into private.owner_intelligence_snapshots(owner_user_id, captured_at, payload)
    values (r.id, now(), v_payload);
    v_count := v_count + 1;
  end loop;

  delete from private.owner_intelligence_snapshots
  where captured_at < now() - interval '30 days';

  return v_count;
end;
$$;

revoke all on function private.capture_owner_intelligence_snapshot() from public, anon, authenticated;
grant execute on function private.capture_owner_intelligence_snapshot() to service_role;

create or replace function private.refresh_owner_decisions_for(p_owner_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_is_owner boolean := false;
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
  select exists(
    select 1 from public.profiles p
    where p.id = p_owner_user_id
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  ) into v_is_owner;

  if not v_is_owner then
    raise exception 'owner_required' using errcode = '42501';
  end if;

  v_data := public.get_system_owner_autopilot_overview_v2_service('', 'all', 1, 100);
  v_overview := coalesce(v_data->'overview', '{}'::jsonb);
  v_attention := coalesce((v_overview->>'attention')::integer, 0);
  v_degraded := coalesce((v_overview->>'degraded')::integer, 0);
  v_dead := coalesce((v_overview->>'dead_letter')::integer, 0);
  v_failed := coalesce((v_overview->>'failed')::integer, 0);
  v_retrying := coalesce((v_overview->>'retrying')::integer, 0);
  v_risk_critical := coalesce((v_overview->>'risk_critical')::integer, 0);
  v_risk_high := coalesce((v_overview->>'risk_high')::integer, 0);

  if v_attention > 0 or v_degraded > 0 then
    insert into private.owner_decisions(owner_user_id,decision_key,kind,severity,title,body,evidence,recommended_actions,status,first_seen_at,last_seen_at,resolved_at,updated_at)
    values (
      p_owner_user_id,'system_market_health','operations',
      case when v_attention > 0 then 'critical' else 'warning' end,
      'دۆخی مارکێت پێویستی بە سەرنج هەیە',
      format('%s Attention • %s Degraded',v_attention,v_degraded),
      jsonb_build_object('attention',v_attention,'degraded',v_degraded,'generated_at',v_data->'generated_at'),
      '["open_autopilot_control_center","inspect_affected_markets"]'::jsonb,
      'open',now(),now(),null,now()
    )
    on conflict(owner_user_id,decision_key) do update set
      severity=excluded.severity,title=excluded.title,body=excluded.body,evidence=excluded.evidence,
      recommended_actions=excluded.recommended_actions,status='open',last_seen_at=now(),resolved_at=null,updated_at=now();
  else
    update private.owner_decisions set status='resolved',resolved_at=coalesce(resolved_at,now()),updated_at=now()
    where owner_user_id=p_owner_user_id and decision_key='system_market_health' and status in ('open','acknowledged');
  end if;

  if v_dead > 0 then
    insert into private.owner_decisions(owner_user_id,decision_key,kind,severity,title,body,evidence,recommended_actions,status,first_seen_at,last_seen_at,resolved_at,updated_at)
    values (p_owner_user_id,'autopilot_dead_letter','operations','critical','Dead-letter هەیە',format('%s job لە Dead-letter ـدایە',v_dead),jsonb_build_object('dead_letter',v_dead,'generated_at',v_data->'generated_at'),'["inspect_dead_letter","retry_safe_jobs_only"]'::jsonb,'open',now(),now(),null,now())
    on conflict(owner_user_id,decision_key) do update set severity=excluded.severity,title=excluded.title,body=excluded.body,evidence=excluded.evidence,recommended_actions=excluded.recommended_actions,status='open',last_seen_at=now(),resolved_at=null,updated_at=now();
  else
    update private.owner_decisions set status='resolved',resolved_at=coalesce(resolved_at,now()),updated_at=now()
    where owner_user_id=p_owner_user_id and decision_key='autopilot_dead_letter' and status in ('open','acknowledged');
  end if;

  if v_failed > 0 or v_retrying >= 5 then
    insert into private.owner_decisions(owner_user_id,decision_key,kind,severity,title,body,evidence,recommended_actions,status,first_seen_at,last_seen_at,resolved_at,updated_at)
    values (p_owner_user_id,'autopilot_delivery_pressure','operations',case when v_failed > 0 then 'critical' else 'warning' end,'Queue/Retry پێویستی بە پشکنین هەیە',format('%s Failed • %s Retry',v_failed,v_retrying),jsonb_build_object('failed',v_failed,'retrying',v_retrying,'generated_at',v_data->'generated_at'),'["inspect_queue","inspect_failure_reasons"]'::jsonb,'open',now(),now(),null,now())
    on conflict(owner_user_id,decision_key) do update set severity=excluded.severity,title=excluded.title,body=excluded.body,evidence=excluded.evidence,recommended_actions=excluded.recommended_actions,status='open',last_seen_at=now(),resolved_at=null,updated_at=now();
  else
    update private.owner_decisions set status='resolved',resolved_at=coalesce(resolved_at,now()),updated_at=now()
    where owner_user_id=p_owner_user_id and decision_key='autopilot_delivery_pressure' and status in ('open','acknowledged');
  end if;

  if v_risk_critical > 0 then
    insert into private.owner_decisions(owner_user_id,decision_key,kind,severity,title,body,evidence,recommended_actions,status,first_seen_at,last_seen_at,resolved_at,updated_at)
    values (p_owner_user_id,'critical_customer_risk','risk','critical','Critical Risk پێویستی بە review هەیە',format('%s Critical • %s High',v_risk_critical,v_risk_high),jsonb_build_object('critical',v_risk_critical,'high',v_risk_high,'generated_at',v_data->'generated_at'),'["open_risk_view","review_critical_customers"]'::jsonb,'open',now(),now(),null,now())
    on conflict(owner_user_id,decision_key) do update set severity=excluded.severity,title=excluded.title,body=excluded.body,evidence=excluded.evidence,recommended_actions=excluded.recommended_actions,status='open',last_seen_at=now(),resolved_at=null,updated_at=now();
  else
    update private.owner_decisions set status='resolved',resolved_at=coalesce(resolved_at,now()),updated_at=now()
    where owner_user_id=p_owner_user_id and decision_key='critical_customer_risk' and status in ('open','acknowledged');
  end if;

  select count(*) into v_open
  from private.owner_decisions
  where owner_user_id=p_owner_user_id and status in ('open','acknowledged');
  return v_open;
end;
$$;

revoke all on function private.refresh_owner_decisions_for(uuid) from public, anon, authenticated;
grant execute on function private.refresh_owner_decisions_for(uuid) to service_role;

create or replace function private.refresh_all_owner_decisions()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_total integer := 0;
begin
  for r in
    select p.id from public.profiles p
    where p.is_system_owner=true and p.active=true and p.approved=true
  loop
    perform private.refresh_owner_decisions_for(r.id);
    v_total := v_total + 1;
  end loop;
  return v_total;
end;
$$;

revoke all on function private.refresh_all_owner_decisions() from public, anon, authenticated;
grant execute on function private.refresh_all_owner_decisions() to service_role;

create or replace function public.get_owner_decision_inbox_service(p_owner_user_id uuid, p_limit integer default 10)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit,10),1),50);
  v_items jsonb := '[]'::jsonb;
  v_total integer := 0;
  v_critical integer := 0;
  v_warning integer := 0;
begin
  if not exists(select 1 from public.profiles p where p.id=p_owner_user_id and p.is_system_owner=true and p.active=true and p.approved=true) then
    raise exception 'owner_required' using errcode='42501';
  end if;

  perform private.refresh_owner_decisions_for(p_owner_user_id);

  select count(*),count(*) filter(where severity='critical'),count(*) filter(where severity='warning')
  into v_total,v_critical,v_warning
  from private.owner_decisions
  where owner_user_id=p_owner_user_id and status in ('open','acknowledged');

  select coalesce(jsonb_agg(to_jsonb(x) order by x.severity_rank,x.last_seen_at desc),'[]'::jsonb)
  into v_items
  from (
    select d.id,d.decision_key,d.kind,d.severity,d.title,d.body,d.evidence,d.recommended_actions,d.status,d.first_seen_at,d.last_seen_at,
           case d.severity when 'critical' then 0 when 'warning' then 1 else 2 end as severity_rank
    from private.owner_decisions d
    where d.owner_user_id=p_owner_user_id and d.status in ('open','acknowledged')
    order by case d.severity when 'critical' then 0 when 'warning' then 1 else 2 end,d.last_seen_at desc
    limit v_limit
  ) x;

  return jsonb_build_object('generated_at',now(),'total',v_total,'critical',v_critical,'warning',v_warning,'items',v_items);
end;
$$;

revoke all on function public.get_owner_decision_inbox_service(uuid,integer) from public, anon, authenticated;
grant execute on function public.get_owner_decision_inbox_service(uuid,integer) to service_role;

create or replace function public.get_owner_executive_brief_service(p_owner_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current jsonb; v_current_o jsonb; v_previous jsonb; v_previous_o jsonb;
  v_decisions jsonb; v_delta jsonb; v_prev_at timestamptz;
begin
  if not exists(select 1 from public.profiles p where p.id=p_owner_user_id and p.is_system_owner=true and p.active=true and p.approved=true) then
    raise exception 'owner_required' using errcode='42501';
  end if;
  v_current := public.get_system_owner_autopilot_overview_v2_service('', 'all', 1, 100);
  v_current_o := coalesce(v_current->'overview','{}'::jsonb);
  perform private.refresh_owner_decisions_for(p_owner_user_id);
  v_decisions := public.get_owner_decision_inbox_service(p_owner_user_id,5);
  select s.payload,s.captured_at into v_previous,v_prev_at from private.owner_intelligence_snapshots s
  where s.owner_user_id=p_owner_user_id and s.captured_at <= now()-interval '23 hours' order by s.captured_at desc limit 1;
  if v_previous is null then
    select s.payload,s.captured_at into v_previous,v_prev_at from private.owner_intelligence_snapshots s
    where s.owner_user_id=p_owner_user_id order by s.captured_at asc limit 1;
  end if;
  v_previous_o := coalesce(v_previous->'overview','{}'::jsonb);
  v_delta := jsonb_build_object(
    'reference_at',v_prev_at,
    'attention',coalesce((v_current_o->>'attention')::integer,0)-coalesce((v_previous_o->>'attention')::integer,0),
    'degraded',coalesce((v_current_o->>'degraded')::integer,0)-coalesce((v_previous_o->>'degraded')::integer,0),
    'active_queue',coalesce((v_current_o->>'active_queue')::integer,0)-coalesce((v_previous_o->>'active_queue')::integer,0),
    'retrying',coalesce((v_current_o->>'retrying')::integer,0)-coalesce((v_previous_o->>'retrying')::integer,0),
    'dead_letter',coalesce((v_current_o->>'dead_letter')::integer,0)-coalesce((v_previous_o->>'dead_letter')::integer,0),
    'risk_high',coalesce((v_current_o->>'risk_high')::integer,0)-coalesce((v_previous_o->>'risk_high')::integer,0),
    'risk_critical',coalesce((v_current_o->>'risk_critical')::integer,0)-coalesce((v_previous_o->>'risk_critical')::integer,0),
    'telegram_linked_customers',coalesce((v_current_o->>'telegram_linked_customers')::integer,0)-coalesce((v_previous_o->>'telegram_linked_customers')::integer,0)
  );
  insert into private.owner_telegram_os_context(owner_user_id,last_brief_at,updated_at)
  values(p_owner_user_id,now(),now())
  on conflict(owner_user_id) do update set last_brief_at=excluded.last_brief_at,updated_at=now();
  return jsonb_build_object('generated_at',now(),'current',v_current_o,'delta_24h',v_delta,'decisions',v_decisions,'markets',coalesce(v_current->'items','[]'::jsonb));
end;
$$;

revoke all on function public.get_owner_executive_brief_service(uuid) from public, anon, authenticated;
grant execute on function public.get_owner_executive_brief_service(uuid) to service_role;

create or replace function public.get_owner_changes_since_last_check_service(p_owner_user_id uuid, p_mark_seen boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_since timestamptz; v_until timestamptz := now(); v_current jsonb; v_current_o jsonb;
  v_previous jsonb; v_previous_o jsonb; v_prev_at timestamptz; v_notifications jsonb := '[]'::jsonb;
  v_notification_count integer := 0; v_delta jsonb;
begin
  if not exists(select 1 from public.profiles p where p.id=p_owner_user_id and p.is_system_owner=true and p.active=true and p.approved=true) then
    raise exception 'owner_required' using errcode='42501';
  end if;
  select coalesce(c.last_changes_seen_at,now()-interval '24 hours') into v_since
  from private.owner_telegram_os_context c where c.owner_user_id=p_owner_user_id;
  if v_since is null then v_since := now()-interval '24 hours'; end if;
  v_current := public.get_system_owner_autopilot_overview_v2_service('', 'all', 1, 100);
  v_current_o := coalesce(v_current->'overview','{}'::jsonb);
  select s.payload,s.captured_at into v_previous,v_prev_at from private.owner_intelligence_snapshots s
  where s.owner_user_id=p_owner_user_id and s.captured_at<=v_since order by s.captured_at desc limit 1;
  v_previous_o := coalesce(v_previous->'overview','{}'::jsonb);
  v_delta := jsonb_build_object(
    'reference_at',v_prev_at,
    'attention',coalesce((v_current_o->>'attention')::integer,0)-coalesce((v_previous_o->>'attention')::integer,0),
    'degraded',coalesce((v_current_o->>'degraded')::integer,0)-coalesce((v_previous_o->>'degraded')::integer,0),
    'active_queue',coalesce((v_current_o->>'active_queue')::integer,0)-coalesce((v_previous_o->>'active_queue')::integer,0),
    'retrying',coalesce((v_current_o->>'retrying')::integer,0)-coalesce((v_previous_o->>'retrying')::integer,0),
    'dead_letter',coalesce((v_current_o->>'dead_letter')::integer,0)-coalesce((v_previous_o->>'dead_letter')::integer,0),
    'risk_high',coalesce((v_current_o->>'risk_high')::integer,0)-coalesce((v_previous_o->>'risk_high')::integer,0),
    'risk_critical',coalesce((v_current_o->>'risk_critical')::integer,0)-coalesce((v_previous_o->>'risk_critical')::integer,0)
  );
  select count(*) into v_notification_count from public.app_realtime_notifications n
  where n.recipient_user_id=p_owner_user_id and n.created_at>v_since and n.created_at<=v_until;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_notifications
  from (select n.id,n.event_type,n.title,n.body,n.data,n.created_at from public.app_realtime_notifications n
        where n.recipient_user_id=p_owner_user_id and n.created_at>v_since and n.created_at<=v_until order by n.created_at desc limit 10) x;
  if p_mark_seen then
    insert into private.owner_telegram_os_context(owner_user_id,last_changes_seen_at,updated_at)
    values(p_owner_user_id,v_until,now())
    on conflict(owner_user_id) do update set last_changes_seen_at=excluded.last_changes_seen_at,updated_at=now();
  end if;
  return jsonb_build_object('generated_at',v_until,'since',v_since,'delta',v_delta,'notification_count',v_notification_count,'notifications',v_notifications);
end;
$$;

revoke all on function public.get_owner_changes_since_last_check_service(uuid,boolean) from public, anon, authenticated;
grant execute on function public.get_owner_changes_since_last_check_service(uuid,boolean) to service_role;

select private.capture_owner_intelligence_snapshot();
select private.refresh_all_owner_decisions();

select cron.unschedule(jobid) from cron.job where jobname in ('zhirox-owner-intelligence-snapshot','zhirox-owner-decision-refresh');
select cron.schedule('zhirox-owner-intelligence-snapshot','*/15 * * * *',$cron$select private.capture_owner_intelligence_snapshot();$cron$);
select cron.schedule('zhirox-owner-decision-refresh','*/5 * * * *',$cron$select private.refresh_all_owner_decisions();$cron$);
