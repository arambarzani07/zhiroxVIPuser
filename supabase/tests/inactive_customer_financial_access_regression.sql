begin;

create temporary table regression_customer as
select p.id
from public.profiles p
where p.role = 'customer'
  and p.active
  and p.approved
  and exists (select 1 from public.debts d where d.customer_id = p.id)
limit 1;

do $$
begin
  if not exists (select 1 from regression_customer) then
    raise exception 'Regression fixture missing: no active approved customer with a debt';
  end if;
end
$$;

update public.profiles
set active = false
where id = (select id from regression_customer);

grant select on regression_customer to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub', (select id::text from regression_customer), true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  target_customer_id uuid := auth.uid();
begin
  if exists (select 1 from public.debts where debts.customer_id = target_customer_id) then
    raise exception 'Inactive customer can still read debts';
  end if;
  if exists (
    select 1 from public.payments
    where private.debt_customer_id(payments.debt_id) = target_customer_id
  ) then
    raise exception 'Inactive customer can still read payments';
  end if;
  if exists (select 1 from public.financial_events where financial_events.customer_id = target_customer_id) then
    raise exception 'Inactive customer can still read financial events';
  end if;
  if exists (select 1 from public.notifications where notifications.customer_id = target_customer_id) then
    raise exception 'Inactive customer can still read notifications';
  end if;
  if exists (select 1 from public.financial_chat_reads where viewer_id = target_customer_id) then
    raise exception 'Inactive customer can still read financial-chat state';
  end if;
end
$$;

rollback;
select 'inactive customer financial access regression passed' as result;
