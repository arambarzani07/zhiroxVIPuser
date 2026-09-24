alter table public.debt_installments
  add column if not exists baseline_paid numeric not null default 0
  check (baseline_paid >= 0);

update public.debt_installments i
set baseline_paid = greatest(coalesce(d.amount,0) - coalesce(d.remaining,0),0)
from public.debts d
where d.id=i.debt_id
  and i.baseline_paid=0;

create or replace function public.set_debt_installment_schedule(
  p_debt_id uuid,
  p_schedule jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_admin_id uuid := private.current_admin_id();
  v_customer_id uuid;
  v_item jsonb;
  v_no integer := 0;
  v_due date;
  v_amount numeric;
  v_remaining numeric;
  v_baseline_paid numeric;
  v_total numeric := 0;
begin
  if v_admin_id is null
     or not (
       private."current_role"() = 'admin'
       or private.employee_has_permission('edit_debts')
     ) then
    raise exception 'forbidden' using errcode='42501';
  end if;

  if jsonb_typeof(p_schedule) <> 'array'
     or jsonb_array_length(p_schedule) < 1
     or jsonb_array_length(p_schedule) > 60 then
    raise exception 'invalid_installment_schedule' using errcode='22023';
  end if;

  select d.customer_id,
         d.remaining,
         greatest(coalesce(d.amount,0)-coalesce(d.remaining,0),0)
    into v_customer_id, v_remaining, v_baseline_paid
  from public.debts d
  join public.profiles c on c.id=d.customer_id
  where d.id=p_debt_id
    and d.is_deleted=false
    and d.remaining > 0
    and c.role='customer'
    and c.admin_id=v_admin_id;

  if v_customer_id is null then
    raise exception 'debt_not_found_or_forbidden' using errcode='42501';
  end if;

  begin
    select coalesce(sum((value->>'amount')::numeric),0)
      into v_total
    from jsonb_array_elements(p_schedule);
  exception when others then
    raise exception 'invalid_installment_schedule' using errcode='22023';
  end;

  if abs(v_total - v_remaining) > 0.02 then
    raise exception 'installment_total_must_equal_remaining'
      using errcode='22023';
  end if;

  update public.debt_installments
  set status='cancelled', updated_at=now()
  where debt_id=p_debt_id
    and status <> 'cancelled'
    and admin_id=v_admin_id;

  for v_item in select value from jsonb_array_elements(p_schedule)
  loop
    v_no := v_no + 1;
    begin
      v_due := (v_item->>'due_date')::date;
      v_amount := (v_item->>'amount')::numeric;
    exception when others then
      raise exception 'invalid_installment_schedule' using errcode='22023';
    end;

    if v_due is null or v_amount is null or v_amount <= 0 then
      raise exception 'invalid_installment_schedule' using errcode='22023';
    end if;

    insert into public.debt_installments(
      admin_id,customer_id,debt_id,installment_no,
      amount,due_date,status,paid_at,created_by,baseline_paid,updated_at
    )
    values(
      v_admin_id,v_customer_id,p_debt_id,v_no,
      v_amount,v_due,'pending',null,(select auth.uid()),v_baseline_paid,now()
    )
    on conflict (debt_id,installment_no)
    do update set
      admin_id=excluded.admin_id,
      customer_id=excluded.customer_id,
      amount=excluded.amount,
      due_date=excluded.due_date,
      status='pending',
      paid_at=null,
      created_by=excluded.created_by,
      baseline_paid=excluded.baseline_paid,
      updated_at=now();
  end loop;

  return (
    select coalesce(
      jsonb_agg(to_jsonb(i) order by i.installment_no),
      '[]'::jsonb
    )
    from public.debt_installments i
    where i.debt_id=p_debt_id
      and i.admin_id=v_admin_id
      and i.status='pending'
  );
end;
$function$;

create or replace function private.close_installments_when_debt_paid()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.remaining is not distinct from old.remaining then
    return new;
  end if;

  with ranked as (
    select
      i.id,
      i.baseline_paid,
      sum(i.amount) over (
        order by i.installment_no
        rows between unbounded preceding and current row
      ) as cumulative_amount
    from public.debt_installments i
    where i.debt_id=new.id
      and i.status <> 'cancelled'
  )
  update public.debt_installments i
  set
    status = case
      when ranked.cumulative_amount <=
           greatest(
             greatest(coalesce(new.amount,0)-coalesce(new.remaining,0),0)
             - ranked.baseline_paid,
             0
           ) + 0.02
        then 'paid'
      else 'pending'
    end,
    paid_at = case
      when ranked.cumulative_amount <=
           greatest(
             greatest(coalesce(new.amount,0)-coalesce(new.remaining,0),0)
             - ranked.baseline_paid,
             0
           ) + 0.02
        then coalesce(i.paid_at,now())
      else null
    end,
    updated_at=now()
  from ranked
  where i.id=ranked.id;

  return new;
end;
$function$;

drop trigger if exists trg_close_installments_when_debt_paid on public.debts;
create trigger trg_close_installments_when_debt_paid
after update of remaining on public.debts
for each row
execute function private.close_installments_when_debt_paid();

create or replace function public.enqueue_customer_installment_reminders_service()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_inserted integer := 0;
begin
  insert into public.notification_outbox(
    market_id, customer_id, event_type, event_record_id,
    idempotency_key, payload, deep_link, requires_ack
  )
  select
    i.admin_id,
    i.customer_id,
    'installment_reminder',
    i.id,
    'installment_reminder:' || i.id::text || ':' ||
      case
        when i.due_date-current_date=3 then 'pre3'
        when i.due_date-current_date=1 then 'pre1'
        when i.due_date=current_date then 'today'
        else 'overdue' || (current_date-i.due_date)::text
      end || ':' || i.due_date::text,
    jsonb_build_object(
      'amount',
        case
          when upper(coalesce(d.currency,'IQD'))='USD'
               and coalesce(d.dollar_rate,0)>0
            then round((i.amount/d.dollar_rate)::numeric,2)
          else i.amount
        end,
      'currency',
        case
          when upper(coalesce(d.currency,'IQD'))='USD'
               and coalesce(d.dollar_rate,0)>0
            then 'USD'
          else 'IQD'
        end,
      'market_name', tenant.market_name,
      'occurred_at', now(),
      'due_date', i.due_date,
      'overdue', i.due_date<current_date,
      'installment_no', i.installment_no,
      'debt_id', i.debt_id,
      'days_until_due', greatest(i.due_date-current_date,0),
      'days_overdue', greatest(current_date-i.due_date,0),
      'overdue_interval_days', coalesce(settings.overdue_interval_days,3)
    ),
    '/?view=transactions&event=' || i.debt_id::text,
    false
  from public.debt_installments i
  join public.debts d on d.id=i.debt_id
  join public.profiles customer on customer.id=i.customer_id
  join public.profiles tenant on tenant.id=i.admin_id
  left join public.customer_notification_preferences pref
    on pref.customer_id=i.customer_id
   and pref.market_id=i.admin_id
  left join public.market_notification_settings settings
    on settings.market_id=i.admin_id
  where i.status='pending'
    and d.is_deleted=false
    and d.remaining>0
    and customer.role='customer'
    and customer.active=true
    and customer.approved=true
    and tenant.role='admin'
    and tenant.active=true
    and tenant.approved=true
    and coalesce(pref.installment_reminders,true)=true
    and private.customer_portal_enabled(i.customer_id,i.admin_id)
    and (
      i.due_date-current_date in (3,1,0)
      or (
        i.due_date<current_date
        and mod(
          current_date-i.due_date,
          coalesce(settings.overdue_interval_days,3)
        )=0
      )
    )
  on conflict (idempotency_key) do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$function$;
