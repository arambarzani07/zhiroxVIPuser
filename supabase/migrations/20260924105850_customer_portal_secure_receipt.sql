create or replace function public.read_customer_portal_receipt_service(
  p_receipt_id uuid,
  p_token_hash text default null,
  p_endpoint text default null,
  p_device_secret_hash text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_customer_id uuid;
  v_market_id uuid;
  v_receipt public.receipt_documents%rowtype;
  v_customer_name text;
  v_customer_phone text;
  v_market_name text;
  v_source jsonb;
begin
  select r.customer_id, r.market_id
    into v_customer_id, v_market_id
  from private.resolve_customer_push_identity(
    p_token_hash, p_endpoint, p_device_secret_hash
  ) r
  limit 1;

  if v_customer_id is null or v_market_id is null then
    raise no_data_found;
  end if;

  select *
    into v_receipt
  from public.receipt_documents r
  where r.id = p_receipt_id
    and r.admin_id = v_market_id
  limit 1;

  if not found then
    raise no_data_found;
  end if;

  select customer.name, customer.phone, tenant.market_name
    into v_customer_name, v_customer_phone, v_market_name
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
    and (
      tenant.is_system_owner
      or tenant.subscription_end is null
      or tenant.subscription_end >= now()
    );

  if v_customer_name is null then
    raise no_data_found;
  end if;

  if v_receipt.source_type = 'debt' then
    select jsonb_build_object(
      'id', d.id,
      'kind', 'debt',
      'amount', d.amount,
      'remaining', d.remaining,
      'currency', d.currency,
      'dollar_rate', d.dollar_rate,
      'due_date', d.due_date,
      'note', d.description,
      'items', coalesce(d.items, '[]'::jsonb),
      'occurred_at', coalesce(d.custom_date, d.created_at)
    )
    into v_source
    from public.debts d
    where d.id = v_receipt.source_id
      and d.customer_id = v_customer_id
      and d.is_deleted = false;
  elsif v_receipt.source_type = 'payment' then
    select jsonb_build_object(
      'id', p.id,
      'kind', 'payment',
      'amount', p.amount,
      'remaining', d.remaining,
      'currency', d.currency,
      'dollar_rate', d.dollar_rate,
      'due_date', null,
      'note', p.note,
      'items', '[]'::jsonb,
      'occurred_at', p.created_at
    )
    into v_source
    from public.payments p
    join public.debts d on d.id = p.debt_id
    where p.id = v_receipt.source_id
      and d.customer_id = v_customer_id
      and d.is_deleted = false;
  else
    raise no_data_found;
  end if;

  if v_source is null then
    raise no_data_found;
  end if;

  return jsonb_build_object(
    'id', v_receipt.id,
    'receipt_number', v_receipt.receipt_number,
    'source_type', v_receipt.source_type,
    'version_no', v_receipt.version_no,
    'created_at', v_receipt.created_at,
    'customer_name', v_customer_name,
    'customer_phone', v_customer_phone,
    'market_name', v_market_name,
    'settings', v_receipt.settings_snapshot,
    'source', v_source
  );
end;
$function$;

revoke all on function public.read_customer_portal_receipt_service(uuid,text,text,text)
  from public, anon, authenticated;
grant execute on function public.read_customer_portal_receipt_service(uuid,text,text,text)
  to service_role;
