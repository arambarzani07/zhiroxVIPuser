
create table if not exists public.market_notification_settings (
  market_id uuid primary key references public.profiles(id) on delete cascade,
  overdue_interval_days integer not null default 3
    check (overdue_interval_days between 1 and 30),
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.market_notification_settings enable row level security;
revoke all on table public.market_notification_settings from public, anon, authenticated;
grant all on table public.market_notification_settings to service_role;

create or replace function public.get_market_notification_settings_service(
  p_actor uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_role text;
  v_market_id uuid;
  v_interval integer := 3;
begin
  select role,
         case when role='admin' then id else admin_id end
    into v_role, v_market_id
  from public.profiles
  where id=p_actor and active=true and approved=true;

  if v_role <> 'admin' or v_market_id is null or v_market_id <> p_actor then
    raise exception 'forbidden' using errcode='42501';
  end if;

  select s.overdue_interval_days
    into v_interval
  from public.market_notification_settings s
  where s.market_id=v_market_id;

  return jsonb_build_object(
    'overdue_interval_days', coalesce(v_interval,3)
  );
end;
$function$;

create or replace function public.update_market_notification_settings_service(
  p_actor uuid,
  p_overdue_interval_days integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_role text;
  v_market_id uuid;
begin
  if p_overdue_interval_days is null
     or p_overdue_interval_days < 1
     or p_overdue_interval_days > 30 then
    raise exception 'invalid_overdue_interval' using errcode='22023';
  end if;

  select role,
         case when role='admin' then id else admin_id end
    into v_role, v_market_id
  from public.profiles
  where id=p_actor and active=true and approved=true;

  if v_role <> 'admin' or v_market_id is null or v_market_id <> p_actor then
    raise exception 'forbidden' using errcode='42501';
  end if;

  insert into public.market_notification_settings(
    market_id, overdue_interval_days, updated_by, updated_at
  )
  values(v_market_id,p_overdue_interval_days,p_actor,now())
  on conflict (market_id) do update
  set overdue_interval_days=excluded.overdue_interval_days,
      updated_by=excluded.updated_by,
      updated_at=now();

  return jsonb_build_object(
    'overdue_interval_days', p_overdue_interval_days
  );
end;
$function$;

revoke all on function public.get_market_notification_settings_service(uuid)
  from public, anon, authenticated;
revoke all on function public.update_market_notification_settings_service(uuid,integer)
  from public, anon, authenticated;
grant execute on function public.get_market_notification_settings_service(uuid)
  to service_role;
grant execute on function public.update_market_notification_settings_service(uuid,integer)
  to service_role;

create or replace function public.enqueue_customer_due_reminders_service()
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
    customer.admin_id,
    debt.customer_id,
    'due_reminder',
    debt.id,
    'due_reminder:' || debt.id::text || ':' ||
      case
        when debt.due_date - current_date = 3 then 'pre3'
        when debt.due_date - current_date = 1 then 'pre1'
        when debt.due_date = current_date then 'today'
        else 'overdue' || (current_date - debt.due_date)::text
      end || ':' || debt.due_date::text,
    jsonb_build_object(
      'amount',
        case
          when upper(coalesce(debt.currency,'IQD'))='USD'
               and coalesce(debt.dollar_rate,0) > 0
            then round((debt.remaining / debt.dollar_rate)::numeric,2)
          else debt.remaining
        end,
      'currency',
        case
          when upper(coalesce(debt.currency,'IQD'))='USD'
               and coalesce(debt.dollar_rate,0) > 0
            then 'USD'
          else 'IQD'
        end,
      'remaining_iqd', balances.remaining_iqd,
      'market_name', tenant.market_name,
      'occurred_at', now(),
      'due_date', debt.due_date,
      'overdue', debt.due_date < current_date,
      'days_until_due', greatest(debt.due_date - current_date,0),
      'days_overdue', greatest(current_date - debt.due_date,0),
      'overdue_interval_days', coalesce(settings.overdue_interval_days,3)
    ),
    '/?view=transactions&event=' || debt.id::text,
    false
  from public.debts debt
  join public.profiles customer on customer.id = debt.customer_id
  join public.profiles tenant on tenant.id = customer.admin_id
  left join public.customer_notification_preferences pref
    on pref.customer_id = debt.customer_id
   and pref.market_id = customer.admin_id
  left join public.market_notification_settings settings
    on settings.market_id = customer.admin_id
  join lateral (
    select coalesce(sum(item.remaining),0)::numeric as remaining_iqd
    from public.debts item
    where item.customer_id = debt.customer_id
      and item.is_deleted = false
      and item.remaining > 0
  ) balances on true
  where debt.is_deleted = false
    and debt.remaining > 0
    and debt.due_date is not null
    and customer.role = 'customer'
    and customer.active = true
    and customer.approved = true
    and tenant.role = 'admin'
    and tenant.active = true
    and tenant.approved = true
    and (tenant.is_system_owner or tenant.subscription_end is null or tenant.subscription_end >= now())
    and coalesce(pref.due_reminders,true) = true
    and private.customer_portal_enabled(debt.customer_id, customer.admin_id)
    and (
      debt.due_date - current_date in (3,1,0)
      or (
        debt.due_date < current_date
        and mod(
          current_date - debt.due_date,
          coalesce(settings.overdue_interval_days,3)
        ) = 0
      )
    )
  on conflict (idempotency_key) do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$function$;

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
        when i.due_date - current_date = 3 then 'pre3'
        when i.due_date - current_date = 1 then 'pre1'
        when i.due_date = current_date then 'today'
        else 'overdue' || (current_date - i.due_date)::text
      end || ':' || i.due_date::text,
    jsonb_build_object(
      'amount', i.amount,
      'currency', case
        when upper(coalesce(d.currency,'IQD'))='USD'
             and coalesce(d.dollar_rate,0) > 0 then 'USD'
        else 'IQD'
      end,
      'market_name', tenant.market_name,
      'occurred_at', now(),
      'due_date', i.due_date,
      'overdue', i.due_date < current_date,
      'installment_no', i.installment_no,
      'debt_id', i.debt_id,
      'days_until_due', greatest(i.due_date - current_date,0),
      'days_overdue', greatest(current_date - i.due_date,0),
      'overdue_interval_days', coalesce(settings.overdue_interval_days,3)
    ),
    '/?view=transactions&event=' || i.debt_id::text,
    false
  from public.debt_installments i
  join public.debts d on d.id = i.debt_id
  join public.profiles customer on customer.id = i.customer_id
  join public.profiles tenant on tenant.id = i.admin_id
  left join public.customer_notification_preferences pref
    on pref.customer_id = i.customer_id
   and pref.market_id = i.admin_id
  left join public.market_notification_settings settings
    on settings.market_id = i.admin_id
  where i.status = 'pending'
    and d.is_deleted = false
    and d.remaining > 0
    and customer.role = 'customer'
    and customer.active = true
    and customer.approved = true
    and tenant.role = 'admin'
    and tenant.active = true
    and tenant.approved = true
    and coalesce(pref.installment_reminders,true) = true
    and private.customer_portal_enabled(i.customer_id,i.admin_id)
    and (
      i.due_date - current_date in (3,1,0)
      or (
        i.due_date < current_date
        and mod(
          current_date - i.due_date,
          coalesce(settings.overdue_interval_days,3)
        ) = 0
      )
    )
  on conflict (idempotency_key) do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$function$;
