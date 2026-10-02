alter table private.owner_decisions add column if not exists acknowledged_at timestamptz;
alter table private.owner_decisions add column if not exists snoozed_until timestamptz;

create index if not exists owner_decisions_owner_status_snooze_idx
  on private.owner_decisions(owner_user_id,status,snoozed_until,last_seen_at desc);

create or replace function public.transition_owner_decision_service(
  p_owner_user_id uuid,
  p_decision_id uuid,
  p_action text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_action text := lower(trim(coalesce(p_action,'')));
  v_status text;
  v_title text;
  v_snoozed_until timestamptz;
begin
  if not exists (
    select 1 from public.profiles p
    where p.id=p_owner_user_id and p.is_system_owner=true and p.active=true and p.approved=true
  ) then
    raise exception 'owner_required' using errcode='42501';
  end if;

  if v_action='ack' then
    update private.owner_decisions d
    set status='acknowledged', acknowledged_at=coalesce(acknowledged_at,now()), snoozed_until=null, updated_at=now()
    where d.owner_user_id=p_owner_user_id and d.id=p_decision_id and d.status in ('open','acknowledged')
    returning d.status,d.title,d.snoozed_until into v_status,v_title,v_snoozed_until;
  elsif v_action='snooze_60' then
    update private.owner_decisions d
    set status='acknowledged', acknowledged_at=coalesce(acknowledged_at,now()), snoozed_until=now()+interval '60 minutes', updated_at=now()
    where d.owner_user_id=p_owner_user_id and d.id=p_decision_id and d.status in ('open','acknowledged')
    returning d.status,d.title,d.snoozed_until into v_status,v_title,v_snoozed_until;
  elsif v_action='snooze_360' then
    update private.owner_decisions d
    set status='acknowledged', acknowledged_at=coalesce(acknowledged_at,now()), snoozed_until=now()+interval '6 hours', updated_at=now()
    where d.owner_user_id=p_owner_user_id and d.id=p_decision_id and d.status in ('open','acknowledged')
    returning d.status,d.title,d.snoozed_until into v_status,v_title,v_snoozed_until;
  elsif v_action='reopen' then
    update private.owner_decisions d
    set status='open', acknowledged_at=null, snoozed_until=null, updated_at=now()
    where d.owner_user_id=p_owner_user_id and d.id=p_decision_id and d.status='acknowledged'
    returning d.status,d.title,d.snoozed_until into v_status,v_title,v_snoozed_until;
  else
    return jsonb_build_object('ok',false,'reason','unsupported_action');
  end if;

  if not found then
    if not exists(select 1 from private.owner_decisions d where d.owner_user_id=p_owner_user_id and d.id=p_decision_id) then
      return jsonb_build_object('ok',false,'reason','not_found');
    end if;
    return jsonb_build_object('ok',false,'reason','invalid_state');
  end if;

  perform public.log_owner_telegram_os_command_service(
    p_owner_user_id,
    'decision_'||v_action,
    'ok',
    jsonb_build_object('decision_id',p_decision_id,'title',v_title,'snoozed_until',v_snoozed_until)
  );

  return jsonb_build_object('ok',true,'status',v_status,'title',v_title,'snoozed_until',v_snoozed_until,'action',v_action);
end;
$$;

create or replace function public.acknowledge_owner_decision_service(p_owner_user_id uuid,p_decision_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
begin
  return public.transition_owner_decision_service(p_owner_user_id,p_decision_id,'ack');
end;
$$;

create or replace function public.get_owner_decision_inbox_service(p_owner_user_id uuid,p_limit integer default 10)
returns jsonb
language plpgsql
security definer
set search_path=''
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
  where owner_user_id=p_owner_user_id
    and status in ('open','acknowledged')
    and (snoozed_until is null or snoozed_until<=now());
  select coalesce(jsonb_agg(to_jsonb(x) order by x.severity_rank,x.last_seen_at desc),'[]'::jsonb)
  into v_items
  from (
    select d.id,d.decision_key,d.kind,d.severity,d.title,d.body,d.evidence,d.recommended_actions,d.status,d.first_seen_at,d.last_seen_at,d.acknowledged_at,d.snoozed_until,
           case d.severity when 'critical' then 0 when 'warning' then 1 else 2 end as severity_rank
    from private.owner_decisions d
    where d.owner_user_id=p_owner_user_id
      and d.status in ('open','acknowledged')
      and (d.snoozed_until is null or d.snoozed_until<=now())
    order by case d.severity when 'critical' then 0 when 'warning' then 1 else 2 end,d.last_seen_at desc
    limit v_limit
  ) x;
  return jsonb_build_object('generated_at',now(),'total',v_total,'critical',v_critical,'warning',v_warning,'items',v_items);
end;
$$;

create or replace function public.get_owner_decision_by_id_service(p_owner_user_id uuid,p_decision_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v jsonb;
begin
  if not exists(select 1 from public.profiles p where p.id=p_owner_user_id and p.is_system_owner=true and p.active=true and p.approved=true) then
    raise exception 'owner_required' using errcode='42501';
  end if;
  perform private.refresh_owner_decisions_for(p_owner_user_id);
  select to_jsonb(d) into v from private.owner_decisions d where d.owner_user_id=p_owner_user_id and d.id=p_decision_id limit 1;
  return v;
end;
$$;

revoke all on function public.transition_owner_decision_service(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.transition_owner_decision_service(uuid,uuid,text) to service_role;
revoke all on function public.acknowledge_owner_decision_service(uuid,uuid) from public,anon,authenticated;
grant execute on function public.acknowledge_owner_decision_service(uuid,uuid) to service_role;
revoke all on function public.get_owner_decision_inbox_service(uuid,integer) from public,anon,authenticated;
grant execute on function public.get_owner_decision_inbox_service(uuid,integer) to service_role;
revoke all on function public.get_owner_decision_by_id_service(uuid,uuid) from public,anon,authenticated;
grant execute on function public.get_owner_decision_by_id_service(uuid,uuid) to service_role;
