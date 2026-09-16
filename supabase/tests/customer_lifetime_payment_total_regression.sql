-- Lifetime customer payment totals must survive debt archival/deletion.
-- Uses an existing paid fixture and rolls all changes back.
begin;

do $test$
declare
  v_customer uuid;
  v_debt uuid;
  v_paid numeric;
  v_before numeric;
  v_after numeric;
begin
  select d.customer_id, d.id, coalesce(sum(p.amount), 0)
    into v_customer, v_debt, v_paid
  from public.debts d
  join public.payments p on p.debt_id = d.id
  where d.is_deleted = false
  group by d.customer_id, d.id
  having coalesce(sum(p.amount), 0) > 0
  limit 1;

  if v_customer is null or v_debt is null or v_paid <= 0 then
    raise exception 'paid debt fixture required';
  end if;

  v_before := coalesce((public.get_customer_finance_snapshot(v_customer)->>'total_paid_iqd')::numeric, 0);

  update public.debts
  set is_deleted = true,
      deleted_at = now(),
      deleted_by = null
  where id = v_debt;

  v_after := coalesce((public.get_customer_finance_snapshot(v_customer)->>'total_paid_iqd')::numeric, 0);

  if v_after <> v_before then
    raise exception 'lifetime payment total changed after debt archival: before %, after %, archived debt paid %',
      v_before, v_after, v_paid;
  end if;
end
$test$;

rollback;

select 'customer lifetime payment total regression passed' as result;
