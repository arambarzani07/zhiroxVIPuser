create table if not exists private.market_daily_digest_settings (
  admin_user_id uuid primary key references public.profiles(id) on delete cascade,
  enabled boolean not null default true,
  timezone text not null default 'Asia/Baghdad',
  local_hour smallint not null default 23 check (local_hour between 0 and 23),
  local_minute smallint not null default 59 check (local_minute between 0 and 59),
  last_sent_local_date date,
  last_sent_at timestamptz,
  last_error text,
  processing_local_date date,
  processing_started_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists private.market_daily_digest_deliveries (
  admin_user_id uuid not null references public.profiles(id) on delete cascade,
  local_date date not null,
  market_name text,
  status text not null default 'processing' check (status in ('processing','sent','failed')),
  attempt_count integer not null default 1 check (attempt_count > 0),
  transaction_count integer not null default 0,
  sent_at timestamptz,
  last_error text,
  updated_at timestamptz not null default now(),
  primary key (admin_user_id, local_date)
);

create index if not exists market_daily_digest_processing_idx
  on private.market_daily_digest_settings(processing_started_at)
  where processing_started_at is not null;

create index if not exists market_daily_digest_delivery_status_idx
  on private.market_daily_digest_deliveries(status, updated_at desc);

revoke all on private.market_daily_digest_settings from public, anon, authenticated;
revoke all on private.market_daily_digest_deliveries from public, anon, authenticated;

insert into private.market_daily_digest_settings(admin_user_id, last_sent_local_date)
select p.id, (timezone('Asia/Baghdad', now())::date - 1)
from public.profiles p
where p.role='admin'
  and p.active=true
  and p.approved=true
  and nullif(btrim(p.market_name),'') is not null
on conflict on constraint market_daily_digest_settings_pkey do nothing;

create or replace function public.claim_market_daily_digest_service()
returns table(
  admin_user_id uuid,
  market_name text,
  chat_id text,
  telegram_username text,
  local_date date,
  timezone text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := now();
  v_row record;
  v_local_now timestamp;
  v_local_date date;
  v_target_date date;
  v_hour int;
  v_minute int;
begin
  insert into private.market_daily_digest_settings(admin_user_id, last_sent_local_date)
  select p.id, (timezone('Asia/Baghdad', v_now)::date - 1)
  from public.profiles p
  where p.role='admin'
    and p.active=true
    and p.approved=true
    and nullif(btrim(p.market_name),'') is not null
  on conflict on constraint market_daily_digest_settings_pkey do nothing;

  for v_row in
    select s.admin_user_id, s.timezone as tz, s.local_hour, s.local_minute,
           s.last_sent_local_date, s.processing_started_at,
           p.market_name,
           tc.chat_id, tc.telegram_username
    from private.market_daily_digest_settings s
    join public.profiles p
      on p.id=s.admin_user_id
     and p.role='admin'
     and p.active=true
     and p.approved=true
     and nullif(btrim(p.market_name),'') is not null
    join private.telegram_credentials tc
      on tc.user_id=s.admin_user_id
     and nullif(btrim(tc.chat_id),'') is not null
    where s.enabled=true
    for update of s skip locked
  loop
    v_local_now := timezone(v_row.tz, v_now);
    v_local_date := v_local_now::date;
    v_hour := extract(hour from v_local_now)::int;
    v_minute := extract(minute from v_local_now)::int;

    if v_hour > v_row.local_hour
       or (v_hour = v_row.local_hour and v_minute >= v_row.local_minute)
    then
      v_target_date := v_local_date;
    else
      v_target_date := v_local_date - 1;
    end if;

    if coalesce(v_row.last_sent_local_date, date '1900-01-01') < v_target_date
       and (v_row.processing_started_at is null or v_row.processing_started_at < v_now - interval '10 minutes')
    then
      update private.market_daily_digest_settings s
      set processing_local_date=v_target_date,
          processing_started_at=v_now,
          last_error=null,
          updated_at=v_now
      where s.admin_user_id=v_row.admin_user_id;

      insert into private.market_daily_digest_deliveries(
        admin_user_id, local_date, market_name, status, attempt_count, updated_at
      ) values (
        v_row.admin_user_id, v_target_date, nullif(btrim(v_row.market_name),''), 'processing', 1, v_now
      )
      on conflict on constraint market_daily_digest_deliveries_pkey do update
      set market_name=excluded.market_name,
          status='processing',
          attempt_count=private.market_daily_digest_deliveries.attempt_count + 1,
          last_error=null,
          updated_at=v_now;

      admin_user_id := v_row.admin_user_id;
      market_name := btrim(v_row.market_name);
      chat_id := v_row.chat_id;
      telegram_username := v_row.telegram_username;
      local_date := v_target_date;
      timezone := v_row.tz;
      return next;
    end if;
  end loop;
end;
$$;

create or replace function public.get_market_daily_transaction_digest_service(
  p_admin_user_id uuid,
  p_local_date date,
  p_timezone text default 'Asia/Baghdad'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_start timestamptz;
  v_end timestamptz;
  v_market_name text;
  v_result jsonb;
begin
  select coalesce(nullif(btrim(p.market_name),''), 'مارکێت')
  into v_market_name
  from public.profiles p
  where p.id=p_admin_user_id
    and p.role='admin'
    and p.active=true
    and p.approved=true;

  if v_market_name is null then
    raise exception 'market_admin_not_found';
  end if;

  v_start := p_local_date::timestamp at time zone p_timezone;
  v_end := (p_local_date + 1)::timestamp at time zone p_timezone;

  with market_customers as (
    select p.id
    from public.profiles p
    where p.role='customer' and p.admin_id=p_admin_user_id
  ),
  day_debts as (
    select d.id, d.customer_id, coalesce(nullif(upper(d.currency),''),'IQD') as currency,
           coalesce(d.amount,0)::numeric as amount
    from public.debts d
    join market_customers c on c.id=d.customer_id
    where coalesce(d.is_deleted,false)=false
      and coalesce(d.custom_date,d.created_at) >= v_start
      and coalesce(d.custom_date,d.created_at) < v_end
  ),
  day_payments as (
    select pay.id, d.customer_id, coalesce(nullif(upper(d.currency),''),'IQD') as currency,
           coalesce(pay.amount,0)::numeric as amount
    from public.payments pay
    join public.debts d on d.id=pay.debt_id
    join market_customers c on c.id=d.customer_id
    where pay.created_at >= v_start
      and pay.created_at < v_end
  ),
  deleted_debts as (
    select d.id
    from public.debts d
    join market_customers c on c.id=d.customer_id
    where coalesce(d.is_deleted,false)=true
      and d.deleted_at >= v_start
      and d.deleted_at < v_end
  ),
  touched as (
    select customer_id from day_debts
    union
    select customer_id from day_payments
  ),
  outstanding as (
    select coalesce(nullif(upper(d.currency),''),'IQD') as currency,
           sum(greatest(coalesce(d.remaining,0),0))::numeric as amount,
           count(*) filter (where coalesce(d.remaining,0)>0)::int as open_count
    from public.debts d
    join market_customers c on c.id=d.customer_id
    where coalesce(d.is_deleted,false)=false
    group by 1
  )
  select jsonb_build_object(
    'admin_user_id', p_admin_user_id,
    'market_name', v_market_name,
    'local_date', p_local_date,
    'timezone', p_timezone,
    'debt_count', (select count(*)::int from day_debts),
    'debt_iqd', coalesce((select sum(amount) from day_debts where currency='IQD'),0),
    'debt_usd', coalesce((select sum(amount) from day_debts where currency='USD'),0),
    'payment_count', (select count(*)::int from day_payments),
    'payment_iqd', coalesce((select sum(amount) from day_payments where currency='IQD'),0),
    'payment_usd', coalesce((select sum(amount) from day_payments where currency='USD'),0),
    'customer_count', (select count(*)::int from touched),
    'deleted_debt_count', (select count(*)::int from deleted_debts),
    'outstanding_iqd', coalesce((select amount from outstanding where currency='IQD'),0),
    'outstanding_usd', coalesce((select amount from outstanding where currency='USD'),0),
    'open_debt_count', coalesce((select sum(open_count)::int from outstanding),0),
    'transaction_count', ((select count(*) from day_debts) + (select count(*) from day_payments))::int
  ) into v_result;

  return v_result;
end;
$$;

create or replace function public.finish_market_daily_digest_service(
  p_admin_user_id uuid,
  p_local_date date,
  p_success boolean,
  p_transaction_count integer default 0,
  p_error text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.market_daily_digest_settings
  set last_sent_local_date = case when p_success then p_local_date else last_sent_local_date end,
      last_sent_at = case when p_success then now() else last_sent_at end,
      last_error = case when p_success then null else left(coalesce(p_error,'delivery_failed'),500) end,
      processing_local_date = null,
      processing_started_at = null,
      updated_at = now()
  where admin_user_id=p_admin_user_id;

  update private.market_daily_digest_deliveries
  set status = case when p_success then 'sent' else 'failed' end,
      transaction_count = greatest(coalesce(p_transaction_count,0),0),
      sent_at = case when p_success then now() else sent_at end,
      last_error = case when p_success then null else left(coalesce(p_error,'delivery_failed'),500) end,
      updated_at = now()
  where admin_user_id=p_admin_user_id and local_date=p_local_date;
end;
$$;

revoke all on function public.claim_market_daily_digest_service() from public, anon, authenticated;
revoke all on function public.get_market_daily_transaction_digest_service(uuid,date,text) from public, anon, authenticated;
revoke all on function public.finish_market_daily_digest_service(uuid,date,boolean,integer,text) from public, anon, authenticated;
grant execute on function public.claim_market_daily_digest_service() to service_role;
grant execute on function public.get_market_daily_transaction_digest_service(uuid,date,text) to service_role;
grant execute on function public.finish_market_daily_digest_service(uuid,date,boolean,integer,text) to service_role;

create or replace function private.invoke_market_daily_digest_worker_service()
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
    url := 'https://madoflmbretqghqbqaak.supabase.co/functions/v1/market-daily-transactions-worker',
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

revoke all on function private.invoke_market_daily_digest_worker_service() from public, anon, authenticated;

select cron.schedule(
  'zhirox-market-daily-transactions-worker',
  '* * * * *',
  $cron$select private.invoke_market_daily_digest_worker_service();$cron$
);