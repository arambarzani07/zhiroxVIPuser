-- Correct the active-customer approval guard in manual push target selection.
create or replace function public.enqueue_manual_customer_push_service(
  p_actor uuid,
  p_customer uuid,
  p_message text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_market_name text;
  v_message text;
  v_audience text;
  v_queued_customers integer := 0;
  v_target_devices integer := 0;
  v_existing public.customer_manual_push_campaigns%rowtype;
begin
  if p_actor is null or p_request_id is null then
    raise exception 'invalid_manual_push_request' using errcode = '22023';
  end if;

  v_message := trim(coalesce(p_message, ''));
  if char_length(v_message) < 1 or char_length(v_message) > 240 then
    raise exception 'invalid_message' using errcode = '22023';
  end if;

  select coalesce(
           nullif(trim(actor.market_name), ''),
           nullif(trim(actor.name), ''),
           'ZHIROX'
         )
  into v_market_name
  from public.profiles actor
  where actor.id = p_actor
    and actor.role = 'admin'
    and actor.active = true
    and actor.approved = true
    and (actor.is_system_owner = true
         or actor.subscription_end is null
         or actor.subscription_end >= now());

  if v_market_name is null then
    raise exception 'manual_push_forbidden' using errcode = '42501';
  end if;

  select *
  into v_existing
  from public.customer_manual_push_campaigns
  where id = p_request_id;

  if found then
    if v_existing.market_id <> p_actor or v_existing.actor_id <> p_actor then
      raise exception 'manual_push_forbidden' using errcode = '42501';
    end if;
    return jsonb_build_object(
      'campaign_id', v_existing.id,
      'queued_customers', v_existing.queued_customer_count,
      'target_devices', v_existing.target_device_count,
      'market_name', v_existing.market_name
    );
  end if;

  if p_customer is not null then
    perform 1
    from public.profiles customer
    where customer.id = p_customer
      and customer.role = 'customer'
      and customer.admin_id = p_actor
      and customer.active = true
      and customer.approved = true;

    if not found then
      raise exception 'manual_push_forbidden' using errcode = '42501';
    end if;
    v_audience := 'single';
  else
    v_audience := 'broadcast';
  end if;

  insert into public.customer_manual_push_campaigns(
    id,
    market_id,
    actor_id,
    target_customer_id,
    audience,
    market_name,
    message
  ) values (
    p_request_id,
    p_actor,
    p_actor,
    p_customer,
    v_audience,
    v_market_name,
    v_message
  );

  with targets as (
    select distinct subscription.customer_id
    from public.customer_push_subscriptions subscription
    join public.profiles customer on customer.id = subscription.customer_id
    where subscription.market_id = p_actor
      and subscription.active = true
      and customer.role = 'customer'
      and customer.admin_id = p_actor
      and customer.active = true
      and customer.approved = true
      and (p_customer is null or customer.id = p_customer)
  )
  insert into public.notification_outbox(
    market_id,
    customer_id,
    event_type,
    event_record_id,
    idempotency_key,
    payload
  )
  select
    p_actor,
    target.customer_id,
    'manual',
    p_request_id,
    'manual:' || p_request_id::text || ':' || target.customer_id::text,
    jsonb_build_object(
      'market_name', v_market_name,
      'message', v_message,
      'occurred_at', now(),
      'campaign_id', p_request_id
    )
  from targets target
  on conflict (idempotency_key) do nothing;

  get diagnostics v_queued_customers = row_count;

  select count(*)::integer
  into v_target_devices
  from public.customer_push_subscriptions subscription
  join public.profiles customer on customer.id = subscription.customer_id
  where subscription.market_id = p_actor
    and subscription.active = true
    and customer.role = 'customer'
    and customer.admin_id = p_actor
    and customer.active = true
    and customer.approved = true
    and (p_customer is null or customer.id = p_customer);

  update public.customer_manual_push_campaigns
  set queued_customer_count = v_queued_customers,
      target_device_count = v_target_devices
  where id = p_request_id;

  return jsonb_build_object(
    'campaign_id', p_request_id,
    'queued_customers', v_queued_customers,
    'target_devices', v_target_devices,
    'market_name', v_market_name
  );
end;
$$;

revoke all on function public.enqueue_manual_customer_push_service(uuid, uuid, text, uuid)
  from public, anon, authenticated;
grant execute on function public.enqueue_manual_customer_push_service(uuid, uuid, text, uuid)
  to service_role;
