create or replace function public.record_payment_service(
  p_actor_id uuid,
  p_debt_id uuid,
  p_amount numeric,
  p_note text default '',
  p_reference_kind text default null,
  p_reference_id uuid default null
)
returns public.payments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_admin_id uuid;
  v_debt public.debts%rowtype;
  v_payment public.payments%rowtype;
  v_new_remaining numeric;
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

  select d.* into v_debt
  from public.debts d
  join public.profiles customer on customer.id = d.customer_id
  where d.id = p_debt_id
    and (case when customer.role = 'admin' then customer.id else customer.admin_id end) = v_admin_id
  for update of d;

  if not found then
    raise exception 'debt_not_found_or_forbidden' using errcode = '42501';
  end if;
  if v_debt.remaining <= 0 then
    raise exception 'debt_already_paid' using errcode = '22023';
  end if;

  v_new_remaining := greatest(v_debt.remaining - p_amount, 0);
  insert into public.payments (
    debt_id, amount, note, created_by, reference_kind, reference_id
  ) values (
    p_debt_id, least(p_amount, v_debt.remaining), coalesce(p_note, ''),
    p_actor_id, p_reference_kind, p_reference_id
  )
  returning * into v_payment;

  perform set_config('zhirox.payment_rpc', 'on', true);
  update public.debts
  set remaining = v_new_remaining,
      status = case when v_new_remaining <= 0 then 'paid' else 'partial' end,
      updated_at = now()
  where id = p_debt_id;

  return v_payment;
end;
$$;

revoke all on function public.record_payment_service(uuid, uuid, numeric, text, text, uuid)
from public, anon, authenticated;
grant execute on function public.record_payment_service(uuid, uuid, numeric, text, text, uuid)
to service_role;

revoke all on function public.record_payment(uuid, numeric, text, text, uuid)
from public, anon, authenticated;
grant execute on function public.record_payment(uuid, numeric, text, text, uuid)
to service_role;
