create or replace function public.claim_owner_critical_push_service(p_limit integer default 20)
returns table (
  alert_id uuid,
  recipient_user_id uuid,
  title text,
  body text,
  event_type text,
  data jsonb,
  attempt_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'invalid_limit';
  end if;

  update private.owner_critical_push_deliveries d
  set status = 'pending',
      processing_started_at = null,
      next_attempt_at = now(),
      last_error = coalesce(d.last_error, 'processing_timeout'),
      updated_at = now()
  where d.status = 'processing'
    and d.processing_started_at < now() - interval '10 minutes';

  insert into private.owner_critical_push_deliveries(alert_id, recipient_user_id)
  select n.id, n.recipient_user_id
  from public.app_realtime_notifications n
  join public.profiles p
    on p.id = n.recipient_user_id
   and p.is_system_owner = true
   and p.active = true
   and p.approved = true
  where n.event_type in ('owner_autopilot_critical','owner_autopilot_recovery')
    and (n.expires_at is null or n.expires_at > now())
  on conflict do nothing;

  return query
  with picked as (
    select d.alert_id
    from private.owner_critical_push_deliveries d
    join public.app_realtime_notifications n on n.id = d.alert_id
    where d.status = 'pending'
      and d.next_attempt_at <= now()
      and (n.expires_at is null or n.expires_at > now())
    order by d.next_attempt_at, d.created_at
    for update of d skip locked
    limit p_limit
  ), claimed as (
    update private.owner_critical_push_deliveries d
    set status = 'processing',
        attempt_count = d.attempt_count + 1,
        processing_started_at = now(),
        updated_at = now()
    from picked p
    where d.alert_id = p.alert_id
    returning d.alert_id, d.recipient_user_id, d.attempt_count
  )
  select c.alert_id,
         c.recipient_user_id,
         n.title,
         n.body,
         n.event_type,
         n.data,
         c.attempt_count
  from claimed c
  join public.app_realtime_notifications n on n.id = c.alert_id;
end;
$$;

revoke all on function public.claim_owner_critical_push_service(integer) from public, anon, authenticated;
grant execute on function public.claim_owner_critical_push_service(integer) to service_role;
