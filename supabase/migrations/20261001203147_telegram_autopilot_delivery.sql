create table if not exists private.telegram_autopilot_deliveries (
  id uuid primary key default gen_random_uuid(),
  outbox_id uuid not null unique references public.notification_outbox(id) on delete cascade,
  market_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','processing','retrying','sent','skipped','failed')),
  attempt_count integer not null default 0,
  max_attempts integer not null default 5 check (max_attempts between 1 and 20),
  next_attempt_at timestamptz not null default now(),
  locked_at timestamptz null,
  provider_message_id text null,
  last_error text null,
  sent_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists telegram_autopilot_ready_idx
  on private.telegram_autopilot_deliveries(status, next_attempt_at, created_at)
  where status in ('pending','retrying');
create index if not exists telegram_autopilot_market_idx
  on private.telegram_autopilot_deliveries(market_id, created_at desc);
create index if not exists telegram_autopilot_customer_idx
  on private.telegram_autopilot_deliveries(customer_id, created_at desc);

revoke all on table private.telegram_autopilot_deliveries from public, anon, authenticated;

create or replace function private.ensure_market_autopilot_settings()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.role = 'admin' then
    insert into public.market_autopilot_settings(market_id, updated_by)
    values (new.id, new.id)
    on conflict (market_id) do nothing;
  end if;
  return new;
end;
$$;

revoke all on function private.ensure_market_autopilot_settings() from public, anon, authenticated;

drop trigger if exists trg_ensure_market_autopilot_settings on public.profiles;
create trigger trg_ensure_market_autopilot_settings
after insert or update of role on public.profiles
for each row execute function private.ensure_market_autopilot_settings();

create or replace function private.enqueue_telegram_autopilot_delivery()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_max_attempts integer := 5;
  v_entity_kind text;
begin
  if new.event_type not in (
    'debt_created','payment_created','due_reminder','installment_reminder',
    'monthly_statement','debt_limit_changed','manual'
  ) then
    return new;
  end if;

  if new.event_type in ('debt_created','payment_created') then
    v_entity_kind := case when new.event_type = 'debt_created' then 'debt' else 'payment' end;
    if exists (
      select 1 from public.legacy_import_links l
      where l.target_id = new.event_record_id and l.entity_kind = v_entity_kind
    ) or exists (
      select 1 from public.daftar_sync_seen s
      where s.target_id = new.event_record_id and s.entity_kind = v_entity_kind
    ) then
      return new;
    end if;
  end if;

  select coalesce(s.max_retry_attempts,5)
  into v_max_attempts
  from public.market_autopilot_settings s
  where s.market_id = new.market_id;

  insert into private.telegram_autopilot_deliveries(
    outbox_id, market_id, customer_id, max_attempts
  ) values (
    new.id, new.market_id, new.customer_id, coalesce(v_max_attempts,5)
  ) on conflict (outbox_id) do nothing;

  return new;
end;
$$;

revoke all on function private.enqueue_telegram_autopilot_delivery() from public, anon, authenticated;

drop trigger if exists trg_telegram_autopilot_outbox on public.notification_outbox;
create trigger trg_telegram_autopilot_outbox
after insert on public.notification_outbox
for each row execute function private.enqueue_telegram_autopilot_delivery();

create or replace function public.claim_telegram_autopilot_deliveries_service(p_limit integer default 25)
returns table(
  delivery_id uuid,
  outbox_id uuid,
  market_id uuid,
  customer_id uuid,
  event_type text,
  event_record_id uuid,
  payload jsonb,
  deep_link text,
  attempt_count integer,
  max_attempts integer,
  chat_id text
)
language sql
security definer
set search_path = ''
as $$
  with picked as (
    select d.id
    from private.telegram_autopilot_deliveries d
    join public.notification_outbox o on o.id = d.outbox_id
    join public.market_autopilot_settings s on s.market_id = d.market_id
    left join public.customer_notification_preferences pref
      on pref.market_id = d.market_id and pref.customer_id = d.customer_id
    where d.status in ('pending','retrying')
      and d.next_attempt_at <= now()
      and s.enabled = true
      and s.mode <> 'manual'
      and coalesce(
        case o.event_type
          when 'due_reminder' then pref.due_reminders
          when 'installment_reminder' then pref.installment_reminders
          when 'monthly_statement' then pref.monthly_statements
          when 'manual' then pref.manual_messages
          else true
        end,
        true
      ) = true
    order by d.next_attempt_at, d.created_at
    for update of d skip locked
    limit greatest(1, least(coalesce(p_limit,25),100))
  ), claimed as (
    update private.telegram_autopilot_deliveries d
    set status = 'processing',
        attempt_count = d.attempt_count + 1,
        locked_at = now(),
        updated_at = now()
    from picked p
    where d.id = p.id
    returning d.*
  )
  select
    c.id,
    c.outbox_id,
    c.market_id,
    c.customer_id,
    o.event_type,
    o.event_record_id,
    o.payload,
    o.deep_link,
    c.attempt_count,
    c.max_attempts,
    tc.chat_id
  from claimed c
  join public.notification_outbox o on o.id = c.outbox_id
  left join private.telegram_credentials tc on tc.user_id = c.customer_id
  order by c.created_at;
$$;

revoke all on function public.claim_telegram_autopilot_deliveries_service(integer) from public, anon, authenticated;
grant execute on function public.claim_telegram_autopilot_deliveries_service(integer) to service_role;

create or replace function public.finish_telegram_autopilot_delivery_service(
  p_delivery_id uuid,
  p_status text,
  p_error text default null,
  p_provider_message_id text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_status not in ('sent','skipped','failed') then
    raise exception 'invalid_telegram_delivery_status';
  end if;

  update private.telegram_autopilot_deliveries d
  set status = p_status,
      provider_message_id = nullif(p_provider_message_id,''),
      last_error = nullif(left(coalesce(p_error,''),500),''),
      sent_at = case when p_status = 'sent' then now() else d.sent_at end,
      locked_at = null,
      updated_at = now()
  where d.id = p_delivery_id
    and d.status = 'processing';

  return found;
end;
$$;

revoke all on function public.finish_telegram_autopilot_delivery_service(uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.finish_telegram_autopilot_delivery_service(uuid,text,text,text) to service_role;

create or replace function public.retry_telegram_autopilot_delivery_service(
  p_delivery_id uuid,
  p_error text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempt integer;
  v_max integer;
begin
  select d.attempt_count, d.max_attempts
  into v_attempt, v_max
  from private.telegram_autopilot_deliveries d
  where d.id = p_delivery_id
    and d.status = 'processing'
  for update;

  if not found then
    return false;
  end if;

  update private.telegram_autopilot_deliveries d
  set status = case when v_attempt >= v_max then 'failed' else 'retrying' end,
      next_attempt_at = case
        when v_attempt >= v_max then d.next_attempt_at
        when v_attempt <= 1 then now() + interval '1 minute'
        when v_attempt = 2 then now() + interval '5 minutes'
        when v_attempt = 3 then now() + interval '30 minutes'
        when v_attempt = 4 then now() + interval '2 hours'
        else now() + interval '6 hours'
      end,
      last_error = nullif(left(coalesce(p_error,''),500),''),
      locked_at = null,
      updated_at = now()
  where d.id = p_delivery_id;

  return true;
end;
$$;

revoke all on function public.retry_telegram_autopilot_delivery_service(uuid,text) from public, anon, authenticated;
grant execute on function public.retry_telegram_autopilot_delivery_service(uuid,text) to service_role;

create or replace function private.invoke_telegram_autopilot_worker_service()
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
  if v_secret is null then
    raise exception 'customer_push_worker_secret_missing';
  end if;

  select net.http_post(
    url := 'https://madoflmbretqghqbqaak.supabase.co/functions/v1/telegram-autopilot-worker',
    body := '{}'::jsonb,
    params := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'x-zhirox-push-worker',v_secret
    ),
    timeout_milliseconds := 10000
  ) into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function private.invoke_telegram_autopilot_worker_service() from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from cron.job where jobname = 'zhirox-telegram-autopilot-worker') then
    perform cron.schedule(
      'zhirox-telegram-autopilot-worker',
      '* * * * *',
      'select private.invoke_telegram_autopilot_worker_service();'
    );
  end if;
end;
$$;
