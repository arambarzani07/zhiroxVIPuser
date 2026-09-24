create or replace function public.read_customer_portal_due_summary_service(
  p_token_hash text default null,
  p_endpoint text default null,
  p_device_secret_hash text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
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

  if not found then raise no_data_found; end if;

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
          then round((i.amount / d.dollar_rate)::numeric, 2)
        else i.amount
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
      and d.remaining > 0

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
          then round((d.remaining / d.dollar_rate)::numeric, 2)
        else d.remaining
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
      and d.remaining > 0
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

revoke all on function public.read_customer_portal_due_summary_service(text,text,text)
  from public, anon, authenticated;
grant execute on function public.read_customer_portal_due_summary_service(text,text,text)
  to service_role;
