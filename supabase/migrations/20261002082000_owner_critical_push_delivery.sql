create table if not exists private.owner_critical_push_deliveries (
  alert_id uuid primary key references public.app_realtime_notifications(id) on delete cascade,
  recipient_user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','processing','sent')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  next_attempt_at timestamptz not null default now(),
  processing_started_at timestamptz,
  last_error text,
  provider_message_id text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table private.owner_critical_push_deliveries enable row level security;

create index if not exists owner_critical_push_due_idx
  on private.owner_critical_push_deliveries(status, next_attempt_at)
  where status = 'pending';

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

  update private.owner_critical_push_deliveries
  set status = 'pending', processing_started_at = null, next_attempt_at = now(),
      last_error = coalesce(last_error, 'processing_timeout'), updated_at = now()
  where status = 'processing'
    and processing_started_at < now() - interval '10 minutes';

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
  on conflict (alert_id) do nothing;

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
    set status = 'processing', attempt_count = d.attempt_count + 1,
        processing_started_at = now(), updated_at = now()
    from picked p
    where d.alert_id = p.alert_id
    returning d.alert_id, d.recipient_user_id, d.attempt_count
  )
  select c.alert_id, c.recipient_user_id, n.title, n.body, n.event_type, n.data, c.attempt_count
  from claimed c
  join public.app_realtime_notifications n on n.id = c.alert_id;
end;
$$;

create or replace function public.finish_owner_critical_push_service(
  p_alert_id uuid,
  p_success boolean,
  p_provider_message_id text default null,
  p_error text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempt integer;
  v_delay interval;
begin
  select attempt_count into v_attempt
  from private.owner_critical_push_deliveries
  where alert_id = p_alert_id
  for update;

  if not found then raise exception 'delivery_not_found'; end if;

  if p_success then
    update private.owner_critical_push_deliveries
    set status = 'sent',
        provider_message_id = nullif(left(coalesce(p_provider_message_id,''), 200), ''),
        sent_at = now(), processing_started_at = null, last_error = null, updated_at = now()
    where alert_id = p_alert_id;

    update public.app_realtime_notifications
    set delivered_at = coalesce(delivered_at, now())
    where id = p_alert_id;

    return jsonb_build_object('ok', true, 'status', 'sent', 'attempt_count', v_attempt);
  end if;

  v_delay := case v_attempt
    when 1 then interval '1 minute'
    when 2 then interval '5 minutes'
    when 3 then interval '30 minutes'
    when 4 then interval '2 hours'
    else interval '6 hours'
  end;

  update private.owner_critical_push_deliveries
  set status = 'pending', next_attempt_at = now() + v_delay,
      processing_started_at = null,
      last_error = left(coalesce(p_error, 'push_failed'), 500), updated_at = now()
  where alert_id = p_alert_id;

  return jsonb_build_object('ok', true, 'status', 'pending', 'attempt_count', v_attempt,
                            'next_attempt_at', now() + v_delay);
end;
$$;

revoke all on function public.claim_owner_critical_push_service(integer) from public, anon, authenticated;
revoke all on function public.finish_owner_critical_push_service(uuid,boolean,text,text) from public, anon, authenticated;
grant execute on function public.claim_owner_critical_push_service(integer) to service_role;
grant execute on function public.finish_owner_critical_push_service(uuid,boolean,text,text) to service_role;

create or replace function private.invoke_owner_critical_push_worker_service()
returns bigint
language plpgsql
security definer
set search_path = 'pg_catalog','public'
as $$
declare
  v_config jsonb;
  v_secret text;
  v_request_id bigint;
begin
  v_config := public.get_customer_push_runtime_config_service();
  v_secret := nullif(v_config->>'customer_push_worker_secret','');
  if v_secret is null then raise exception 'customer_push_worker_secret_missing'; end if;

  select net.http_post(
    url := 'https://madoflmbretqghqbqaak.supabase.co/functions/v1/owner-critical-push-worker',
    body := '{}'::jsonb,
    params := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','x-zhirox-push-worker',v_secret),
    timeout_milliseconds := 10000
  ) into v_request_id;
  return v_request_id;
end;
$$;

revoke all on function private.invoke_owner_critical_push_worker_service() from public, anon, authenticated;
grant execute on function private.invoke_owner_critical_push_worker_service() to service_role;

do $$
declare v_jobid bigint;
begin
  select jobid into v_jobid from cron.job where jobname = 'zhirox-owner-critical-push-worker' limit 1;
  if v_jobid is not null then perform cron.unschedule(v_jobid); end if;
end $$;

select cron.schedule(
  'zhirox-owner-critical-push-worker',
  '* * * * *',
  'select private.invoke_owner_critical_push_worker_service();'
);
