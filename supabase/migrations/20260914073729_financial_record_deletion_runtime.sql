-- Atomic, service-only deletion runtime for debt and payment records.
-- Edge Functions authenticate the caller, while these functions re-check the
-- active admin and tenant boundary inside the database transaction.

create or replace function public.delete_debt_service(
  p_actor_id uuid,
  p_debt_id uuid
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_deleted_id uuid;
begin
  if not exists (
    select 1
    from public.profiles actor
    where actor.id = p_actor_id
      and actor.role = 'admin'
      and actor.active = true
      and actor.approved = true
      and (
        actor.is_system_owner = true
        or actor.subscription_end is null
        or actor.subscription_end >= now()
      )
  ) then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', p_actor_id::text, 'role', 'authenticated')::text,
    true
  );

  update public.debts debt
  set is_deleted = true,
      deleted_at = now(),
      deleted_by = p_actor_id,
      updated_at = now()
  from public.profiles customer
  where debt.id = p_debt_id
    and debt.customer_id = customer.id
    and (
      case
        when customer.role = 'admin' then customer.id
        else customer.admin_id
      end
    ) = p_actor_id
    and debt.is_deleted = false
  returning debt.id into v_deleted_id;

  if v_deleted_id is null then
    raise exception 'debt_not_found_or_forbidden' using errcode = '42501';
  end if;

  return true;
end;
$$;

create or replace function public.restore_debt_service(
  p_actor_id uuid,
  p_debt_id uuid
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_restored_id uuid;
begin
  if not exists (
    select 1
    from public.profiles actor
    where actor.id = p_actor_id
      and actor.role = 'admin'
      and actor.active = true
      and actor.approved = true
      and (
        actor.is_system_owner = true
        or actor.subscription_end is null
        or actor.subscription_end >= now()
      )
  ) then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', p_actor_id::text, 'role', 'authenticated')::text,
    true
  );

  update public.debts debt
  set is_deleted = false,
      deleted_at = null,
      deleted_by = null,
      updated_at = now()
  from public.profiles customer
  where debt.id = p_debt_id
    and debt.customer_id = customer.id
    and (
      case
        when customer.role = 'admin' then customer.id
        else customer.admin_id
      end
    ) = p_actor_id
    and debt.is_deleted = true
  returning debt.id into v_restored_id;

  if v_restored_id is null then
    raise exception 'debt_not_found_or_forbidden' using errcode = '42501';
  end if;

  return true;
end;
$$;

create or replace function public.delete_payment_service(
  p_actor_id uuid,
  p_payment_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_debt public.debts%rowtype;
  v_payment public.payments%rowtype;
  v_new_remaining numeric;
  v_new_status text;
begin
  if not exists (
    select 1
    from public.profiles actor
    where actor.id = p_actor_id
      and actor.role = 'admin'
      and actor.active = true
      and actor.approved = true
      and (
        actor.is_system_owner = true
        or actor.subscription_end is null
        or actor.subscription_end >= now()
      )
  ) then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  -- Lock in the same debt-first order used by record_payment_service so a
  -- concurrent payment cannot produce a stale remaining balance.
  select debt.*
    into v_debt
  from public.payments payment
  join public.debts debt on debt.id = payment.debt_id
  join public.profiles customer on customer.id = debt.customer_id
  where payment.id = p_payment_id
    and debt.is_deleted = false
    and (
      case
        when customer.role = 'admin' then customer.id
        else customer.admin_id
      end
    ) = p_actor_id
  for update of debt;

  if not found then
    raise exception 'payment_not_found_or_forbidden' using errcode = '42501';
  end if;

  select payment.*
    into v_payment
  from public.payments payment
  where payment.id = p_payment_id
    and payment.debt_id = v_debt.id
  for update;

  if not found then
    raise exception 'payment_not_found_or_forbidden' using errcode = '42501';
  end if;

  v_new_remaining := least(v_debt.amount, v_debt.remaining + v_payment.amount);
  v_new_status := case
    when v_new_remaining <= 0 then 'paid'
    when v_new_remaining >= v_debt.amount then 'pending'
    else 'partial'
  end;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', p_actor_id::text, 'role', 'authenticated')::text,
    true
  );
  perform set_config('zhirox.payment_rpc', 'on', true);

  update public.debts
  set remaining = v_new_remaining,
      status = v_new_status,
      updated_at = now()
  where id = v_debt.id;

  delete from public.payments
  where id = v_payment.id;

  if not found then
    raise exception 'payment_delete_failed';
  end if;

  return jsonb_build_object(
    'payment_deleted', true,
    'payment_id', v_payment.id,
    'debt_id', v_debt.id,
    'remaining', v_new_remaining,
    'status', v_new_status
  );
end;
$$;

revoke all on function public.delete_debt_service(uuid, uuid)
from public, anon, authenticated;
revoke all on function public.restore_debt_service(uuid, uuid)
from public, anon, authenticated;
revoke all on function public.delete_payment_service(uuid, uuid)
from public, anon, authenticated;

grant execute on function public.delete_debt_service(uuid, uuid)
to service_role;
grant execute on function public.restore_debt_service(uuid, uuid)
to service_role;
grant execute on function public.delete_payment_service(uuid, uuid)
to service_role;
