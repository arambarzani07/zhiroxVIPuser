-- Customer push observability and safe manual retry controls.
-- Provides manager-visible delivery history without exposing push endpoints/keys.

create or replace function public.read_customer_push_history_service(
  p_actor uuid,
  p_customer uuid,
  p_limit integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_market_id uuid;
  v_limit integer := greatest(1, least(coalesce(p_limit, 20), 100));
  v_items jsonb := '[]'::jsonb;
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

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', item.id,
        'event_type', item.event_type,
        'status', item.delivery_status,
        'created_at', item.created_at,
        'completed_at', item.completed_at,
        'sent_count', item.sent_count,
        'failed_count', item.failed_count,
        'expired_count', item.expired_count,
        'pending_count', item.pending_count,
        'device_count', item.device_count,
        'attempt_count', item.attempt_count,
        'last_error', item.last_error,
        'message', item.message,
        'amount', item.amount,
        'currency', item.currency
      )
      order by item.created_at desc, item.id desc
    ),
    '[]'::jsonb
  )
  into v_items
  from (
    select
      o.id,
      o.event_type,
      o.created_at,
      o.completed_at,
      coalesce(del.sent_count, 0)::integer as sent_count,
      coalesce(del.failed_count, 0)::integer as failed_count,
      coalesce(del.expired_count, 0)::integer as expired_count,
      coalesce(del.pending_count, 0)::integer as pending_count,
      coalesce(del.device_count, 0)::integer as device_count,
      greatest(o.attempt_count, coalesce(del.max_attempt_count, 0))::integer as attempt_count,
      coalesce(del.last_error, o.last_error) as last_error,
      nullif(o.payload ->> 'message', '') as message,
      case
        when (o.payload ->> 'amount') ~ '^-?[0-9]+([.][0-9]+)?$'
          then (o.payload ->> 'amount')::numeric
        else null
      end as amount,
      nullif(o.payload ->> 'currency', '') as currency,
      case
        when coalesce(del.device_count, 0) = 0 then 'no_device'
        when coalesce(del.pending_count, 0) > 0 then 'pending'
        when coalesce(del.sent_count, 0) > 0
             and coalesce(del.failed_count, 0) + coalesce(del.expired_count, 0) > 0
          then 'partial'
        when coalesce(del.sent_count, 0) > 0 then 'sent'
        when coalesce(del.failed_count, 0) + coalesce(del.expired_count, 0) > 0 then 'failed'
        when o.status in ('pending', 'processing') then 'pending'
        when o.status = 'failed' then 'failed'
        else 'no_device'
      end as delivery_status
    from public.notification_outbox o
    left join lateral (
      select
        count(*)::integer as device_count,
        count(*) filter (where d.status = 'sent')::integer as sent_count,
        count(*) filter (where d.status = 'failed')::integer as failed_count,
        count(*) filter (where d.status = 'expired')::integer as expired_count,
        count(*) filter (where d.status = 'pending')::integer as pending_count,
        max(d.attempt_count)::integer as max_attempt_count,
        (array_agg(d.last_error order by d.updated_at desc, d.id desc)
          filter (where nullif(d.last_error, '') is not null))[1] as last_error
      from public.notification_deliveries d
      where d.outbox_id = o.id
    ) del on true
    where o.market_id = v_market_id
      and o.customer_id = p_customer
    order by o.created_at desc, o.id desc
    limit v_limit
  ) item;

  return jsonb_build_object(
    'items', v_items,
    'limit', v_limit
  );
end;
$$;


create or replace function public.retry_customer_push_service(
  p_actor uuid,
  p_customer uuid,
  p_outbox_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_market_id uuid;
  v_event public.notification_outbox%rowtype;
  v_active_devices integer := 0;
  v_retry_devices integer := 0;
begin
  if p_outbox_id is null then
    raise exception 'invalid_push_retry' using errcode = '22023';
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

  select *
  into v_event
  from public.notification_outbox o
  where o.id = p_outbox_id
    and o.market_id = v_market_id
    and o.customer_id = p_customer
  for update;

  if not found then
    raise exception 'push_event_not_found' using errcode = 'P0002';
  end if;

  select count(*)::integer
  into v_active_devices
  from public.customer_push_subscriptions s
  where s.market_id = v_market_id
    and s.customer_id = p_customer
    and s.active = true;

  if v_active_devices = 0 then
    raise exception 'no_active_push_subscription' using errcode = 'P0001';
  end if;

  insert into public.notification_deliveries(
    outbox_id,
    subscription_id,
    status,
    attempt_count,
    provider_status,
    last_error,
    next_attempt_at,
    sent_at,
    updated_at
  )
  select
    v_event.id,
    s.id,
    'pending',
    0,
    null,
    null,
    now(),
    null,
    now()
  from public.customer_push_subscriptions s
  where s.market_id = v_market_id
    and s.customer_id = p_customer
    and s.active = true
  on conflict (outbox_id, subscription_id) do update
  set status = case
        when public.notification_deliveries.status = 'sent'
          then public.notification_deliveries.status
        else 'pending'
      end,
      provider_status = case
        when public.notification_deliveries.status = 'sent'
          then public.notification_deliveries.provider_status
        else null
      end,
      last_error = case
        when public.notification_deliveries.status = 'sent'
          then public.notification_deliveries.last_error
        else null
      end,
      next_attempt_at = case
        when public.notification_deliveries.status = 'sent'
          then public.notification_deliveries.next_attempt_at
        else now()
      end,
      sent_at = case
        when public.notification_deliveries.status = 'sent'
          then public.notification_deliveries.sent_at
        else null
      end,
      updated_at = now();

  select count(*)::integer
  into v_retry_devices
  from public.notification_deliveries d
  join public.customer_push_subscriptions s on s.id = d.subscription_id
  where d.outbox_id = v_event.id
    and s.active = true
    and s.market_id = v_market_id
    and s.customer_id = p_customer
    and d.status = 'pending';

  if v_retry_devices = 0 then
    return jsonb_build_object(
      'outbox_id', v_event.id,
      'retry_devices', 0,
      'already_sent', true
    );
  end if;

  update public.notification_outbox
  set status = 'pending',
      next_attempt_at = now(),
      completed_at = null,
      last_error = null
  where id = v_event.id;

  return jsonb_build_object(
    'outbox_id', v_event.id,
    'retry_devices', v_retry_devices,
    'already_sent', false
  );
end;
$$;

revoke all on function public.read_customer_push_history_service(uuid,uuid,integer)
  from public, anon, authenticated;
revoke all on function public.retry_customer_push_service(uuid,uuid,uuid)
  from public, anon, authenticated;

grant execute on function public.read_customer_push_history_service(uuid,uuid,integer)
  to service_role;
grant execute on function public.retry_customer_push_service(uuid,uuid,uuid)
  to service_role;
