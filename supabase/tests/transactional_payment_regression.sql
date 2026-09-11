-- Uses existing tenant fixtures and rolls every write back.
begin;

do $test$
declare
  v_employee uuid;
  v_debt uuid;
  v_before numeric;
  v_after numeric;
  v_payment public.payments;
begin
  if has_table_privilege('authenticated', 'public.payments', 'INSERT')
     or has_table_privilege('authenticated', 'public.payments', 'UPDATE')
     or has_table_privilege('authenticated', 'public.payments', 'DELETE') then
    raise exception 'authenticated retained direct payment write privilege';
  end if;

  select e.id, d.id, d.remaining
    into v_employee, v_debt, v_before
  from public.profiles e
  join public.profiles c
    on c.admin_id = e.admin_id
   and c.role = 'customer'
  join public.debts d
    on d.customer_id = c.id
   and d.remaining > 0
  where e.role = 'employee'
    and e.active = true
    and e.approved = true
  limit 1;

  if v_employee is null then
    raise exception 'employee and open debt fixture required';
  end if;

  perform set_config('request.jwt.claim.sub', v_employee::text, true);

  select *
    into v_payment
  from public.record_payment(
    v_debt,
    least(1, v_before),
    'regression',
    null,
    null
  );

  select remaining into v_after
  from public.debts
  where id = v_debt;

  if v_after <> greatest(v_before - least(1, v_before), 0) then
    raise exception 'atomic payment did not update debt remaining';
  end if;

  if v_payment.amount <> least(1, v_before) then
    raise exception 'atomic payment amount mismatch';
  end if;
end
$test$;

rollback;

select 'transactional payment regression passed' as result;

