create or replace function public.record_customer_payment_service(
  p_actor_id uuid,
  p_customer_id uuid,
  p_amount numeric,
  p_note text default '',
  p_reference_kind text default null,
  p_reference_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_admin_id uuid;
  v_customer_admin_id uuid;
  v_left numeric := p_amount;
  v_piece numeric;
  v_total_remaining numeric := 0;
  v_allocation_count integer := 0;
  v_debt public.debts%rowtype;
  v_payment public.payments%rowtype;
  v_payments jsonb := '[]'::jsonb;
begin
  if p_actor_id is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select p.role,
         case when p.role = 'admin' then p.id else p.admin_id end
    into v_role, v_admin_id
  from public.profiles p
  join public.profiles tenant
    on tenant.id = case when p.role = 'admin' then p.id else p.admin_id end
   and tenant.role = 'admin'
   and tenant.active = true
   and tenant.approved = true
   and (tenant.subscription_end is null or tenant.subscription_end >= now())
  where p.id = p_actor_id
    and p.role in ('admin', 'employee')
    and p.active = true
    and p.approved = true;

  if v_role is null or v_admin_id is null then
    raise exception 'payment_forbidden' using errcode = '42501';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_payment_amount' using errcode = '22023';
  end if;

  select case when customer.role = 'admin' then customer.id else customer.admin_id end
    into v_customer_admin_id
  from public.profiles customer
  where customer.id = p_customer_id
    and customer.role = 'customer';

  if v_customer_admin_id is null or v_customer_admin_id <> v_admin_id then
    raise exception 'customer_not_found_or_forbidden' using errcode = '42501';
  end if;

  perform set_config('zhirox.payment_rpc', 'on', true);

  for v_debt in
    select d.*
    from public.debts d
    where d.customer_id = p_customer_id
      and d.is_deleted = false
      and d.remaining > 0
    order by coalesce(d.custom_date, d.created_at) asc,
             d.created_at asc,
             d.id asc
    for update
  loop
    exit when v_left <= 0;

    v_piece := least(v_left, v_debt.remaining);

    insert into public.payments (
      debt_id,
      amount,
      note,
      created_by,
      reference_kind,
      reference_id
    ) values (
      v_debt.id,
      v_piece,
      coalesce(p_note, ''),
      p_actor_id,
      p_reference_kind,
      p_reference_id
    )
    returning * into v_payment;

    update public.debts
    set remaining = greatest(v_debt.remaining - v_piece, 0),
        status = case
          when greatest(v_debt.remaining - v_piece, 0) <= 0 then 'paid'
          else 'partial'
        end,
        updated_at = now()
    where id = v_debt.id;

    v_payments := v_payments || jsonb_build_array(to_jsonb(v_payment));
    v_allocation_count := v_allocation_count + 1;
    v_left := v_left - v_piece;
  end loop;

  if v_left > 0 then
    raise exception 'payment_exceeds_customer_balance' using errcode = '22023';
  end if;

  select coalesce(sum(d.remaining), 0)::numeric
    into v_total_remaining
  from public.debts d
  where d.customer_id = p_customer_id
    and d.is_deleted = false
    and d.remaining > 0;

  return jsonb_build_object(
    'customer_id', p_customer_id,
    'amount', p_amount,
    'allocation_count', v_allocation_count,
    'remaining', v_total_remaining,
    'payments', v_payments
  );
end;
$$;

revoke all on function public.record_customer_payment_service(
  uuid, uuid, numeric, text, text, uuid
) from public, anon, authenticated;

grant execute on function public.record_customer_payment_service(
  uuid, uuid, numeric, text, text, uuid
) to service_role;
