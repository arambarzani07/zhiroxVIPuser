begin;

create temporary table regression_debt_edit as
select d.id,
       d.amount as old_amount,
       d.remaining as old_remaining,
       case when c.role = 'admin' then c.id else c.admin_id end as admin_id
from public.debts d
join public.profiles c on c.id = d.customer_id
join public.profiles a
  on a.id = case when c.role = 'admin' then c.id else c.admin_id end
where a.role = 'admin'
  and a.active
  and a.approved
  and (a.subscription_end is null or a.subscription_end >= now())
limit 1;

do $$
begin
  if not exists (select 1 from regression_debt_edit) then
    raise exception 'Regression fixture missing: no editable debt';
  end if;
end
$$;

grant select on regression_debt_edit to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub', (select admin_id::text from regression_debt_edit), true);
select set_config('request.jwt.claim.role', 'authenticated', true);

update public.debts d
set amount = d.amount + 1000,
    remaining = d.remaining + 1000
where d.id = (select id from regression_debt_edit);

do $$
declare
  v_old_paid numeric;
  v_new_paid numeric;
  v_expected_status text;
  v_actual_status text;
begin
  select old_amount - old_remaining into v_old_paid
  from regression_debt_edit;

  select d.amount - d.remaining,
         case when d.remaining = 0 then 'paid'
              when d.remaining < d.amount then 'partial'
              else 'pending' end,
         d.status
    into v_new_paid, v_expected_status, v_actual_status
  from public.debts d
  where d.id = (select id from regression_debt_edit);

  if v_new_paid is distinct from v_old_paid then
    raise exception 'Debt edit changed the already-paid amount';
  end if;
  if v_actual_status is distinct from v_expected_status then
    raise exception 'Debt edit left an inconsistent status';
  end if;

  begin
    update public.debts d
    set remaining = d.remaining + 1
    where d.id = (select id from regression_debt_edit);
    raise exception 'Direct remaining tampering was accepted';
  exception
    when insufficient_privilege then null;
  end;
end
$$;

rollback;
select 'debt edit financial invariant regression passed' as result;
