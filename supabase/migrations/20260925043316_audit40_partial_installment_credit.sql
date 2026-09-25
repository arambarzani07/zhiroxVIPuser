-- Mirrors production migration 20260925043316: audit40_partial_installment_credit.
-- Partial account credits reduce installment reminder amounts without changing debt.remaining.

create or replace function private.get_effective_installment_remaining(
  p_installment_id uuid
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $function$
  with target as (
    select
      i.id, i.debt_id, i.installment_no, i.amount,
      coalesce(i.baseline_paid,0)::numeric as baseline_paid,
      d.amount::numeric as debt_amount,
      private.get_effective_debt_remaining(d.id)::numeric as effective_debt_remaining
    from public.debt_installments i
    join public.debts d on d.id=i.debt_id
    where i.id=p_installment_id
      and i.status <> 'cancelled'
      and d.is_deleted=false
  ),
  prior as (
    select coalesce(sum(i.amount),0)::numeric as amount
    from public.debt_installments i
    join target t on t.debt_id=i.debt_id
    where i.status <> 'cancelled'
      and i.installment_no < t.installment_no
  ),
  calc as (
    select t.*,
      greatest(
        greatest(t.debt_amount-coalesce(t.effective_debt_remaining,0),0)
        - t.baseline_paid,
        0
      )::numeric as schedule_paid,
      p.amount::numeric as prior_amount
    from target t cross join prior p
  )
  select greatest(
    c.amount - least(c.amount,greatest(c.schedule_paid-c.prior_amount,0)),
    0
  )::numeric
  from calc c
  limit 1
$function$;

revoke all on function private.get_effective_installment_remaining(uuid)
  from public, anon;
grant execute on function private.get_effective_installment_remaining(uuid)
  to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.read_customer_portal_due_summary_service(p_token_hash text DEFAULT NULL::text, p_endpoint text DEFAULT NULL::text, p_device_secret_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_customer_id uuid;
  v_market_id uuid;
  v_today date := (now() at time zone 'Asia/Baghdad')::date;
  v_summary jsonb := '{}'::jsonb;
begin
  select r.customer_id, r.market_id
    into v_customer_id, v_market_id
  from private.resolve_customer_push_identity(
    p_token_hash, p_endpoint, p_device_secret_hash
  ) r
  limit 1;

  perform 1
  from public.profiles customer
  join public.profiles tenant on tenant.id = v_market_id
  where customer.id = v_customer_id
    and customer.admin_id = v_market_id
    and customer.role = 'customer'
    and customer.active = true
    and customer.approved = true
    and tenant.role = 'admin'
    and tenant.active = true
    and tenant.approved = true
    and (
      tenant.is_system_owner
      or tenant.subscription_end is null
      or tenant.subscription_end >= now()
    );

  if not found then
    raise no_data_found;
  end if;

  with schedule as (
    select
      i.id as event_id,
      i.debt_id,
      'installment'::text as kind,
      i.installment_no,
      i.due_date,
      case
        when upper(coalesce(d.currency,'IQD'))='USD'
             and coalesce(d.dollar_rate,0) > 0
          then round((private.get_effective_installment_remaining(i.id) / d.dollar_rate)::numeric, 2)
        else private.get_effective_installment_remaining(i.id)
      end as amount,
      case
        when upper(coalesce(d.currency,'IQD'))='USD'
             and coalesce(d.dollar_rate,0) > 0
          then 'USD'
        else 'IQD'
      end as currency
    from public.debt_installments i
    join public.debts d on d.id = i.debt_id
    where i.customer_id = v_customer_id
      and i.admin_id = v_market_id
      and i.status = 'pending'
      and d.is_deleted = false
      and private.get_effective_installment_remaining(i.id) > 0

    union all

    select
      d.id as event_id,
      d.id as debt_id,
      'debt'::text as kind,
      null::integer as installment_no,
      d.due_date,
      case
        when upper(coalesce(d.currency,'IQD'))='USD'
             and coalesce(d.dollar_rate,0) > 0
          then round((private.get_effective_debt_remaining(d.id) / d.dollar_rate)::numeric, 2)
        else private.get_effective_debt_remaining(d.id)
      end as amount,
      case
        when upper(coalesce(d.currency,'IQD'))='USD'
             and coalesce(d.dollar_rate,0) > 0
          then 'USD'
        else 'IQD'
      end as currency
    from public.debts d
    where d.customer_id = v_customer_id
      and d.is_deleted = false
      and private.get_effective_debt_remaining(d.id) > 0
      and d.due_date is not null
      and not exists (
        select 1
        from public.debt_installments i
        where i.debt_id = d.id
          and i.status = 'pending'
      )
  ),
  aggregates as (
    select
      count(*)::integer as open_schedule_count,
      count(*) filter (where due_date < v_today)::integer as overdue_count,
      count(*) filter (where due_date = v_today)::integer as due_today_count,
      count(*) filter (
        where due_date > v_today and due_date <= v_today + 7
      )::integer as due_next_7_days,
      coalesce(sum(amount) filter (
        where due_date < v_today and currency = 'IQD'
      ),0)::numeric as overdue_iqd,
      coalesce(sum(amount) filter (
        where due_date < v_today and currency = 'USD'
      ),0)::numeric as overdue_usd
    from schedule
  ),
  next_due as (
    select jsonb_build_object(
      'event_id', event_id,
      'debt_id', debt_id,
      'kind', kind,
      'installment_no', installment_no,
      'due_date', due_date,
      'amount', amount,
      'currency', currency,
      'days_until_due', greatest(due_date - v_today, 0)
    ) as value
    from schedule
    where due_date >= v_today
    order by due_date asc, kind asc, event_id asc
    limit 1
  ),
  oldest_overdue as (
    select jsonb_build_object(
      'event_id', event_id,
      'debt_id', debt_id,
      'kind', kind,
      'installment_no', installment_no,
      'due_date', due_date,
      'amount', amount,
      'currency', currency,
      'days_overdue', v_today - due_date
    ) as value
    from schedule
    where due_date < v_today
    order by due_date asc, kind asc, event_id asc
    limit 1
  )
  select jsonb_build_object(
    'as_of_date', v_today,
    'open_schedule_count', a.open_schedule_count,
    'overdue_count', a.overdue_count,
    'due_today_count', a.due_today_count,
    'due_next_7_days', a.due_next_7_days,
    'overdue_iqd', a.overdue_iqd,
    'overdue_usd', a.overdue_usd,
    'next_due', coalesce((select value from next_due), 'null'::jsonb),
    'oldest_overdue', coalesce((select value from oldest_overdue), 'null'::jsonb)
  )
  into v_summary
  from aggregates a;

  return coalesce(v_summary, '{}'::jsonb);
end;
$function$;

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
        then round((private.get_effective_installment_remaining(i.id)/d.dollar_rate)::numeric,2) else private.get_effective_installment_remaining(i.id) end,
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
    and private.get_effective_installment_remaining(i.id)>0
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
$function$;
