create or replace function public.get_customer_period_statement_for_user(
  p_customer_id uuid,
  p_from_date date,
  p_to_date date
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_actor public.profiles%rowtype;
  v_customer public.profiles%rowtype;
  v_admin public.profiles%rowtype;
  v_settings public.market_receipt_settings%rowtype;
  v_rows jsonb := '[]'::jsonb;
  v_totals jsonb := '[]'::jsonb;
  v_row_count integer := 0;
  v_truncated boolean := false;
begin
  if (select auth.uid()) is null then
    raise exception 'not_authenticated';
  end if;

  if p_customer_id is null
     or p_from_date is null
     or p_to_date is null
     or p_from_date > p_to_date
     or (p_to_date - p_from_date) > 7305 then
    raise exception 'invalid_period';
  end if;

  select *
    into v_actor
  from public.profiles
  where id = (select auth.uid())
    and active = true
    and approved = true
  limit 1;

  if v_actor.id is null or coalesce(v_actor.is_system_owner, false) then
    raise exception 'forbidden';
  end if;

  select *
    into v_customer
  from public.profiles
  where id = p_customer_id
    and role = 'customer'
    and active = true
    and approved = true
  limit 1;

  if v_customer.id is null or v_customer.admin_id is null then
    raise exception 'customer_not_found';
  end if;

  if v_actor.role = 'admin' then
    if v_actor.id <> v_customer.admin_id then
      raise exception 'cross_tenant_forbidden';
    end if;
  elsif v_actor.role = 'employee' then
    if v_actor.admin_id is distinct from v_customer.admin_id
       or not coalesce(v_actor.can_view_debts, false) then
      raise exception 'missing_permission';
    end if;
  else
    raise exception 'forbidden';
  end if;

  select *
    into v_admin
  from public.profiles
  where id = v_customer.admin_id
    and role = 'admin'
    and active = true
    and approved = true
    and coalesce(is_system_owner, false) = false
  limit 1;

  if v_admin.id is null then
    raise exception 'admin_not_found';
  end if;

  if v_admin.subscription_end is not null
     and v_admin.subscription_end < now() then
    raise exception 'subscription_expired';
  end if;

  select *
    into v_settings
  from public.market_receipt_settings
  where admin_id = v_admin.id
  limit 1;

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
    where d.customer_id = v_customer.id
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
    'customer_id', v_customer.id,
    'customer_name', v_customer.name,
    'customer_phone', v_customer.phone,
    'market_id', v_admin.id,
    'market_name', coalesce(nullif(v_admin.market_name, ''), 'ZHIROX'),
    'market_phone', coalesce(nullif(v_settings.phone, ''), v_admin.phone, ''),
    'market_address', coalesce(v_settings.address, ''),
    'footer_note', coalesce(v_settings.footer_note, ''),
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

revoke all on function public.get_customer_period_statement_for_user(uuid,date,date)
  from public, anon;
grant execute on function public.get_customer_period_statement_for_user(uuid,date,date)
  to authenticated, service_role;
