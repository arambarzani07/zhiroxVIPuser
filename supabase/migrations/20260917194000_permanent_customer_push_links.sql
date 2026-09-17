-- Customer QR/Web Push links are permanent and reusable until an authorized
-- manager explicitly revokes them. Raw tokens remain hash-only at rest.

alter table public.customer_push_link_tokens
  alter column expires_at drop not null;

-- Preserve every legacy link that has not been explicitly revoked. A link that
-- was consumed under the previous one-time policy becomes reusable again.
update public.customer_push_link_tokens
set expires_at = null,
    used_at = null
where revoked_at is null;

drop index if exists public.customer_push_link_redeemable_idx;
create index customer_push_link_redeemable_idx
  on public.customer_push_link_tokens(token_hash)
  where revoked_at is null;

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
    and (tenant.is_system_owner or tenant.subscription_end is null or tenant.subscription_end >= now());

  if v_market_id is null then
    raise exception 'push_forbidden' using errcode = '42501';
  end if;

  -- p_expires_at is retained in the RPC signature for backwards compatibility.
  -- New links intentionally store no expiry and do not replace older links.
  insert into public.customer_push_link_tokens(
    market_id, customer_id, token_hash, expires_at, created_by
  ) values (
    v_market_id, p_customer, p_token_hash, null, p_actor
  )
  returning id into v_id;

  return jsonb_build_object(
    'id', v_id,
    'market_id', v_market_id,
    'customer_id', p_customer,
    'expires_at', null
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
  v_link_count integer := 0;
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

  select count(*)::integer
  into v_link_count
  from public.customer_push_link_tokens link
  where link.market_id = v_market_id
    and link.customer_id = p_customer
    and link.revoked_at is null;

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
    'active_link_count', v_link_count,
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
    and link.revoked_at is null
    and customer.role = 'customer'
    and customer.active = true
    and customer.approved = true
    and tenant.role = 'admin'
    and tenant.active = true
    and tenant.approved = true
    and (tenant.is_system_owner or tenant.subscription_end is null or tenant.subscription_end >= now())
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

  select link.* into v_link
  from public.customer_push_link_tokens link
  join public.profiles customer on customer.id = link.customer_id
  join public.profiles tenant on tenant.id = link.market_id
  where link.token_hash = p_token_hash
    and link.revoked_at is null
    and customer.role = 'customer'
    and customer.active = true
    and customer.approved = true
    and tenant.role = 'admin'
    and tenant.active = true
    and tenant.approved = true
    and (tenant.is_system_owner or tenant.subscription_end is null or tenant.subscription_end >= now())
  for update of link;

  if not found then
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

  return jsonb_build_object(
    'subscription_id', v_subscription_id,
    'market_id', v_link.market_id,
    'customer_id', v_link.customer_id
  );
end;
$$;

-- The customer portal must follow the same permanent-link semantics. A valid
-- unrevoked link can reopen the portal and can subscribe additional devices.
create or replace function public.read_customer_push_portal_service(
  p_token_hash text default null,
  p_endpoint text default null,
  p_device_secret_hash text default null,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer_id uuid;
  v_market_id uuid;
  v_customer_name text;
  v_market_name text;
  v_debt_limit numeric;
  v_can_subscribe boolean := false;
  v_offset integer := greatest(0, least(coalesce(p_offset, 0), 1000000));
  v_totals jsonb := '[]'::jsonb;
  v_rows jsonb := '[]'::jsonb;
begin
  if p_token_hash is not null and p_token_hash ~ '^[a-f0-9]{64}$' then
    select link.customer_id, link.market_id, true
    into v_customer_id, v_market_id, v_can_subscribe
    from public.customer_push_link_tokens link
    where link.token_hash = p_token_hash
      and link.revoked_at is null
    limit 1;
  elsif nullif(trim(coalesce(p_endpoint, '')), '') is not null
        and p_device_secret_hash is not null
        and p_device_secret_hash ~ '^[a-f0-9]{64}$' then
    select subscription.customer_id, subscription.market_id
    into v_customer_id, v_market_id
    from public.customer_push_subscriptions subscription
    where subscription.endpoint = p_endpoint
      and subscription.device_secret_hash = p_device_secret_hash
      and subscription.active = true
    limit 1;
  end if;

  select customer.name, tenant.market_name, customer.debt_limit
  into v_customer_name, v_market_name, v_debt_limit
  from public.profiles customer
  join public.profiles tenant on tenant.id = v_market_id
  where customer.id = v_customer_id
    and customer.admin_id = v_market_id
    and customer.role = 'customer'
    and customer.active = true
    and customer.approved = true
    and tenant.role = 'admin'
    and tenant.active = true
    and tenant.approved = true
    and (tenant.is_system_owner or tenant.subscription_end is null or tenant.subscription_end >= now());

  if v_customer_name is null then
    raise no_data_found;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'currency', totals.currency,
    'total_debt', totals.total_debt,
    'remaining', totals.remaining,
    'paid', totals.paid
  ) order by totals.currency), '[]'::jsonb)
  into v_totals
  from (
    select d.currency,
           coalesce(sum(d.amount), 0) as total_debt,
           coalesce(sum(d.remaining), 0) as remaining,
           coalesce(sum(d.amount - d.remaining), 0) as paid
    from public.debts d
    where d.customer_id = v_customer_id and d.is_deleted = false
    group by d.currency
  ) totals;

  select coalesce(jsonb_agg(to_jsonb(item) order by item.occurred_at desc, item.kind, item.id), '[]'::jsonb)
  into v_rows
  from (
    select *
    from (
      select d.id,
             'debt'::text as kind,
             d.amount,
             d.remaining,
             d.currency,
             coalesce(d.custom_date, d.created_at) as occurred_at,
             d.due_date,
             d.status,
             d.description as note
      from public.debts d
      where d.customer_id = v_customer_id and d.is_deleted = false
      union all
      select p.id,
             'payment'::text as kind,
             p.amount,
             null::numeric as remaining,
             d.currency,
             p.created_at as occurred_at,
             null::date as due_date,
             null::text as status,
             p.note
      from public.payments p
      join public.debts d on d.id = p.debt_id
      where d.customer_id = v_customer_id and d.is_deleted = false
    ) ledger
    order by occurred_at desc, kind, id
    limit 51 offset v_offset
  ) item;

  return jsonb_build_object(
    'customer_name', v_customer_name,
    'market_name', v_market_name,
    'debt_limit', v_debt_limit,
    'can_subscribe', v_can_subscribe,
    'totals', v_totals,
    'rows', v_rows,
    'offset', v_offset,
    'has_more', jsonb_array_length(v_rows) > 50
  ) || jsonb_build_object(
    'rows', case when jsonb_array_length(v_rows) > 50 then v_rows - 50 else v_rows end
  );
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
revoke all on function public.read_customer_push_portal_service(text,text,text,integer)
  from public, anon, authenticated;

grant execute on function public.manage_customer_push_link(uuid,uuid,text,timestamptz) to service_role;
grant execute on function public.customer_push_status_service(uuid,uuid) to service_role;
grant execute on function public.revoke_customer_push_subscriptions_service(uuid,uuid) to service_role;
grant execute on function public.inspect_customer_push_link_service(text) to service_role;
grant execute on function public.redeem_customer_push_subscription_service(text,text,text,text,text,text,text) to service_role;
grant execute on function public.read_customer_push_portal_service(text,text,text,integer) to service_role;
