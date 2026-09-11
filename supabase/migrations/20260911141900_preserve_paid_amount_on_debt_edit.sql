create or replace function private.guard_debt_financial_state()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_paid numeric;
  v_expected_remaining numeric;
  v_expected_status text;
begin
  if tg_op = 'INSERT' then
    if new.remaining is distinct from new.amount or new.status <> 'pending' then
      raise exception 'invalid_initial_debt_state' using errcode = '22023';
    end if;
    return new;
  end if;

  if coalesce(current_setting('zhirox.payment_rpc', true), '') = 'on' then
    if new.amount <= 0 or new.remaining < 0 or new.remaining > new.amount then
      raise exception 'invalid_debt_financial_state' using errcode = '22023';
    end if;
    v_expected_status := case
      when new.remaining = 0 then 'paid'
      when new.remaining < new.amount then 'partial'
      else 'pending'
    end;
    if new.status is distinct from v_expected_status then
      raise exception 'invalid_debt_status' using errcode = '22023';
    end if;
    return new;
  end if;

  if new.amount is distinct from old.amount then
    v_paid := old.amount - old.remaining;
    if new.amount < v_paid then
      raise exception 'debt_amount_below_paid_amount' using errcode = '22023';
    end if;

    v_expected_remaining := new.amount - v_paid;
    if new.remaining is distinct from v_expected_remaining then
      raise exception 'debt_edit_must_preserve_paid_amount' using errcode = '22023';
    end if;

    new.status := case
      when v_expected_remaining = 0 then 'paid'
      when v_expected_remaining < new.amount then 'partial'
      else 'pending'
    end;
    return new;
  end if;

  if new.remaining is distinct from old.remaining
     or new.status is distinct from old.status then
    raise exception 'debt_financial_state_requires_payment_rpc' using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists debts_guard_financial_state on public.debts;
create trigger debts_guard_financial_state
before insert or update of amount, remaining, status on public.debts
for each row execute function private.guard_debt_financial_state();
