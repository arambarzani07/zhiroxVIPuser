create table public.customer_push_link_tokens (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  token_hash text not null unique check (token_hash ~ '^[a-f0-9]{64}$'),
  expires_at timestamptz not null,
  used_at timestamptz,
  revoked_at timestamptz,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create index customer_push_link_customer_idx
  on public.customer_push_link_tokens(market_id, customer_id, created_at desc);
create index customer_push_link_redeemable_idx
  on public.customer_push_link_tokens(token_hash)
  where used_at is null and revoked_at is null;

create table public.customer_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth text not null,
  device_secret_hash text not null check (device_secret_hash ~ '^[a-f0-9]{64}$'),
  user_agent text,
  platform text,
  active boolean not null default true,
  last_success_at timestamptz,
  last_failure_at timestamptz,
  failure_count integer not null default 0 check (failure_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index customer_push_active_endpoint_uq
  on public.customer_push_subscriptions(endpoint) where active = true;
create index customer_push_subscription_customer_idx
  on public.customer_push_subscriptions(market_id, customer_id, active);

create table public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  event_type text not null check (event_type in ('debt_created','payment_created')),
  event_record_id uuid not null,
  idempotency_key text not null unique,
  payload jsonb not null,
  status text not null default 'pending'
    check (status in ('pending','processing','completed','failed')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  next_attempt_at timestamptz not null default now(),
  fanout_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create index notification_outbox_due_idx
  on public.notification_outbox(status, next_attempt_at, created_at)
  where status in ('pending','processing');
create index notification_outbox_customer_idx
  on public.notification_outbox(market_id, customer_id, created_at desc);

create table public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  outbox_id uuid not null references public.notification_outbox(id) on delete cascade,
  subscription_id uuid not null references public.customer_push_subscriptions(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','sent','failed','expired')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  provider_status integer,
  last_error text,
  next_attempt_at timestamptz,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(outbox_id, subscription_id)
);

create index notification_deliveries_due_idx
  on public.notification_deliveries(status, next_attempt_at, created_at)
  where status = 'pending';
create index notification_deliveries_subscription_idx
  on public.notification_deliveries(subscription_id, updated_at desc);

create table public.customer_push_rate_limits (
  key_hash text primary key check (key_hash ~ '^[a-f0-9]{64}$'),
  window_started_at timestamptz not null default now(),
  request_count integer not null default 0 check (request_count >= 0),
  expires_at timestamptz not null
);

alter table public.customer_push_link_tokens enable row level security;
alter table public.customer_push_subscriptions enable row level security;
alter table public.notification_outbox enable row level security;
alter table public.notification_deliveries enable row level security;
alter table public.customer_push_rate_limits enable row level security;

revoke all on table public.customer_push_link_tokens from public, anon, authenticated;
revoke all on table public.customer_push_subscriptions from public, anon, authenticated;
revoke all on table public.notification_outbox from public, anon, authenticated;
revoke all on table public.notification_deliveries from public, anon, authenticated;
revoke all on table public.customer_push_rate_limits from public, anon, authenticated;

grant select, insert, update, delete on table public.customer_push_link_tokens to service_role;
grant select, insert, update, delete on table public.customer_push_subscriptions to service_role;
grant select, insert, update, delete on table public.notification_outbox to service_role;
grant select, insert, update, delete on table public.notification_deliveries to service_role;
grant select, insert, update, delete on table public.customer_push_rate_limits to service_role;

create or replace function public.manage_customer_push_link(
  p_actor uuid,
  p_customer uuid,
  p_token_hash text,
  p_expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_market_id uuid;
  v_id uuid;
begin
  if p_token_hash is null or p_token_hash !~ '^[a-f0-9]{64}$' then
    raise exception 'invalid_push_token_hash' using errcode = '22023';
  end if;

  select case
    when actor.role = 'admin' and actor.id = customer.admin_id then customer.admin_id
    when actor.role = 'employee'
         and actor.admin_id = customer.admin_id
         and actor.can_send_notifications = true then customer.admin_id
  end
  into v_market_id
  from public.profiles actor
  join public.profiles customer on customer.id = p_customer
  join public.profiles tenant on tenant.id = customer.admin_id
  where actor.id = p_actor
    and actor.active = true
    and actor.approved = true
    and customer.role = 'customer'
    and customer.active = true
    and customer.approved = true
    and tenant.role = 'admin'
    and tenant.active = true
    and tenant.approved = true
    and (tenant.subscription_end is null or tenant.subscription_end >= now());

  if v_market_id is null then
    raise exception 'push_forbidden' using errcode = '42501';
  end if;

  update public.customer_push_link_tokens
  set revoked_at = now()
  where market_id = v_market_id
    and customer_id = p_customer
    and used_at is null
    and revoked_at is null;

  insert into public.customer_push_link_tokens(
    market_id, customer_id, token_hash, expires_at, created_by
  ) values (
    v_market_id, p_customer, p_token_hash, p_expires_at, p_actor
  )
  returning id into v_id;

  return jsonb_build_object(
    'id', v_id,
    'market_id', v_market_id,
    'customer_id', p_customer,
    'expires_at', p_expires_at
  );
end;
$$;

create or replace function public.customer_push_status_service(
  p_actor uuid,
  p_customer uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_market_id uuid;
  v_count integer := 0;
  v_latest_status text;
  v_latest_at timestamptz;
begin
  select case
    when actor.role = 'admin' and actor.id = customer.admin_id then customer.admin_id
    when actor.role = 'employee'
         and actor.admin_id = customer.admin_id
         and actor.can_send_notifications = true then customer.admin_id
  end
  into v_market_id
  from public.profiles actor
  join public.profiles customer on customer.id = p_customer
  where actor.id = p_actor
    and actor.active = true
    and actor.approved = true
    and customer.role = 'customer'
    and customer.active = true
    and customer.approved = true;

  if v_market_id is null then
    raise exception 'push_forbidden' using errcode = '42501';
  end if;

  select count(*)::integer
  into v_count
  from public.customer_push_subscriptions s
  where s.market_id = v_market_id
    and s.customer_id = p_customer
    and s.active = true;

  select d.status, coalesce(d.sent_at, d.updated_at)
  into v_latest_status, v_latest_at
  from public.notification_deliveries d
  join public.customer_push_subscriptions s on s.id = d.subscription_id
  where s.market_id = v_market_id
    and s.customer_id = p_customer
  order by d.updated_at desc, d.id desc
  limit 1;

  return jsonb_build_object(
    'active', v_count > 0,
    'device_count', v_count,
    'latest_status', v_latest_status,
    'latest_at', v_latest_at
  );
end;
$$;

create or replace function public.revoke_customer_push_subscriptions_service(
  p_actor uuid,
  p_customer uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_market_id uuid;
  v_count integer := 0;
begin
  select case
    when actor.role = 'admin' and actor.id = customer.admin_id then customer.admin_id
    when actor.role = 'employee'
         and actor.admin_id = customer.admin_id
         and actor.can_send_notifications = true then customer.admin_id
  end
  into v_market_id
  from public.profiles actor
  join public.profiles customer on customer.id = p_customer
  where actor.id = p_actor
    and actor.active = true
    and actor.approved = true
    and customer.role = 'customer';

  if v_market_id is null then
    raise exception 'push_forbidden' using errcode = '42501';
  end if;

  update public.customer_push_subscriptions
  set active = false,
      updated_at = now()
  where market_id = v_market_id
    and customer_id = p_customer
    and active = true;
  get diagnostics v_count = row_count;

  update public.customer_push_link_tokens
  set revoked_at = now()
  where market_id = v_market_id
    and customer_id = p_customer
    and used_at is null
    and revoked_at is null;

  return v_count;
end;
$$;

create or replace function public.inspect_customer_push_link_service(
  p_token_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'customer_name', customer.name,
    'market_name', tenant.market_name,
    'expires_at', link.expires_at
  )
  into v_result
  from public.customer_push_link_tokens link
  join public.profiles customer on customer.id = link.customer_id
  join public.profiles tenant on tenant.id = link.market_id
  where link.token_hash = p_token_hash
    and link.used_at is null
    and link.revoked_at is null
    and link.expires_at > now()
    and customer.role = 'customer'
    and customer.active = true
    and customer.approved = true
    and tenant.role = 'admin'
    and tenant.active = true
    and tenant.approved = true
    and (tenant.subscription_end is null or tenant.subscription_end >= now())
  limit 1;

  if v_result is null then
    raise no_data_found;
  end if;

  return v_result;
end;
$$;

create or replace function public.redeem_customer_push_subscription_service(
  p_token_hash text,
  p_endpoint text,
  p_p256dh text,
  p_auth text,
  p_device_secret_hash text,
  p_user_agent text,
  p_platform text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_link public.customer_push_link_tokens%rowtype;
  v_existing public.customer_push_subscriptions%rowtype;
  v_subscription_id uuid;
begin
  if p_token_hash is null or p_token_hash !~ '^[a-f0-9]{64}$'
     or p_device_secret_hash is null or p_device_secret_hash !~ '^[a-f0-9]{64}$'
     or nullif(trim(p_endpoint), '') is null
     or nullif(trim(p_p256dh), '') is null
     or nullif(trim(p_auth), '') is null then
    raise exception 'invalid_push_subscription' using errcode = '22023';
  end if;

  select * into v_link
  from public.customer_push_link_tokens
  where token_hash = p_token_hash
  for update;

  if not found
     or v_link.used_at is not null
     or v_link.revoked_at is not null
     or v_link.expires_at <= now() then
    raise no_data_found;
  end if;

  select * into v_existing
  from public.customer_push_subscriptions
  where endpoint = p_endpoint
    and active = true
  for update;

  if found and (
    v_existing.market_id <> v_link.market_id
    or v_existing.customer_id <> v_link.customer_id
  ) then
    raise exception 'push_endpoint_in_use' using errcode = '23505';
  end if;

  if found then
    update public.customer_push_subscriptions
    set p256dh = p_p256dh,
        auth = p_auth,
        device_secret_hash = p_device_secret_hash,
        user_agent = nullif(p_user_agent, ''),
        platform = nullif(p_platform, ''),
        failure_count = 0,
        last_failure_at = null,
        updated_at = now()
    where id = v_existing.id
    returning id into v_subscription_id;
  else
    insert into public.customer_push_subscriptions(
      market_id, customer_id, endpoint, p256dh, auth,
      device_secret_hash, user_agent, platform
    ) values (
      v_link.market_id, v_link.customer_id, p_endpoint, p_p256dh, p_auth,
      p_device_secret_hash, nullif(p_user_agent, ''), nullif(p_platform, '')
    )
    returning id into v_subscription_id;
  end if;

  update public.customer_push_link_tokens
  set used_at = now()
  where id = v_link.id;

  return jsonb_build_object(
    'subscription_id', v_subscription_id,
    'market_id', v_link.market_id,
    'customer_id', v_link.customer_id
  );
end;
$$;

create or replace function public.unsubscribe_customer_push_subscription_service(
  p_endpoint text,
  p_device_secret_hash text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
begin
  update public.customer_push_subscriptions
  set active = false,
      updated_at = now()
  where endpoint = p_endpoint
    and device_secret_hash = p_device_secret_hash
    and active = true;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

create or replace function public.consume_customer_push_rate_limit(
  p_key_hash text,
  p_limit integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.customer_push_rate_limits%rowtype;
begin
  if p_key_hash is null or p_key_hash !~ '^[a-f0-9]{64}$'
     or p_limit is null or p_limit <= 0
     or p_window_seconds is null or p_window_seconds <= 0 then
    raise exception 'invalid_rate_limit_input' using errcode = '22023';
  end if;

  insert into public.customer_push_rate_limits(
    key_hash, window_started_at, request_count, expires_at
  ) values (
    p_key_hash, now(), 0, now() + make_interval(secs => p_window_seconds)
  )
  on conflict (key_hash) do nothing;

  select * into v_row
  from public.customer_push_rate_limits
  where key_hash = p_key_hash
  for update;

  if v_row.expires_at <= now() then
    update public.customer_push_rate_limits
    set window_started_at = now(),
        request_count = 1,
        expires_at = now() + make_interval(secs => p_window_seconds)
    where key_hash = p_key_hash;
    return true;
  end if;

  if v_row.request_count >= p_limit then
    return false;
  end if;

  update public.customer_push_rate_limits
  set request_count = request_count + 1
  where key_hash = p_key_hash;
  return true;
end;
$$;

create or replace function public.enqueue_customer_push_event_service(
  p_market_id uuid,
  p_customer_id uuid,
  p_event_type text,
  p_event_record_id uuid,
  p_idempotency_key text,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_customer_market uuid;
begin
  if p_event_type not in ('debt_created', 'payment_created') then
    raise exception 'unsupported_push_event' using errcode = '23514';
  end if;
  if p_event_record_id is null or nullif(trim(p_idempotency_key), '') is null then
    raise exception 'invalid_push_event' using errcode = '22023';
  end if;

  select customer.admin_id
  into v_customer_market
  from public.profiles customer
  where customer.id = p_customer_id
    and customer.role = 'customer';

  if v_customer_market is null or v_customer_market <> p_market_id then
    raise exception 'push_customer_market_mismatch' using errcode = '42501';
  end if;

  with inserted as (
    insert into public.notification_outbox(
      market_id, customer_id, event_type, event_record_id, idempotency_key, payload
    ) values (
      p_market_id, p_customer_id, p_event_type, p_event_record_id,
      p_idempotency_key, coalesce(p_payload, '{}'::jsonb)
    )
    on conflict (idempotency_key) do nothing
    returning id
  )
  select id into v_id from inserted
  union all
  select id from public.notification_outbox where idempotency_key = p_idempotency_key
  limit 1;

  return v_id;
end;
$$;

create or replace function public.claim_customer_push_outbox(
  p_limit integer default 25
)
returns setof public.notification_outbox
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  with due as (
    select o.id
    from public.notification_outbox o
    where o.status in ('pending', 'processing')
      and o.next_attempt_at <= now()
    order by o.next_attempt_at asc, o.created_at asc, o.id asc
    for update skip locked
    limit greatest(1, least(coalesce(p_limit, 25), 100))
  ), claimed as (
    update public.notification_outbox o
    set status = 'processing',
        next_attempt_at = now() + interval '2 minutes'
    from due
    where o.id = due.id
    returning o.*
  )
  select * from claimed;
end;
$$;

revoke all on function public.manage_customer_push_link(uuid,uuid,text,timestamptz)
  from public, anon, authenticated;
revoke all on function public.customer_push_status_service(uuid,uuid)
  from public, anon, authenticated;
revoke all on function public.revoke_customer_push_subscriptions_service(uuid,uuid)
  from public, anon, authenticated;
revoke all on function public.inspect_customer_push_link_service(text)
  from public, anon, authenticated;
revoke all on function public.redeem_customer_push_subscription_service(text,text,text,text,text,text,text)
  from public, anon, authenticated;
revoke all on function public.unsubscribe_customer_push_subscription_service(text,text)
  from public, anon, authenticated;
revoke all on function public.consume_customer_push_rate_limit(text,integer,integer)
  from public, anon, authenticated;
revoke all on function public.enqueue_customer_push_event_service(uuid,uuid,text,uuid,text,jsonb)
  from public, anon, authenticated;
revoke all on function public.claim_customer_push_outbox(integer)
  from public, anon, authenticated;

grant execute on function public.manage_customer_push_link(uuid,uuid,text,timestamptz) to service_role;
grant execute on function public.customer_push_status_service(uuid,uuid) to service_role;
grant execute on function public.revoke_customer_push_subscriptions_service(uuid,uuid) to service_role;
grant execute on function public.inspect_customer_push_link_service(text) to service_role;
grant execute on function public.redeem_customer_push_subscription_service(text,text,text,text,text,text,text) to service_role;
grant execute on function public.unsubscribe_customer_push_subscription_service(text,text) to service_role;
grant execute on function public.consume_customer_push_rate_limit(text,integer,integer) to service_role;
grant execute on function public.enqueue_customer_push_event_service(uuid,uuid,text,uuid,text,jsonb) to service_role;
grant execute on function public.claim_customer_push_outbox(integer) to service_role;
