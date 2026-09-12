alter table public.debts
  add column if not exists subtotal numeric not null default 0,
  add column if not exists discount_percent numeric not null default 0,
  add column if not exists discount_amount numeric not null default 0;

update public.debts
set subtotal = amount,
    discount_percent = 0,
    discount_amount = 0
where subtotal = 0
   or discount_percent <> 0
   or discount_amount <> 0;

alter table public.debts
  drop constraint if exists debts_subtotal_check,
  drop constraint if exists debts_discount_percent_check,
  drop constraint if exists debts_discount_amount_check;

alter table public.debts
  add constraint debts_subtotal_check check (subtotal > 0),
  add constraint debts_discount_percent_check check (discount_percent between 0 and 100),
  add constraint debts_discount_amount_check check (discount_amount >= 0 and discount_amount < subtotal);

create or replace function private.normalize_debt_discount()
returns trigger
language plpgsql
set search_path to 'pg_catalog'
as $function$
declare
  v_paid numeric := 0;
begin
  new.discount_percent := coalesce(new.discount_percent, 0);
  new.discount_amount := coalesce(new.discount_amount, 0);
  new.subtotal := coalesce(new.subtotal, 0);

  if new.discount_percent < 0 or new.discount_percent > 100 then
    raise exception 'invalid_discount_percent';
  end if;

  if tg_op = 'INSERT' then
    if new.subtotal <= 0 and coalesce(new.amount, 0) > 0 then
      new.subtotal := new.amount;
    end if;
    if new.subtotal <= 0 then
      raise exception 'invalid_subtotal';
    end if;
    new.discount_amount := round(new.subtotal * new.discount_percent / 100.0, 2);
    new.amount := new.subtotal - new.discount_amount;
    if new.amount <= 0 then
      raise exception 'discounted_total_must_be_positive';
    end if;
    new.remaining := new.amount;
    new.status := 'pending';
    return new;
  end if;

  if new.amount is distinct from old.amount
     and new.subtotal is not distinct from old.subtotal
     and new.discount_percent is not distinct from old.discount_percent
     and new.discount_amount is not distinct from old.discount_amount then
    if new.amount <= 0 then
      raise exception 'discounted_total_must_be_positive';
    end if;
    new.subtotal := new.amount;
    new.discount_percent := 0;
    new.discount_amount := 0;
    return new;
  end if;

  if new.subtotal is distinct from old.subtotal
     or new.discount_percent is distinct from old.discount_percent
     or new.discount_amount is distinct from old.discount_amount then
    if new.subtotal <= 0 then
      raise exception 'invalid_subtotal';
    end if;
    v_paid := greatest(old.amount - old.remaining, 0);
    new.discount_amount := round(new.subtotal * new.discount_percent / 100.0, 2);
    new.amount := new.subtotal - new.discount_amount;
    if new.amount <= 0 then
      raise exception 'discounted_total_must_be_positive';
    end if;
    if v_paid > new.amount then
      raise exception 'discounted_total_below_paid';
    end if;
    new.remaining := new.amount - v_paid;
    new.status := case
      when new.remaining <= 0 then 'paid'
      when v_paid > 0 then 'partial'
      else 'pending'
    end;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_debts_normalize_discount on public.debts;
create trigger trg_debts_normalize_discount
before insert or update of amount, subtotal, discount_percent, discount_amount
on public.debts
for each row execute function private.normalize_debt_discount();
