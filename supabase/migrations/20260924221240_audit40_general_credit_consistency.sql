-- Mirrors production migration 20260924221240: audit40_general_credit_consistency.
-- General payments remain account-level credits and never mutate debt.remaining.
-- Derived open-state, installment settlement, and reminders are general-credit aware.

CREATE OR REPLACE FUNCTION private.get_effective_debt_remaining(p_debt_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(v.effective_remaining,0)::numeric
  from public.debts d
  left join lateral private.get_customer_virtual_debt_balances(d.customer_id) v on v.debt_id=d.id
  where d.id=p_debt_id and d.is_deleted=false limit 1
$function$

CREATE OR REPLACE FUNCTION private.refresh_customer_installments_effective(p_customer_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  with effective as materialized (
    select d.id debt_id,d.amount,d.remaining,
           coalesce(v.effective_remaining,d.remaining)::numeric effective_remaining
    from public.debts d
    left join lateral private.get_customer_virtual_debt_balances(p_customer_id) v on v.debt_id=d.id
    where d.customer_id=p_customer_id and d.is_deleted=false
  ), ranked as (
    select i.id,i.debt_id,i.baseline_paid,e.amount,e.effective_remaining,
           sum(i.amount) over(partition by i.debt_id order by i.installment_no
             rows between unbounded preceding and current row)::numeric cumulative_amount
    from public.debt_installments i join effective e on e.debt_id=i.debt_id
    where i.customer_id=p_customer_id and i.status<>'cancelled'
  ), resolved as (
    select r.*,greatest(
      greatest(coalesce(r.amount,0)-coalesce(r.effective_remaining,0),0)
      -coalesce(r.baseline_paid,0),0)::numeric schedule_paid
    from ranked r
  )
  update public.debt_installments i
  set status=case when r.cumulative_amount<=r.schedule_paid+0.02 then 'paid' else 'pending' end,
      paid_at=case when r.cumulative_amount<=r.schedule_paid+0.02 then coalesce(i.paid_at,now()) else null end,
      updated_at=now()
  from resolved r
  where i.id=r.id and (
    i.status is distinct from case when r.cumulative_amount<=r.schedule_paid+0.02 then 'paid' else 'pending' end
    or (r.cumulative_amount>r.schedule_paid+0.02 and i.paid_at is not null)
  );
end
$function$

CREATE OR REPLACE FUNCTION private.close_installments_when_debt_paid()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.remaining is distinct from old.remaining then
    perform private.refresh_customer_installments_effective(new.customer_id);
  end if;
  return new;
end
$function$

CREATE OR REPLACE FUNCTION private.refresh_installments_after_general_payment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op='DELETE' then
    perform private.refresh_customer_installments_effective(old.customer_id);
    return old;
  end if;
  perform private.refresh_customer_installments_effective(new.customer_id);
  if tg_op='UPDATE' and old.customer_id is distinct from new.customer_id then
    perform private.refresh_customer_installments_effective(old.customer_id);
  end if;
  return new;
end
$function$

CREATE OR REPLACE FUNCTION public.get_customer_finance_snapshot(p_customer_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with official as (
    select * from private.get_daftar_official_customer_totals(p_customer_id) limit 1
  ), debt_rows as materialized (
    select d.* from public.debts d where d.customer_id=p_customer_id and d.is_deleted=false
  ), virtual as materialized (
    select * from private.get_customer_virtual_debt_balances(p_customer_id)
  ), summary as (
    select
      coalesce(sum(d.amount) filter(where upper(coalesce(d.currency,'IQD'))<>'USD'),0)::numeric local_total_debt_iqd,
      coalesce(sum(d.remaining) filter(where upper(coalesce(d.currency,'IQD'))<>'USD'),0)::numeric local_gross_remaining_iqd,
      count(*) filter(where coalesce(v.effective_remaining,d.remaining)>0)::bigint open_debt_count
    from debt_rows d left join virtual v on v.debt_id=d.id
  ), local_paid as (
    select private.customer_lifetime_paid_total(p_customer_id)::numeric total_paid_iqd
  ), general_paid as (
    select coalesce(sum(g.amount),0)::numeric amount
    from public.customer_general_payments g where g.customer_id=p_customer_id
  ), open_debts as (
    select coalesce(jsonb_agg(
      to_jsonb(d)||jsonb_build_object(
        'effective_remaining',coalesce(v.effective_remaining,d.remaining),
        'general_credit_applied',coalesce(v.applied_general_credit,0)
      ) order by coalesce(d.custom_date,d.created_at) desc,d.id desc
    ),'[]'::jsonb) items
    from debt_rows d left join virtual v on v.debt_id=d.id
    where coalesce(v.effective_remaining,d.remaining)>0
  )
  select jsonb_build_object(
    'total_debt_iqd',coalesce((select loan_iqd from official),s.local_total_debt_iqd),
    'total_remaining_iqd',greatest(coalesce((select balance_iqd from official),s.local_gross_remaining_iqd)-gp.amount,0),
    'total_paid_iqd',case when exists(select 1 from official)
      then coalesce((select payment_iqd from official),0)+gp.amount else lp.total_paid_iqd end,
    'general_paid_iqd',gp.amount,
    'gross_remaining_iqd',coalesce((select balance_iqd from official),s.local_gross_remaining_iqd),
    'open_debt_count',s.open_debt_count,'open_debts',o.items,'complete',true,
    'general_payment_policy','account_credit_no_debt_mutation'
  )
  from summary s cross join local_paid lp cross join general_paid gp cross join open_debts o
$function$

CREATE OR REPLACE FUNCTION public.enqueue_customer_due_reminders_service()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_inserted integer:=0;
begin
  insert into public.notification_outbox(
    market_id,customer_id,event_type,event_record_id,idempotency_key,payload,deep_link,requires_ack
  )
  select customer.admin_id,debt.customer_id,'due_reminder',debt.id,
    'due_reminder:'||debt.id::text||':'||
      case when debt.due_date-current_date=3 then 'pre3'
           when debt.due_date-current_date=1 then 'pre1'
           when debt.due_date=current_date then 'today'
           else 'overdue'||(current_date-debt.due_date)::text end||':'||debt.due_date::text,
    jsonb_build_object(
      'amount',case
        when upper(coalesce(debt.currency,'IQD'))='USD' and coalesce(debt.dollar_rate,0)>0
          then round((eff.effective_remaining/debt.dollar_rate)::numeric,2)
        when upper(coalesce(debt.currency,'IQD'))='USD' then eff.effective_remaining
        else least(eff.effective_remaining,balances.remaining_iqd) end,
      'currency',case when upper(coalesce(debt.currency,'IQD'))='USD' then 'USD' else 'IQD' end,
      'remaining_iqd',balances.remaining_iqd,'market_name',tenant.market_name,'occurred_at',now(),
      'due_date',debt.due_date,'overdue',debt.due_date<current_date,
      'days_until_due',greatest(debt.due_date-current_date,0),
      'days_overdue',greatest(current_date-debt.due_date,0),
      'overdue_interval_days',coalesce(settings.overdue_interval_days,3),
      'general_credit_aware',true
    ),
    '/?view=transactions&event='||debt.id::text,false
  from public.debts debt
  join public.profiles customer on customer.id=debt.customer_id
  join public.profiles tenant on tenant.id=customer.admin_id
  join lateral (select private.get_effective_debt_remaining(debt.id)::numeric effective_remaining) eff
    on eff.effective_remaining>0
  join lateral (select public.get_customer_effective_balance(debt.customer_id)::numeric remaining_iqd) balances on true
  left join public.customer_notification_preferences pref
    on pref.customer_id=debt.customer_id and pref.market_id=customer.admin_id
  left join public.market_notification_settings settings on settings.market_id=customer.admin_id
  where debt.is_deleted=false and debt.due_date is not null
    and customer.role='customer' and customer.active=true and customer.approved=true
    and tenant.role='admin' and tenant.active=true and tenant.approved=true
    and (tenant.is_system_owner or tenant.subscription_end is null or tenant.subscription_end>=now())
    and (upper(coalesce(debt.currency,'IQD'))='USD' or balances.remaining_iqd>0)
    and coalesce(pref.due_reminders,true)=true
    and private.customer_portal_enabled(debt.customer_id,customer.admin_id)
    and (debt.due_date-current_date in (3,1,0)
      or (debt.due_date<current_date and mod(current_date-debt.due_date,coalesce(settings.overdue_interval_days,3))=0))
  on conflict(idempotency_key) do nothing;
  get diagnostics v_inserted=row_count;
  return v_inserted;
end
$function$

CREATE OR REPLACE FUNCTION public.enqueue_customer_installment_reminders_service()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_inserted integer:=0;
begin
  insert into public.notification_outbox(
    market_id,customer_id,event_type,event_record_id,idempotency_key,payload,deep_link,requires_ack
  )
  select i.admin_id,i.customer_id,'installment_reminder',i.id,
    'installment_reminder:'||i.id::text||':'||
      case when i.due_date-current_date=3 then 'pre3'
           when i.due_date-current_date=1 then 'pre1'
           when i.due_date=current_date then 'today'
           else 'overdue'||(current_date-i.due_date)::text end||':'||i.due_date::text,
    jsonb_build_object(
      'amount',case when upper(coalesce(d.currency,'IQD'))='USD' and coalesce(d.dollar_rate,0)>0
        then round((i.amount/d.dollar_rate)::numeric,2) else i.amount end,
      'currency',case when upper(coalesce(d.currency,'IQD'))='USD' then 'USD' else 'IQD' end,
      'market_name',tenant.market_name,'occurred_at',now(),'due_date',i.due_date,
      'overdue',i.due_date<current_date,'installment_no',i.installment_no,'debt_id',i.debt_id,
      'days_until_due',greatest(i.due_date-current_date,0),'days_overdue',greatest(current_date-i.due_date,0),
      'overdue_interval_days',coalesce(settings.overdue_interval_days,3),'general_credit_aware',true
    ),
    '/?view=transactions&event='||i.debt_id::text,false
  from public.debt_installments i
  join public.debts d on d.id=i.debt_id
  join public.profiles customer on customer.id=i.customer_id
  join public.profiles tenant on tenant.id=i.admin_id
  left join public.customer_notification_preferences pref
    on pref.customer_id=i.customer_id and pref.market_id=i.admin_id
  left join public.market_notification_settings settings on settings.market_id=i.admin_id
  where i.status='pending' and d.is_deleted=false
    and private.get_effective_debt_remaining(d.id)>0
    and customer.role='customer' and customer.active=true and customer.approved=true
    and tenant.role='admin' and tenant.active=true and tenant.approved=true
    and (tenant.is_system_owner or tenant.subscription_end is null or tenant.subscription_end>=now())
    and coalesce(pref.installment_reminders,true)=true
    and private.customer_portal_enabled(i.customer_id,i.admin_id)
    and (i.due_date-current_date in (3,1,0)
      or (i.due_date<current_date and mod(current_date-i.due_date,coalesce(settings.overdue_interval_days,3))=0))
  on conflict(idempotency_key) do nothing;
  get diagnostics v_inserted=row_count;
  return v_inserted;
end
$function$

revoke all on function private.get_effective_debt_remaining(uuid)
  from public, anon;
grant execute on function private.get_effective_debt_remaining(uuid)
  to authenticated, service_role;

revoke all on function private.refresh_customer_installments_effective(uuid)
  from public, anon, authenticated;
revoke all on function private.close_installments_when_debt_paid()
  from public, anon, authenticated;
revoke all on function private.refresh_installments_after_general_payment()
  from public, anon, authenticated;

drop trigger if exists customer_general_payments_refresh_installments
  on public.customer_general_payments;
create trigger customer_general_payments_refresh_installments
after insert or update of amount, customer_id or delete
on public.customer_general_payments
for each row execute function private.refresh_installments_after_general_payment();
