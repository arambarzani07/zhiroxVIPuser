-- Read-only customer notification history for the installed portal.

create or replace function public.read_customer_push_notification_history_service(
  p_token_hash text default null,
  p_endpoint text default null,
  p_device_secret_hash text default null,
  p_limit integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer_id uuid;
  v_market_id uuid;
  v_limit integer := greatest(1, least(coalesce(p_limit, 20), 50));
  v_items jsonb := '[]'::jsonb;
begin
  if p_token_hash is not null and p_token_hash ~ '^[a-f0-9]{64}$' then
    select link.customer_id, link.market_id
    into v_customer_id, v_market_id
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

  perform 1
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

  if not found then
    raise no_data_found;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', row.id,
        'event_type', row.event_type,
        'status', row.delivery_status,
        'created_at', row.created_at,
        'message', row.message,
        'amount', row.amount,
        'currency', row.currency
      )
      order by row.created_at desc, row.id desc
    ),
    '[]'::jsonb
  )
  into v_items
  from (
    select
      o.id,
      o.event_type,
      o.created_at,
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
        when coalesce(del.failed_count, 0) + coalesce(del.expired_count, 0) > 0
          then 'failed'
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
        count(*) filter (where d.status = 'pending')::integer as pending_count
      from public.notification_deliveries d
      where d.outbox_id = o.id
    ) del on true
    where o.market_id = v_market_id
      and o.customer_id = v_customer_id
    order by o.created_at desc, o.id desc
    limit v_limit
  ) row;

  return jsonb_build_object('items', v_items, 'limit', v_limit);
end;
$$;

revoke all on function public.read_customer_push_notification_history_service(text,text,text,integer)
  from public, anon, authenticated;
grant execute on function public.read_customer_push_notification_history_service(text,text,text,integer)
  to service_role;
