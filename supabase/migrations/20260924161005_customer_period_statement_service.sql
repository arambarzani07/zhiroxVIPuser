CREATE OR REPLACE FUNCTION public.read_customer_period_statement_service(p_from_date date, p_to_date date, p_token_hash text DEFAULT NULL::text, p_endpoint text DEFAULT NULL::text, p_device_secret_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_customer_id uuid;
  v_market_id uuid;
  v_customer_name text;
  v_market_name text;
  v_market_phone text;
  v_market_address text;
  v_footer_note text;
  v_rows jsonb := '[]'::jsonb;
  v_totals jsonb := '[]'::jsonb;
  v_row_count integer := 0;
  v_truncated boolean := false;
begin
  if p_from_date is null or p_to_date is null
     or p_from_date > p_to_date
     or (p_to_date - p_from_date) > 7305 then
    raise exception 'invalid_period';
  end if;

  select r.customer_id, r.market_id
    into v_customer_id, v_market_id
  from private.resolve_customer_push_identity(
    p_token_hash, p_endpoint, p_device_secret_hash
  ) r
  limit 1;

  if v_customer_id is null or v_market_id is null then
    raise no_data_found;
  end if;

  select customer.name,
         tenant.market_name,
         coalesce(nullif(settings.phone, ''), tenant.phone),
         coalesce(settings.address, ''),
         coalesce(settings.footer_note, '')
    into v_customer_name, v_market_name, v_market_phone,
         v_market_address, v_footer_note
  from public.profiles customer
  join public.profiles tenant on tenant.id = v_market_id
  left join public.market_receipt_settings settings
    on settings.admin_id = tenant.id
  where customer.id = v_customer_id
    and customer.admin_id = v_market_id
    and customer.role = 'customer'
    and customer.active = true
    and customer.approved = true
    and tenant.role = 'admin'
    and tenant.active = true
    and tenant.approved = true
    and (
      tenant.is_system_owner
      or tenant.subscription_end is null
      or tenant.subscription_end >= now()
    );

  if v_customer_name is null then
    raise no_data_found;
  end if;

  with selected_debts as (
    select
      d.id,
      d.description,
      d.amount,
      coalesce(nullif(d.currency, ''), 'IQD') as currency,
      coalesce(d.custom_date, d.created_at) as occurred_at,
      case
        when jsonb_typeof(d.items) = 'array' and jsonb_array_length(d.items) > 0
          then d.items
        else jsonb_build_array(jsonb_build_object(
          'name', coalesce(nullif(trim(d.description), ''), 'قەرز'),
          'price', d.amount,
          'qty', 1,
          'currency', coalesce(nullif(d.currency, ''), 'IQD')
        ))
      end as normalized_items
    from public.debts d
    where d.customer_id = v_customer_id
      and d.is_deleted = false
      and coalesce(d.custom_date, d.created_at)::date between p_from_date and p_to_date
  ),
  expanded as (
    select
      d.id as debt_id,
      d.occurred_at,
      item.ordinality::integer as item_no,
      coalesce(
        nullif(trim(item.value ->> 'name'), ''),
        nullif(trim(item.value ->> 'title'), ''),
        nullif(trim(item.value ->> 'item_name'), ''),
        nullif(trim(item.value ->> 'product_name'), ''),
        nullif(trim(item.value ->> 'description'), ''),
        'بابەت'
      ) as item_name,
      coalesce(nullif(trim(item.value ->> 'currency'), ''), d.currency, 'IQD') as currency,
      case
        when jsonb_typeof(item.value -> 'total') = 'number'
          then (item.value ->> 'total')::numeric
        when jsonb_typeof(item.value -> 'total_price') = 'number'
          then (item.value ->> 'total_price')::numeric
        when jsonb_typeof(item.value -> 'price') = 'number'
          then (item.value ->> 'price')::numeric
               * case
                   when jsonb_typeof(item.value -> 'qty') = 'number'
                     then (item.value ->> 'qty')::numeric
                   when jsonb_typeof(item.value -> 'quantity') = 'number'
                     then (item.value ->> 'quantity')::numeric
                   else 1
                 end
        when jsonb_typeof(item.value -> 'unit_price') = 'number'
          then (item.value ->> 'unit_price')::numeric
               * case
                   when jsonb_typeof(item.value -> 'qty') = 'number'
                     then (item.value ->> 'qty')::numeric
                   when jsonb_typeof(item.value -> 'quantity') = 'number'
                     then (item.value ->> 'quantity')::numeric
                   else 1
                 end
        else d.amount
      end as amount,
      case
        when jsonb_typeof(item.value -> 'qty') = 'number'
          then (item.value ->> 'qty')::numeric
        when jsonb_typeof(item.value -> 'quantity') = 'number'
          then (item.value ->> 'quantity')::numeric
        else 1
      end as qty
    from selected_debts d
    cross join lateral jsonb_array_elements(d.normalized_items)
      with ordinality as item(value, ordinality)
  ),
  capped as (
    select *
    from expanded
    order by occurred_at asc, debt_id asc, item_no asc
    limit 20001
  ),
  numbered as (
    select
      row_number() over(order by occurred_at asc, debt_id asc, item_no asc) as row_no,
      debt_id,
      occurred_at,
      item_no,
      item_name,
      currency,
      amount,
      qty
    from capped
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'row_no', row_no,
          'debt_id', debt_id,
          'name', case
            when qty > 1 then item_name || ' × ' || trim(to_char(qty, 'FM999999990.##'))
            else item_name
          end,
          'amount', amount,
          'currency', currency,
          'date', occurred_at::date,
          'occurred_at', occurred_at
        )
        order by row_no
      ) filter (where row_no <= 20000),
      '[]'::jsonb
    ),
    count(*)::integer,
    count(*) > 20000
  into v_rows, v_row_count, v_truncated
  from numbered;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'currency', t.currency,
        'total', t.total
      )
      order by t.currency
    ),
    '[]'::jsonb
  )
  into v_totals
  from (
    select
      coalesce(r ->> 'currency', 'IQD') as currency,
      sum((r ->> 'amount')::numeric) as total
    from jsonb_array_elements(v_rows) r
    group by coalesce(r ->> 'currency', 'IQD')
  ) t;

  return jsonb_build_object(
    'customer_name', v_customer_name,
    'market_name', v_market_name,
    'market_phone', v_market_phone,
    'market_address', v_market_address,
    'footer_note', v_footer_note,
    'from_date', p_from_date,
    'to_date', p_to_date,
    'rows', v_rows,
    'totals', v_totals,
    'row_count', least(v_row_count, 20000),
    'truncated', v_truncated,
    'generated_at', now()
  );
end;
$function$;

revoke all on function public.read_customer_period_statement_service(date,date,text,text,text) from public, anon, authenticated;
grant execute on function public.read_customer_period_statement_service(date,date,text,text,text) to service_role;