-- Force every payment through the atomic RPC and protect cached debt state.
create or replace function private.guard_debt_financial_state()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.remaining is distinct from new.amount or new.status <> 'pending' then
      raise exception 'invalid_initial_debt_state' using errcode = '22023';
    end if;
    return new;
  end if;

  if (
    new.remaining is distinct from old.remaining
    or new.status is distinct from old.status
  ) and coalesce(current_setting('zhirox.payment_rpc', true), '') <> 'on' then
    raise exception 'debt_financial_state_requires_payment_rpc' using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists debts_guard_financial_state on public.debts;
create trigger debts_guard_financial_state
before insert or update of remaining, status on public.debts
for each row execute function private.guard_debt_financial_state();

create or replace function public.record_payment(
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
  v_uid uuid := auth.uid();
  v_role text;
  v_admin_id uuid;
  v_debt public.debts%rowtype;
  v_payment public.payments%rowtype;
  v_new_remaining numeric;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  v_role := private."current_role"();
  v_admin_id := private.current_admin_id();

  if v_role not in ('admin', 'employee') or v_admin_id is null then
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
    p_debt_id,
    least(p_amount, v_debt.remaining),
    coalesce(p_note, ''),
    v_uid,
    p_reference_kind,
    p_reference_id
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

revoke all privileges on table public.payments from anon;
revoke all privileges on table public.payments from authenticated;
grant select on table public.payments to authenticated;

revoke all on function public.record_payment(uuid, numeric, text, text, uuid)
from public, anon;
grant execute on function public.record_payment(uuid, numeric, text, text, uuid)
to authenticated;

