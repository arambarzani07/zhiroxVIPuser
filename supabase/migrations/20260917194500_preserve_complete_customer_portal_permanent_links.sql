-- Preserve the complete customer portal payload while switching token access to
-- permanent-until-revoked semantics.
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
  v_customer_phone text;
  v_market_name text;
  v_market_phone text;
  v_market_address text;
  v_receipt_title text;
  v_footer_note text;
  v_primary_color text;
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

  select customer.name,
         customer.phone,
         tenant.market_name,
         coalesce(nullif(settings.phone, ''), tenant.phone),
         coalesce(settings.address, ''),
         coalesce(nullif(settings.receipt_title, ''), 'پسووڵەی ZHIROX'),
         coalesce(settings.footer_note, ''),
         coalesce(settings.primary_color, '#3157E0'),
         customer.debt_limit
  into v_customer_name, v_customer_phone, v_market_name, v_market_phone,
       v_market_address, v_receipt_title, v_footer_note, v_primary_color,
       v_debt_limit
  from public.profiles customer
  join public.profiles tenant on tenant.id = v_market_id
  left join public.market_receipt_settings settings on settings.admin_id = tenant.id
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

  select coalesce(
    jsonb_agg(to_jsonb(item) order by item.occurred_at desc, item.kind, item.id),
    '[]'::jsonb
  )
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
             d.description as note,
             d.items,
             d.created_at
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
             p.note,
             '[]'::jsonb as items,
             p.created_at
      from public.payments p
      join public.debts d on d.id = p.debt_id
      where d.customer_id = v_customer_id and d.is_deleted = false
    ) ledger
    order by occurred_at desc, kind, id
    limit 51 offset v_offset
  ) item;

  return jsonb_build_object(
    'customer_name', v_customer_name,
    'customer_phone', v_customer_phone,
    'market_name', v_market_name,
    'market_phone', v_market_phone,
    'market_address', v_market_address,
    'receipt_title', v_receipt_title,
    'footer_note', v_footer_note,
    'primary_color', v_primary_color,
    'debt_limit', v_debt_limit,
    'can_subscribe', v_can_subscribe,
    'totals', v_totals,
    'rows', case when jsonb_array_length(v_rows) > 50 then v_rows - 50 else v_rows end,
    'offset', v_offset,
    'has_more', jsonb_array_length(v_rows) > 50,
    'as_of', now()
  );
end;
$$;

revoke all on function public.read_customer_push_portal_service(text,text,text,integer)
  from public, anon, authenticated;
grant execute on function public.read_customer_push_portal_service(text,text,text,integer)
  to service_role;
