-- Manager notification center: paginated customer push overview.

create or replace function public.list_customer_push_overview_service(
  p_actor uuid,
  p_search text default '',
  p_limit integer default 60,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_market_id uuid;
  v_search text := trim(coalesce(p_search, ''));
  v_limit integer := greatest(1, least(coalesce(p_limit, 60), 100));
  v_offset integer := greatest(0, coalesce(p_offset, 0));
  v_rows jsonb := '[]'::jsonb;
  v_total integer := 0;
begin
  select case
    when actor.role = 'admin' then actor.id
    when actor.role = 'employee' and actor.can_send_notifications = true then actor.admin_id
  end
  into v_market_id
  from public.profiles actor
  join public.profiles tenant
    on tenant.id = case
      when actor.role = 'admin' then actor.id
      else actor.admin_id
    end
   and tenant.role = 'admin'
   and tenant.active = true
   and tenant.approved = true
   and (tenant.is_system_owner or tenant.subscription_end is null or tenant.subscription_end >= now())
  where actor.id = p_actor
    and actor.active = true
    and actor.approved = true
    and actor.role in ('admin', 'employee');

  if v_market_id is null then
    raise exception 'push_forbidden' using errcode = '42501';
  end if;

  select count(*)::integer
  into v_total
  from public.profiles customer
  where customer.role = 'customer'
    and customer.admin_id = v_market_id
    and customer.active = true
    and customer.approved = true
    and (
      v_search = ''
      or customer.name ilike '%' || v_search || '%'
      or coalesce(customer.phone, '') ilike '%' || v_search || '%'
    );

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'customer_id', row.customer_id,
        'name', row.name,
        'phone', row.phone,
        'active', row.device_count > 0,
        'device_count', row.device_count,
        'active_link_count', row.active_link_count,
        'latest_status', row.latest_status,
        'latest_at', row.latest_at
      )
      order by row.name, row.customer_id
    ),
    '[]'::jsonb
  )
  into v_rows
  from (
    select
      customer.id as customer_id,
      customer.name,
      coalesce(customer.phone, '') as phone,
      coalesce(subs.device_count, 0)::integer as device_count,
      coalesce(links.active_link_count, 0)::integer as active_link_count,
      latest.latest_status,
      latest.latest_at
    from public.profiles customer
    left join lateral (
      select count(*)::integer as device_count
      from public.customer_push_subscriptions s
      where s.market_id = v_market_id
        and s.customer_id = customer.id
        and s.active = true
    ) subs on true
    left join lateral (
      select count(*)::integer as active_link_count
      from public.customer_push_link_tokens link
      where link.market_id = v_market_id
        and link.customer_id = customer.id
        and link.revoked_at is null
    ) links on true
    left join lateral (
      select
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
        end as latest_status,
        coalesce(o.completed_at, o.created_at) as latest_at
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
        and o.customer_id = customer.id
      order by o.created_at desc, o.id desc
      limit 1
    ) latest on true
    where customer.role = 'customer'
      and customer.admin_id = v_market_id
      and customer.active = true
      and customer.approved = true
      and (
        v_search = ''
        or customer.name ilike '%' || v_search || '%'
        or coalesce(customer.phone, '') ilike '%' || v_search || '%'
      )
    order by customer.name, customer.id
    limit v_limit offset v_offset
  ) row;

  return jsonb_build_object(
    'items', v_rows,
    'total_count', v_total,
    'offset', v_offset,
    'limit', v_limit,
    'has_more', v_offset + jsonb_array_length(v_rows) < v_total
  );
end;
$$;

revoke all on function public.list_customer_push_overview_service(uuid,text,integer,integer)
  from public, anon, authenticated;
grant execute on function public.list_customer_push_overview_service(uuid,text,integer,integer)
  to service_role;
