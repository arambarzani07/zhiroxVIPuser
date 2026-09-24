-- General customer payment ledger.
-- General payments reduce only the customer's effective total balance.
-- Debt-specific payments continue to mutate only the selected debt.

create table if not exists public.customer_general_payments (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  amount numeric not null check (amount > 0),
  note text not null default '',
  created_by uuid references public.profiles(id) on delete set null,
  reference_kind text,
  reference_id uuid,
  reference_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint customer_general_payments_reference_pair_chk check (
    (reference_kind is null and reference_id is null)
    or (
      reference_kind = any(array['debt'::text,'payment'::text])
      and reference_id is not null
    )
  )
);

create index if not exists customer_general_payments_customer_created_idx
  on public.customer_general_payments(customer_id, created_at desc, id desc);
create index if not exists customer_general_payments_admin_created_idx
  on public.customer_general_payments(admin_id, created_at desc, id desc);
create index if not exists customer_general_payments_created_by_idx
  on public.customer_general_payments(created_by)
  where created_by is not null;

alter table public.customer_general_payments enable row level security;

drop policy if exists customer_general_payments_select_authorized
  on public.customer_general_payments;
create policy customer_general_payments_select_authorized
on public.customer_general_payments
for select
to authenticated
using (
  (
    customer_id = (select auth.uid())
    and (select private."current_role"()) = 'customer'
  )
  or (
    (select private."current_role"()) = 'admin'
    and admin_id = (select private.current_admin_id())
  )
  or (
    (select private."current_role"()) = 'employee'
    and (
      (select private.employee_has_permission('view_debts'))
      or (select private.employee_has_permission('view_financial_reports'))
    )
    and admin_id = (select private.current_admin_id())
  )
);

revoke all on table public.customer_general_payments from public, anon;
revoke insert, update, delete on table public.customer_general_payments from authenticated;
grant select on table public.customer_general_payments to authenticated;
grant all on table public.customer_general_payments to service_role;


CREATE OR REPLACE FUNCTION private.customer_lifetime_paid_total(p_customer_id uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_role text := private."current_role"();
  v_admin_id uuid := private.current_admin_id();
  v_specific numeric := 0;
  v_general numeric := 0;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.profiles c
    where c.id = p_customer_id
      and c.role = 'customer'
      and (
        (v_role = 'customer' and c.id = v_uid)
        or (
          v_role = any (array['admin'::text, 'employee'::text])
          and v_admin_id is not null
          and private.profile_tenant_id(c.id) = v_admin_id
        )
      )
  ) then
    raise exception 'customer_finance_forbidden' using errcode = '42501';
  end if;

  select coalesce(sum(p.amount), 0)::numeric
    into v_specific
  from public.payments p
  join public.debts d on d.id = p.debt_id
  where d.customer_id = p_customer_id;

  select coalesce(sum(g.amount), 0)::numeric
    into v_general
  from public.customer_general_payments g
  where g.customer_id = p_customer_id;

  return coalesce(v_specific, 0) + coalesce(v_general, 0);
end;
$function$;

CREATE OR REPLACE FUNCTION private.enqueue_customer_push_debt_after_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_market_id uuid;
  v_market_name text := '';
  v_remaining_iqd numeric := 0;
  v_currency text := 'IQD';
  v_amount numeric := 0;
begin
  if coalesce(new.is_deleted, false) then
    return new;
  end if;

  if coalesce(new.reference_snapshot ->> 'source', '') in (
    'legacy_import',
    'daftar_live_sync'
  ) then
    return new;
  end if;

  select customer.admin_id, coalesce(tenant.market_name, '')
    into v_market_id, v_market_name
  from public.profiles customer
  join public.profiles tenant
    on tenant.id = customer.admin_id
   and tenant.role = 'admin'
   and tenant.active = true
   and tenant.approved = true
   and (
     tenant.is_system_owner
     or tenant.subscription_end is null
     or tenant.subscription_end >= now()
   )
  where customer.id = new.customer_id
    and customer.role = 'customer'
    and customer.active = true
    and customer.approved = true;

  if v_market_id is null then
    return new;
  end if;

  select public.get_customer_effective_balance(new.customer_id)
    into v_remaining_iqd;

  if upper(coalesce(new.currency, 'IQD')) = 'USD'
     and coalesce(new.dollar_rate, 0) > 0 then
    v_currency := 'USD';
    v_amount := case
      when coalesce(new.amount_usd, 0) > 0 then new.amount_usd
      else round((new.amount / new.dollar_rate)::numeric, 2)
    end;
  else
    v_currency := 'IQD';
    v_amount := coalesce(new.amount, 0);
  end if;

  begin
    perform public.enqueue_customer_push_event_service(
      v_market_id,
      new.customer_id,
      'debt_created',
      new.id,
      'debt_created:' || new.id::text,
      jsonb_build_object(
        'amount', v_amount,
        'currency', v_currency,
        'remaining_iqd', v_remaining_iqd,
        'market_name', v_market_name,
        'occurred_at', coalesce(new.custom_date, new.created_at, now())
      )
    );
  exception when others then
    raise warning 'customer debt push enqueue deferred for %: %',
      new.id, sqlerrm;
  end;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.enqueue_customer_push_payment_after_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_customer_id uuid;
  v_market_id uuid;
  v_market_name text := '';
  v_currency text := 'IQD';
  v_dollar_rate numeric := 0;
  v_remaining_iqd numeric := 0;
  v_amount numeric := 0;
begin
  if current_setting('zhirox.payment_rpc', true) = 'on' then
    return new;
  end if;

  select d.customer_id,
         customer.admin_id,
         coalesce(tenant.market_name, ''),
         upper(coalesce(d.currency, 'IQD')),
         coalesce(d.dollar_rate, 0)
    into v_customer_id, v_market_id, v_market_name, v_currency, v_dollar_rate
  from public.debts d
  join public.profiles customer
    on customer.id = d.customer_id
   and customer.role = 'customer'
   and customer.active = true
   and customer.approved = true
  join public.profiles tenant
    on tenant.id = customer.admin_id
   and tenant.role = 'admin'
   and tenant.active = true
   and tenant.approved = true
   and (
     tenant.is_system_owner
     or tenant.subscription_end is null
     or tenant.subscription_end >= now()
   )
  where d.id = new.debt_id
    and d.is_deleted = false;

  if v_customer_id is null or v_market_id is null then
    return new;
  end if;

  select public.get_customer_effective_balance(v_customer_id)
    into v_remaining_iqd;

  if v_currency = 'USD' and v_dollar_rate > 0 then
    v_amount := round((new.amount / v_dollar_rate)::numeric, 2);
  else
    v_currency := 'IQD';
    v_amount := coalesce(new.amount, 0);
  end if;

  begin
    perform public.enqueue_customer_push_event_service(
      v_market_id,
      v_customer_id,
      'payment_created',
      new.id,
      'payment_created:' || new.id::text,
      jsonb_build_object(
        'amount', v_amount,
        'currency', v_currency,
        'remaining_iqd', v_remaining_iqd,
        'market_name', v_market_name,
        'occurred_at', coalesce(new.created_at, now()),
        'payment_scope', 'debt'
      )
    );
  exception when others then
    raise warning 'customer payment push enqueue deferred for %: %',
      new.id, sqlerrm;
  end;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.populate_financial_reference()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_customer_id uuid;
  v_ref_customer_id uuid;
  v_ref_amount numeric;
  v_ref_currency text;
  v_ref_text text;
  v_ref_created_at timestamptz;
begin
  if tg_op = 'UPDATE'
     and new.reference_kind is not distinct from old.reference_kind
     and new.reference_id is not distinct from old.reference_id then
    return new;
  end if;

  if new.reference_kind is null and new.reference_id is null then
    new.reference_snapshot := '{}'::jsonb;
    return new;
  end if;

  if new.reference_kind is null
     or new.reference_id is null
     or new.reference_kind not in ('debt', 'payment') then
    raise exception 'invalid_financial_reference' using errcode = '22023';
  end if;

  if tg_table_name = 'debts' then
    v_customer_id := new.customer_id;
    if new.reference_kind = 'debt' and new.reference_id = new.id then
      raise exception 'self_financial_reference' using errcode = '22023';
    end if;
  elsif tg_table_name = 'payments' then
    select d.customer_id into v_customer_id
    from public.debts d
    where d.id = new.debt_id;
    if new.reference_kind = 'payment' and new.reference_id = new.id then
      raise exception 'self_financial_reference' using errcode = '22023';
    end if;
  elsif tg_table_name = 'customer_general_payments' then
    v_customer_id := new.customer_id;
  else
    raise exception 'unsupported_financial_reference_table' using errcode = '22023';
  end if;

  if v_customer_id is null then
    raise exception 'financial_reference_customer_not_found' using errcode = '23503';
  end if;

  if new.reference_kind = 'debt' then
    select d.customer_id,
           d.amount,
           coalesce(nullif(d.currency, ''), 'IQD'),
           nullif(trim(d.description), ''),
           d.created_at
      into v_ref_customer_id, v_ref_amount, v_ref_currency, v_ref_text, v_ref_created_at
    from public.debts d
    where d.id = new.reference_id;
  else
    select d.customer_id,
           p.amount,
           coalesce(nullif(d.currency, ''), 'IQD'),
           nullif(trim(p.note), ''),
           p.created_at
      into v_ref_customer_id, v_ref_amount, v_ref_currency, v_ref_text, v_ref_created_at
    from public.payments p
    join public.debts d on d.id = p.debt_id
    where p.id = new.reference_id;
  end if;

  if v_ref_customer_id is null then
    raise exception 'financial_reference_not_found' using errcode = '23503';
  end if;

  if v_ref_customer_id <> v_customer_id then
    raise exception 'cross_customer_financial_reference_forbidden' using errcode = '42501';
  end if;

  new.reference_snapshot := jsonb_build_object(
    'kind', new.reference_kind,
    'id', new.reference_id,
    'amount', coalesce(v_ref_amount, 0),
    'currency', coalesce(v_ref_currency, 'IQD'),
    'text', coalesce(v_ref_text, ''),
    'created_at', v_ref_created_at
  );

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.enqueue_customer_due_reminders_service()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    select public.get_customer_effective_balance(debt.customer_id)::numeric
      as remaining_iqd
  ) balances on true
  where debt.is_deleted = false
    and debt.remaining > 0
    and balances.remaining_iqd > 0
    and debt.due_date is not null
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
    )
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

CREATE OR REPLACE FUNCTION public.enqueue_customer_monthly_statements_service()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_inserted integer := 0;
  v_start timestamptz := date_trunc('month', now()) - interval '1 month';
  v_end timestamptz := date_trunc('month', now());
  v_period text := to_char(
    date_trunc('month', now()) - interval '1 month',
    'YYYY-MM'
  );
begin
  insert into public.notification_outbox(
    market_id, customer_id, event_type, event_record_id,
    idempotency_key, payload, deep_link, requires_ack
  )
  select
    customer.admin_id,
    customer.id,
    'monthly_statement',
    customer.id,
    'monthly_statement:' || customer.id::text || ':' || v_period,
    jsonb_build_object(
      'market_name', tenant.market_name,
      'occurred_at', now(),
      'period', v_period,
      'total_debt', coalesce(monthly.total_debt,0),
      'total_paid', coalesce(monthly.total_paid,0),
      'remaining_iqd', coalesce(balance.remaining_iqd,0),
      'general_paid_iqd', coalesce(monthly.general_paid,0)
    ),
    '/?view=transactions&period=' || v_period,
    false
  from public.profiles customer
  join public.profiles tenant on tenant.id = customer.admin_id
  left join public.customer_notification_preferences pref
    on pref.customer_id = customer.id
   and pref.market_id = customer.admin_id
  left join lateral (
    select
      coalesce(sum(d.amount),0)::numeric as total_debt,
      (
        coalesce((
          select sum(p.amount)
          from public.payments p
          join public.debts pd on pd.id = p.debt_id
          where pd.customer_id = customer.id
            and p.created_at >= v_start
            and p.created_at < v_end
        ),0)
        +
        coalesce((
          select sum(g.amount)
          from public.customer_general_payments g
          where g.customer_id = customer.id
            and g.created_at >= v_start
            and g.created_at < v_end
        ),0)
      )::numeric as total_paid,
      coalesce((
        select sum(g.amount)
        from public.customer_general_payments g
        where g.customer_id = customer.id
          and g.created_at >= v_start
          and g.created_at < v_end
      ),0)::numeric as general_paid
    from public.debts d
    where d.customer_id = customer.id
      and d.is_deleted = false
      and coalesce(d.custom_date,d.created_at) >= v_start
      and coalesce(d.custom_date,d.created_at) < v_end
  ) monthly on true
  left join lateral (
    select public.get_customer_effective_balance(customer.id)::numeric
      as remaining_iqd
  ) balance on true
  where customer.role = 'customer'
    and customer.active = true
    and customer.approved = true
    and tenant.role = 'admin'
    and tenant.active = true
    and tenant.approved = true
    and (
      tenant.is_system_owner
      or tenant.subscription_end is null
      or tenant.subscription_end >= now()
    )
    and coalesce(pref.monthly_statements,true) = true
    and private.customer_portal_enabled(customer.id,customer.admin_id)
  on conflict (idempotency_key) do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_admin_dashboard_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_result jsonb;
  v_admin_id uuid := auth.uid();
  v_projection jsonb := private.get_daftar_projection_summary();
  v_use_daftar_projection boolean := v_projection <> '{}'::jsonb;
begin
  if private."current_role"() is distinct from 'admin' then
    raise insufficient_privilege using message = 'admin role required';
  end if;

  with official_customer_ids as materialized (
    select x.customer_id
    from private.get_daftar_official_customer_totals(null) x
  ),
  visible_customer_ids as materialized (
    select p.id
    from public.profiles p
    where p.admin_id = v_admin_id
      and p.role = 'customer'
      and (
        not v_use_daftar_projection
        or exists (
          select 1
          from official_customer_ids o
          where o.customer_id = p.id
        )
      )
  ),
  general_paid as materialized (
    select coalesce(sum(g.amount), 0)::numeric as amount
    from public.customer_general_payments g
    join visible_customer_ids visible on visible.id = g.customer_id
  ),
  recent_rows as materialized (
    select
      d.created_at,
      d.id::text as sort_id,
      jsonb_build_object(
        'id', d.id,
        'event_type', 'debt',
        'amount', d.amount,
        'currency', coalesce(d.currency, 'IQD'),
        'created_at', d.created_at,
        'customer_id', d.customer_id,
        'customer', jsonb_build_object(
          'id', customer.id,
          'name', customer.name,
          'role', customer.role,
          'created_at', customer.created_at,
          'updated_at', customer.updated_at
        ),
        'created_by', case when creator.id is null then null else jsonb_build_object(
          'id', creator.id,
          'name', creator.name,
          'role', creator.role,
          'created_at', creator.created_at,
          'updated_at', creator.updated_at
        ) end
      ) as payload
    from public.debts d
    join visible_customer_ids visible on visible.id = d.customer_id
    join public.profiles customer on customer.id = d.customer_id
    left join public.profiles creator on creator.id = d.created_by
    where d.is_deleted = false
      and d.created_at >= now() - interval '24 hours'
      and d.created_at <= now()

    union all

    select
      pay.created_at,
      pay.id::text as sort_id,
      jsonb_build_object(
        'id', pay.id,
        'event_type', 'payment',
        'payment_scope', 'debt',
        'amount', pay.amount,
        'currency', coalesce(d.currency, 'IQD'),
        'created_at', pay.created_at,
        'customer_id', d.customer_id,
        'debt_id', pay.debt_id,
        'customer', jsonb_build_object(
          'id', customer.id,
          'name', customer.name,
          'role', customer.role,
          'created_at', customer.created_at,
          'updated_at', customer.updated_at
        ),
        'created_by', case when creator.id is null then null else jsonb_build_object(
          'id', creator.id,
          'name', creator.name,
          'role', creator.role,
          'created_at', creator.created_at,
          'updated_at', creator.updated_at
        ) end
      ) as payload
    from public.payments pay
    join public.debts d on d.id = pay.debt_id
    join visible_customer_ids visible on visible.id = d.customer_id
    join public.profiles customer on customer.id = d.customer_id
    left join public.profiles creator on creator.id = pay.created_by
    where d.is_deleted = false
      and pay.created_at >= now() - interval '24 hours'
      and pay.created_at <= now()

    union all

    select
      g.created_at,
      g.id::text as sort_id,
      jsonb_build_object(
        'id', g.id,
        'event_type', 'payment',
        'payment_scope', 'general',
        'amount', g.amount,
        'currency', 'IQD',
        'created_at', g.created_at,
        'customer_id', g.customer_id,
        'debt_id', null,
        'customer', jsonb_build_object(
          'id', customer.id,
          'name', customer.name,
          'role', customer.role,
          'created_at', customer.created_at,
          'updated_at', customer.updated_at
        ),
        'created_by', case when creator.id is null then null else jsonb_build_object(
          'id', creator.id,
          'name', creator.name,
          'role', creator.role,
          'created_at', creator.created_at,
          'updated_at', creator.updated_at
        ) end
      ) as payload
    from public.customer_general_payments g
    join visible_customer_ids visible on visible.id = g.customer_id
    join public.profiles customer on customer.id = g.customer_id
    left join public.profiles creator on creator.id = g.created_by
    where g.created_at >= now() - interval '24 hours'
      and g.created_at <= now()
  ),
  limited_recent_rows as materialized (
    select r.created_at, r.sort_id, r.payload
    from recent_rows r
    order by r.created_at desc, r.sort_id desc
    limit 250
  )
  select jsonb_build_object(
    'total_customers', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_total_customers')::integer, 0)
      else (select count(*) from visible_customer_ids)
    end,
    'pending_requests', (
      select count(*)
      from public.profiles p
      where p.admin_id = v_admin_id
        and p.role = 'customer'
        and p.approved = false
    ),
    'total_debt', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_total_loan_iqd')::numeric, 0)
      else coalesce((
        select sum(d.amount)
        from public.debts d
        join visible_customer_ids visible on visible.id = d.customer_id
        where d.is_deleted = false
          and upper(coalesce(d.currency, 'IQD')) <> 'USD'
      ), 0)
    end,
    'total_remaining', greatest(
      case
        when v_use_daftar_projection
          then coalesce((v_projection->>'official_balance_iqd')::numeric, 0)
        else coalesce((
          select sum(d.remaining)
          from public.debts d
          join visible_customer_ids visible on visible.id = d.customer_id
          where d.is_deleted = false
            and upper(coalesce(d.currency, 'IQD')) <> 'USD'
        ), 0)
      end - (select amount from general_paid),
      0
    ),
    'total_payments', (
      case
        when v_use_daftar_projection
          then coalesce((v_projection->>'official_total_payment_iqd')::numeric, 0)
        else coalesce((
          select sum(pay.amount)
          from public.payments pay
          join public.debts d on d.id = pay.debt_id
          join visible_customer_ids visible on visible.id = d.customer_id
          where d.is_deleted = false
            and upper(coalesce(d.currency, 'IQD')) <> 'USD'
        ), 0)
      end + (select amount from general_paid)
    ),
    'total_debt_usd', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_total_loan_usd')::numeric, 0)
      else coalesce((
        select sum(d.amount)
        from public.debts d
        join visible_customer_ids visible on visible.id = d.customer_id
        where d.is_deleted = false
          and upper(coalesce(d.currency, 'IQD')) = 'USD'
      ), 0)
    end,
    'total_remaining_usd', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_balance_usd')::numeric, 0)
      else coalesce((
        select sum(d.remaining)
        from public.debts d
        join visible_customer_ids visible on visible.id = d.customer_id
        where d.is_deleted = false
          and upper(coalesce(d.currency, 'IQD')) = 'USD'
      ), 0)
    end,
    'total_payments_usd', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_total_payment_usd')::numeric, 0)
      else coalesce((
        select sum(pay.amount)
        from public.payments pay
        join public.debts d on d.id = pay.debt_id
        join visible_customer_ids visible on visible.id = d.customer_id
        where d.is_deleted = false
          and upper(coalesce(d.currency, 'IQD')) = 'USD'
      ), 0)
    end,
    'pending_debts', (
      select count(*)
      from public.debts d
      join visible_customer_ids visible on visible.id = d.customer_id
      where d.is_deleted = false
        and d.status <> 'paid'
    ),
    'recent_activity', coalesce((
      select jsonb_agg(r.payload order by r.created_at desc, r.sort_id desc)
      from limited_recent_rows r
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_customer_directory_page(p_search text DEFAULT ''::text, p_limit integer DEFAULT 60, p_cursor_created_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with settings as (
    select
      greatest(1, least(coalesce(p_limit, 60), 100)) as page_size,
      nullif(trim(coalesce(p_search, '')), '') as search_text,
      (select private.current_admin_id()) as tenant_id
  ),
  projection as (
    select private.get_daftar_projection_summary() as j
  ),
  official_rows as materialized (
    select * from private.get_daftar_official_customer_totals(null)
  ),
  viewer_baseline as (
    select greatest(
      coalesce(
        (
          select p.created_at
          from public.profiles p
          where p.id = (select auth.uid())
        ),
        '2026-09-11 09:08:54+00'::timestamptz
      ),
      '2026-09-11 09:08:54+00'::timestamptz
    ) as baseline_at
  ),
  matching as materialized (
    select p.*
    from public.profiles p
    cross join settings s
    cross join projection pr
    where s.tenant_id is not null
      and (select private."current_role"()) in ('admin', 'employee')
      and p.admin_id = s.tenant_id
      and p.role = 'customer'
      and (
        pr.j = '{}'::jsonb
        or exists (
          select 1 from official_rows o where o.customer_id = p.id
        )
      )
      and (
        s.search_text is null
        or lower(
          coalesce(p.name, '') || ' ' ||
          coalesce(p.father_name, '') || ' ' ||
          coalesce(p.grandfather_name, '') || ' ' ||
          coalesce(p.phone, '')
        ) like '%' || lower(s.search_text) || '%'
      )
  ),
  page_profiles as (
    select p.*
    from matching p
    cross join settings s
    where p_cursor_created_at is null
       or (p.created_at, p.id) < (p_cursor_created_at, p_cursor_id)
    order by p.created_at desc, p.id desc
    limit (select page_size + 1 from settings)
  ),
  visible_profiles as (
    select p.*
    from page_profiles p
    order by p.created_at desc, p.id desc
    limit (select page_size from settings)
  ),
  rows_with_stats as (
    select
      p.*,
      greatest(
        coalesce(o.balance_iqd, ds.remaining, 0)
        - coalesce(gp.general_paid, 0),
        0
      )::numeric as remaining,
      coalesce(ds.open_debt_count, 0)::bigint as open_debt_count,
      la.event_at as last_activity_at,
      la.kind as last_kind,
      la.amount as last_amount,
      coalesce(la.preview, '') as last_preview,
      coalesce(la.event_type, '') as last_event_type,
      case
        when la.event_at is null then false
        when fr.last_read_at is not null then la.event_at > fr.last_read_at
        else la.event_at > vb.baseline_at
      end as unread
    from visible_profiles p
    left join official_rows o on o.customer_id = p.id
    left join lateral (
      select
        coalesce(sum(d.remaining), 0)::numeric as remaining,
        count(*)::bigint as open_debt_count
      from public.debts d
      where d.customer_id = p.id
        and d.is_deleted = false
        and d.remaining > 0
    ) ds on true
    left join lateral (
      select coalesce(sum(g.amount), 0)::numeric as general_paid
      from public.customer_general_payments g
      where g.customer_id = p.id
    ) gp on true
    left join lateral (
      select event_at, kind, amount, preview, event_type
      from (
        (
          select e.created_at as event_at, 4::smallint as kind_rank,
                 e.id as record_id, 'system'::text as kind,
                 e.amount::numeric as amount, nullif(e.description, '')::text as preview,
                 e.event_type::text as event_type
          from public.financial_events e
          where e.customer_id = p.id
          order by e.created_at desc, e.id desc
          limit 1
        )
        union all
        (
          select coalesce(d.custom_date, d.created_at), 3::smallint, d.id,
                 'debt'::text, d.amount::numeric, d.description::text, null::text
          from public.debts d
          where d.customer_id = p.id and d.is_deleted = false
          order by coalesce(d.custom_date, d.created_at) desc, d.id desc
          limit 1
        )
        union all
        (
          select pay.created_at, 2::smallint, pay.id, 'payment'::text,
                 pay.amount::numeric, nullif(pay.note, '')::text, null::text
          from public.payments pay
          join public.debts d on d.id = pay.debt_id
          where d.customer_id = p.id and d.is_deleted = false
          order by pay.created_at desc, pay.id desc
          limit 1
        )
        union all
        (
          select g.created_at, 2::smallint, g.id, 'payment'::text,
                 g.amount::numeric, nullif(g.note, '')::text, 'general_payment'::text
          from public.customer_general_payments g
          where g.customer_id = p.id
          order by g.created_at desc, g.id desc
          limit 1
        )
      ) candidates
      order by event_at desc, kind_rank desc, record_id desc
      limit 1
    ) la on true
    left join public.financial_chat_reads fr
      on fr.viewer_id = (select auth.uid()) and fr.customer_id = p.id
    cross join viewer_baseline vb
  ),
  page_meta as (
    select
      count(*)::bigint as total_count,
      (select count(*) > (select page_size from settings) from page_profiles) as has_more
    from matching
  )
  select jsonb_build_object(
    'items', coalesce(
      (
        select jsonb_agg(to_jsonb(r) order by r.created_at desc, r.id desc)
        from rows_with_stats r
      ),
      '[]'::jsonb
    ),
    'total_count', m.total_count,
    'has_more', m.has_more,
    'next_cursor', case
      when m.has_more then (
        select jsonb_build_object('created_at', r.created_at, 'id', r.id)
        from rows_with_stats r
        order by r.created_at asc, r.id asc
        limit 1
      )
      else null
    end
  )
  from page_meta m;
$function$;

CREATE OR REPLACE FUNCTION public.get_customer_directory_page_filtered(p_search text DEFAULT ''::text, p_filter text DEFAULT 'all'::text, p_limit integer DEFAULT 60, p_cursor_created_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with settings as (
    select
      greatest(1, least(coalesce(p_limit, 60), 100)) as page_size,
      nullif(trim(coalesce(p_search, '')), '') as search_text,
      case
        when lower(trim(coalesce(p_filter, ''))) in (
          'with_debt', 'debt_free', 'active', 'inactive'
        ) then lower(trim(coalesce(p_filter, '')))
        else 'all'
      end as filter_key,
      (select private.current_admin_id()) as tenant_id
  ),
  viewer_baseline as (
    select greatest(
      coalesce(
        (
          select p.created_at
          from public.profiles p
          where p.id = (select auth.uid())
        ),
        '2026-09-11 09:08:54+00'::timestamptz
      ),
      '2026-09-11 09:08:54+00'::timestamptz
    ) as baseline_at
  ),
  matching as materialized (
    select p.*
    from public.profiles p
    cross join settings s
    where s.tenant_id is not null
      and (select private."current_role"()) in ('admin', 'employee')
      and p.admin_id = s.tenant_id
      and p.role = 'customer'
      and (
        s.search_text is null
        or lower(
          coalesce(p.name, '') || ' ' ||
          coalesce(p.father_name, '') || ' ' ||
          coalesce(p.grandfather_name, '') || ' ' ||
          coalesce(p.phone, '')
        ) like '%' || lower(s.search_text) || '%'
      )
      and (
        s.filter_key = 'all'
        or (s.filter_key = 'active' and p.active is true)
        or (s.filter_key = 'inactive' and p.active is false)
        or (
          s.filter_key = 'with_debt'
          and public.get_customer_effective_balance(p.id) > 0
        )
        or (
          s.filter_key = 'debt_free'
          and public.get_customer_effective_balance(p.id) <= 0
        )
      )
  ),
  page_profiles as (
    select p.*
    from matching p
    cross join settings s
    where p_cursor_created_at is null
       or p_cursor_id is null
       or (p.created_at, p.id) < (p_cursor_created_at, p_cursor_id)
    order by p.created_at desc, p.id desc
    limit (select page_size + 1 from settings)
  ),
  visible_profiles as (
    select p.*
    from page_profiles p
    order by p.created_at desc, p.id desc
    limit (select page_size from settings)
  ),
  rows_with_stats as (
    select
      p.*,
      greatest(
        coalesce(ds.remaining, 0) - coalesce(gp.general_paid, 0),
        0
      )::numeric as remaining,
      coalesce(ds.open_debt_count, 0)::bigint as open_debt_count,
      la.event_at as last_activity_at,
      la.kind as last_kind,
      la.amount as last_amount,
      coalesce(la.preview, '') as last_preview,
      coalesce(la.event_type, '') as last_event_type,
      case
        when la.event_at is null then false
        when fr.last_read_at is not null then la.event_at > fr.last_read_at
        else la.event_at > vb.baseline_at
      end as unread
    from visible_profiles p
    left join lateral (
      select
        coalesce(sum(d.remaining), 0)::numeric as remaining,
        count(*)::bigint as open_debt_count
      from public.debts d
      where d.customer_id = p.id
        and d.is_deleted = false
        and d.remaining > 0
    ) ds on true
    left join lateral (
      select coalesce(sum(g.amount), 0)::numeric as general_paid
      from public.customer_general_payments g
      where g.customer_id = p.id
    ) gp on true
    left join lateral (
      select event_at, kind, amount, preview, event_type
      from (
        (
          select
            e.created_at as event_at,
            4::smallint as kind_rank,
            e.id as record_id,
            'system'::text as kind,
            e.amount::numeric as amount,
            nullif(e.description, '')::text as preview,
            e.event_type::text as event_type
          from public.financial_events e
          where e.customer_id = p.id
          order by e.created_at desc, e.id desc
          limit 1
        )
        union all
        (
          select
            coalesce(d.custom_date, d.created_at) as event_at,
            3::smallint as kind_rank,
            d.id as record_id,
            'debt'::text as kind,
            d.amount::numeric as amount,
            d.description::text as preview,
            null::text as event_type
          from public.debts d
          where d.customer_id = p.id
            and d.is_deleted = false
          order by coalesce(d.custom_date, d.created_at) desc, d.id desc
          limit 1
        )
        union all
        (
          select
            pay.created_at as event_at,
            2::smallint as kind_rank,
            pay.id as record_id,
            'payment'::text as kind,
            pay.amount::numeric as amount,
            nullif(pay.note, '')::text as preview,
            null::text as event_type
          from public.payments pay
          join public.debts d on d.id = pay.debt_id
          where d.customer_id = p.id
            and d.is_deleted = false
          order by pay.created_at desc, pay.id desc
          limit 1
        )
        union all
        (
          select
            g.created_at as event_at,
            2::smallint as kind_rank,
            g.id as record_id,
            'payment'::text as kind,
            g.amount::numeric as amount,
            nullif(g.note, '')::text as preview,
            'general_payment'::text as event_type
          from public.customer_general_payments g
          where g.customer_id = p.id
          order by g.created_at desc, g.id desc
          limit 1
        )
      ) candidates
      order by event_at desc, kind_rank desc, record_id desc
      limit 1
    ) la on true
    left join public.financial_chat_reads fr
      on fr.viewer_id = (select auth.uid())
     and fr.customer_id = p.id
    cross join viewer_baseline vb
  ),
  page_meta as (
    select
      count(*)::bigint as total_count,
      (select count(*) > (select page_size from settings) from page_profiles) as has_more
    from matching
  )
  select jsonb_build_object(
    'items', coalesce(
      (
        select jsonb_agg(to_jsonb(r) order by r.created_at desc, r.id desc)
        from rows_with_stats r
      ),
      '[]'::jsonb
    ),
    'total_count', m.total_count,
    'has_more', m.has_more,
    'next_cursor', case
      when m.has_more then (
        select jsonb_build_object('created_at', r.created_at, 'id', r.id)
        from rows_with_stats r
        order by r.created_at asc, r.id asc
        limit 1
      )
      else null
    end
  )
  from page_meta m;
$function$;

CREATE OR REPLACE FUNCTION public.get_customer_effective_balance(p_customer_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with official as (
    select o.balance_iqd
    from private.get_daftar_official_customer_totals(p_customer_id) o
    limit 1
  ),
  local_balance as (
    select coalesce(sum(d.remaining), 0)::numeric as amount
    from public.debts d
    where d.customer_id = p_customer_id
      and d.is_deleted = false
      and d.remaining > 0
  ),
  general_paid as (
    select coalesce(sum(g.amount), 0)::numeric as amount
    from public.customer_general_payments g
    where g.customer_id = p_customer_id
  )
  select greatest(
    coalesce((select balance_iqd from official),
             (select amount from local_balance),
             0)
    - coalesce((select amount from general_paid), 0),
    0
  )::numeric;
$function$;

CREATE OR REPLACE FUNCTION public.get_customer_finance_snapshot(p_customer_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with official as (
    select *
    from private.get_daftar_official_customer_totals(p_customer_id)
    limit 1
  ),
  debt_rows as materialized (
    select d.*
    from public.debts d
    where d.customer_id = p_customer_id
      and d.is_deleted = false
  ),
  summary as (
    select
      coalesce(sum(d.amount), 0)::numeric as local_total_debt_iqd,
      coalesce(sum(d.remaining), 0)::numeric as local_total_remaining_iqd,
      count(*) filter (where d.remaining > 0)::bigint as open_debt_count
    from debt_rows d
  ),
  local_paid as (
    select private.customer_lifetime_paid_total(p_customer_id)::numeric
      as total_paid_iqd
  ),
  general_paid as (
    select coalesce(sum(g.amount), 0)::numeric as amount
    from public.customer_general_payments g
    where g.customer_id = p_customer_id
  ),
  open_debts as (
    select coalesce(
      jsonb_agg(
        to_jsonb(d)
        order by coalesce(d.custom_date, d.created_at) desc, d.id desc
      ),
      '[]'::jsonb
    ) as items
    from debt_rows d
    where d.remaining > 0
  )
  select jsonb_build_object(
    'total_debt_iqd',
      coalesce((select loan_iqd from official), s.local_total_debt_iqd),
    'total_remaining_iqd',
      greatest(
        coalesce(
          (select balance_iqd from official),
          s.local_total_remaining_iqd
        ) - gp.amount,
        0
      ),
    'total_paid_iqd',
      case
        when exists(select 1 from official)
          then coalesce((select payment_iqd from official), 0) + gp.amount
        else lp.total_paid_iqd
      end,
    'general_paid_iqd', gp.amount,
    'gross_remaining_iqd',
      coalesce(
        (select balance_iqd from official),
        s.local_total_remaining_iqd
      ),
    'open_debt_count', s.open_debt_count,
    'open_debts', o.items,
    'complete', true
  )
  from summary s
  cross join local_paid lp
  cross join general_paid gp
  cross join open_debts o;
$function$;

CREATE OR REPLACE FUNCTION public.get_customer_financial_timeline_page(p_customer_id uuid, p_limit integer DEFAULT 50, p_cursor_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_kind smallint DEFAULT NULL::smallint, p_cursor_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with params as (
    select greatest(1, least(coalesce(p_limit, 50), 100))::integer as lim
  ),
  debt_source as (
    select
      'debt'::text as kind,
      3::smallint as kind_rank,
      d.id as record_id,
      coalesce(d.custom_date, d.created_at) as event_at,
      to_jsonb(d) as record,
      null::jsonb as related_debt
    from public.debts d
    where d.customer_id = p_customer_id
      and d.is_deleted = false
      and (
        p_cursor_at is null or p_cursor_kind is null or p_cursor_id is null
        or (coalesce(d.custom_date, d.created_at), 3::smallint, d.id)
           < (p_cursor_at, p_cursor_kind, p_cursor_id)
      )
    order by coalesce(d.custom_date, d.created_at) desc, d.id desc
    limit (select lim + 1 from params)
  ),
  payment_source as (
    select
      'payment'::text as kind,
      2::smallint as kind_rank,
      p.id as record_id,
      p.created_at as event_at,
      to_jsonb(p) || jsonb_build_object(
        'payment_scope', 'debt',
        'currency', coalesce(d.currency, 'IQD')
      ) as record,
      to_jsonb(d) as related_debt
    from public.payments p
    join public.debts d on d.id = p.debt_id
    where d.customer_id = p_customer_id
      and d.is_deleted = false
      and (
        p_cursor_at is null or p_cursor_kind is null or p_cursor_id is null
        or (p.created_at, 2::smallint, p.id)
           < (p_cursor_at, p_cursor_kind, p_cursor_id)
      )
    order by p.created_at desc, p.id desc
    limit (select lim + 1 from params)
  ),
  general_payment_source as (
    select
      'payment'::text as kind,
      2::smallint as kind_rank,
      g.id as record_id,
      g.created_at as event_at,
      jsonb_build_object(
        'id', g.id,
        'debt_id', null,
        'amount', g.amount,
        'note', g.note,
        'created_by', g.created_by,
        'reference_kind', g.reference_kind,
        'reference_id', g.reference_id,
        'reference_snapshot', g.reference_snapshot,
        'created_at', g.created_at,
        'payment_scope', 'general',
        'currency', 'IQD'
      ) as record,
      null::jsonb as related_debt
    from public.customer_general_payments g
    where g.customer_id = p_customer_id
      and (
        p_cursor_at is null or p_cursor_kind is null or p_cursor_id is null
        or (g.created_at, 2::smallint, g.id)
           < (p_cursor_at, p_cursor_kind, p_cursor_id)
      )
    order by g.created_at desc, g.id desc
    limit (select lim + 1 from params)
  ),
  event_source as (
    select
      'system'::text as kind,
      1::smallint as kind_rank,
      e.id as record_id,
      e.created_at as event_at,
      to_jsonb(e) as record,
      null::jsonb as related_debt
    from public.financial_events e
    where e.customer_id = p_customer_id
      and e.event_type in (
        'debt_updated',
        'debt_deleted',
        'payment_updated',
        'payment_deleted'
      )
      and (
        p_cursor_at is null or p_cursor_kind is null or p_cursor_id is null
        or (e.created_at, 1::smallint, e.id)
           < (p_cursor_at, p_cursor_kind, p_cursor_id)
      )
    order by e.created_at desc, e.id desc
    limit (select lim + 1 from params)
  ),
  combined as (
    select * from debt_source
    union all
    select * from payment_source
    union all
    select * from general_payment_source
    union all
    select * from event_source
  ),
  page_plus_one as (
    select c.*
    from combined c
    order by c.event_at desc, c.kind_rank desc, c.record_id desc
    limit (select lim + 1 from params)
  ),
  visible as (
    select p.*
    from page_plus_one p
    order by p.event_at desc, p.kind_rank desc, p.record_id desc
    limit (select lim from params)
  )
  select jsonb_build_object(
    'items', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'kind', v.kind,
            'kind_rank', v.kind_rank,
            'id', v.record_id,
            'event_at', v.event_at,
            'record', v.record,
            'related_debt', v.related_debt
          )
          order by v.event_at desc, v.kind_rank desc, v.record_id desc
        )
        from visible v
      ),
      '[]'::jsonb
    ),
    'has_more',
      (select count(*) from page_plus_one) > (select lim from params),
    'next_cursor', case
      when (select count(*) from page_plus_one) > (select lim from params)
      then (
        select jsonb_build_object(
          'at', v.event_at,
          'kind_rank', v.kind_rank,
          'id', v.record_id
        )
        from visible v
        order by v.event_at asc, v.kind_rank asc, v.record_id asc
        limit 1
      )
      else null
    end
  );
$function$;

CREATE OR REPLACE FUNCTION public.get_customer_inbox_rows(p_customer_ids uuid[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with viewer_baseline as (
    select greatest(
      coalesce(
        (
          select p.created_at
          from public.profiles p
          where p.id = (select auth.uid())
        ),
        '2026-09-11 09:08:54+00'::timestamptz
      ),
      '2026-09-11 09:08:54+00'::timestamptz
    ) as baseline_at
  ),
  requested as (
    select p.id
    from public.profiles p
    where p.id = any(coalesce(p_customer_ids, array[]::uuid[]))
      and p.role = 'customer'
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'customer_id', r.id,
      'remaining', greatest(
        coalesce(ds.remaining, 0) - coalesce(gp.general_paid, 0),
        0
      ),
      'open_debt_count', coalesce(ds.open_debt_count, 0),
      'last_activity_at', la.event_at,
      'last_kind', la.kind,
      'last_amount', la.amount,
      'last_preview', coalesce(la.preview, ''),
      'last_event_type', coalesce(la.event_type, ''),
      'unread', case
        when la.event_at is null then false
        when fr.last_read_at is not null then la.event_at > fr.last_read_at
        else la.event_at > vb.baseline_at
      end
    ) order by la.event_at desc nulls last, r.id
  ), '[]'::jsonb)
  from requested r
  left join lateral (
    select coalesce(sum(d.remaining), 0)::numeric as remaining,
           count(*)::bigint as open_debt_count
    from public.debts d
    where d.customer_id = r.id
      and d.is_deleted = false
      and d.remaining > 0
  ) ds on true
  left join lateral (
    select coalesce(sum(g.amount), 0)::numeric as general_paid
    from public.customer_general_payments g
    where g.customer_id = r.id
  ) gp on true
  left join lateral (
    select event_at, kind, amount, preview, event_type
    from (
      (
        select e.created_at as event_at, 4::smallint as kind_rank,
               e.id as record_id, 'system'::text as kind,
               e.amount::numeric as amount, nullif(e.description, '')::text as preview,
               e.event_type::text as event_type
        from public.financial_events e
        where e.customer_id = r.id
        order by e.created_at desc, e.id desc
        limit 1
      )
      union all
      (
        select coalesce(d.custom_date, d.created_at), 3::smallint, d.id,
               'debt'::text, d.amount::numeric, d.description::text, null::text
        from public.debts d
        where d.customer_id = r.id and d.is_deleted = false
        order by coalesce(d.custom_date, d.created_at) desc, d.id desc
        limit 1
      )
      union all
      (
        select pay.created_at, 2::smallint, pay.id, 'payment'::text,
               pay.amount::numeric, nullif(pay.note, '')::text, null::text
        from public.payments pay
        join public.debts d on d.id = pay.debt_id
        where d.customer_id = r.id and d.is_deleted = false
        order by pay.created_at desc, pay.id desc
        limit 1
      )
      union all
      (
        select g.created_at, 2::smallint, g.id, 'payment'::text,
               g.amount::numeric, nullif(g.note, '')::text, 'general_payment'::text
        from public.customer_general_payments g
        where g.customer_id = r.id
        order by g.created_at desc, g.id desc
        limit 1
      )
    ) candidates
    order by event_at desc, kind_rank desc, record_id desc
    limit 1
  ) la on true
  left join public.financial_chat_reads fr
    on fr.viewer_id = (select auth.uid()) and fr.customer_id = r.id
  cross join viewer_baseline vb;
$function$;

CREATE OR REPLACE FUNCTION public.read_customer_link(p_hash text, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  c public.profiles%rowtype;
  market text;
  result jsonb;
  rows jsonb;
  n integer := greatest(0, least(coalesce(p_offset,0),1000000));
  v_general_paid numeric := 0;
  v_gross_remaining numeric := 0;
begin
  select customer.* into c
  from public.customer_read_links l
  join public.profiles customer on customer.id=l.customer_id
  join public.profiles a on a.id=l.admin_id
  where l.token_hash=p_hash
    and l.expires_at>now()
    and customer.admin_id=l.admin_id
    and customer.role='customer'
    and customer.active
    and customer.approved
    and a.role='admin'
    and a.active
    and a.approved
    and (a.is_system_owner or a.subscription_end is null or a.subscription_end>=now());

  if c.id is null then
    raise exception 'link_unavailable' using errcode='42501';
  end if;

  select a.market_name into market
  from public.profiles a
  where a.id=c.admin_id;

  select coalesce(sum(d.remaining),0)
    into v_gross_remaining
  from public.debts d
  where d.customer_id=c.id and d.is_deleted=false;

  select coalesce(sum(g.amount),0)
    into v_general_paid
  from public.customer_general_payments g
  where g.customer_id=c.id;

  select jsonb_build_object(
    'name',c.name,
    'market',market,
    'debt_limit',c.debt_limit,
    'total_debt',coalesce(sum(d.amount),0),
    'remaining',greatest(v_gross_remaining-v_general_paid,0),
    'gross_remaining',v_gross_remaining,
    'general_paid',v_general_paid,
    'paid',coalesce(sum(d.amount-d.remaining),0)+v_general_paid,
    'as_of',now()
  )
  into result
  from public.debts d
  where d.customer_id=c.id and d.is_deleted=false;

  select coalesce(
    jsonb_agg(to_jsonb(t) order by t.date desc,t.kind,t.id),
    '[]'::jsonb
  )
  into rows
  from (
    select *
    from (
      select
        d.id,
        'debt'::text kind,
        d.amount,
        coalesce(d.custom_date,d.created_at) date,
        d.description note,
        null::text as payment_scope
      from public.debts d
      where d.customer_id=c.id and not d.is_deleted

      union all

      select
        p.id,
        'payment',
        p.amount,
        p.created_at,
        p.note,
        'debt'::text
      from public.payments p
      join public.debts d on d.id=p.debt_id
      where d.customer_id=c.id and not d.is_deleted

      union all

      select
        g.id,
        'payment',
        g.amount,
        g.created_at,
        g.note,
        'general'::text
      from public.customer_general_payments g
      where g.customer_id=c.id
    ) all_rows
    order by date desc,kind,id
    limit 51 offset n
  ) t;

  return result||jsonb_build_object('rows',rows,'offset',n);
end;
$function$;

CREATE OR REPLACE FUNCTION public.read_customer_push_portal_service(p_token_hash text DEFAULT NULL::text, p_endpoint text DEFAULT NULL::text, p_device_secret_hash text DEFAULT NULL::text, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_customer_id uuid;
  v_market_id uuid;
  v_customer_name text;
  v_customer_phone text;
  v_market_name text;
  v_market_phone text;
  v_market_address text;
  v_receipt_title text;
  v_footer_note text;
  v_primary_color text;
  v_debt_limit numeric;
  v_can_subscribe boolean := false;
  v_offset integer := greatest(0, least(coalesce(p_offset, 0), 1000000));
  v_totals jsonb := '[]'::jsonb;
  v_rows jsonb := '[]'::jsonb;
  v_general_paid_iqd numeric := 0;
  v_gross_remaining_iqd numeric := 0;
  v_effective_remaining_iqd numeric := 0;
begin
  if p_token_hash is not null and p_token_hash ~ '^[a-f0-9]{64}$' then
    select link.customer_id, link.market_id, true
    into v_customer_id, v_market_id, v_can_subscribe
    from public.customer_push_link_tokens link
    where link.token_hash = p_token_hash
      and link.revoked_at is null
    limit 1;
  elsif nullif(trim(coalesce(p_endpoint, '')), '') is not null
        and p_device_secret_hash is not null
        and p_device_secret_hash ~ '^[a-f0-9]{64}$' then
    select subscription.customer_id, subscription.market_id
    into v_customer_id, v_market_id
    from public.customer_push_subscriptions subscription
    where subscription.endpoint = p_endpoint
      and subscription.device_secret_hash = p_device_secret_hash
      and subscription.active = true
    limit 1;
  end if;

  select customer.name,
         customer.phone,
         tenant.market_name,
         coalesce(nullif(settings.phone, ''), tenant.phone),
         coalesce(settings.address, ''),
         coalesce(nullif(settings.receipt_title, ''), 'پسووڵەی ZHIROX'),
         coalesce(settings.footer_note, ''),
         coalesce(settings.primary_color, '#3157E0'),
         customer.debt_limit
  into v_customer_name, v_customer_phone, v_market_name, v_market_phone,
       v_market_address, v_receipt_title, v_footer_note, v_primary_color,
       v_debt_limit
  from public.profiles customer
  join public.profiles tenant on tenant.id = v_market_id
  left join public.market_receipt_settings settings on settings.admin_id = tenant.id
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

  if v_customer_name is null then
    raise no_data_found;
  end if;

  select coalesce(sum(d.remaining),0)::numeric
    into v_gross_remaining_iqd
  from public.debts d
  where d.customer_id=v_customer_id
    and d.is_deleted=false;

  select coalesce(sum(g.amount),0)::numeric
    into v_general_paid_iqd
  from public.customer_general_payments g
  where g.customer_id=v_customer_id;

  v_effective_remaining_iqd :=
    greatest(v_gross_remaining_iqd-v_general_paid_iqd,0);

  select coalesce(jsonb_agg(jsonb_build_object(
    'currency', totals.currency,
    'total_debt', totals.total_debt,
    'remaining', totals.remaining,
    'paid', totals.paid
  ) order by totals.currency), '[]'::jsonb)
  into v_totals
  from (
    select d.currency,
           coalesce(sum(d.amount), 0) as total_debt,
           coalesce(sum(d.remaining), 0) as remaining,
           coalesce(sum(d.amount - d.remaining), 0) as paid
    from public.debts d
    where d.customer_id = v_customer_id and d.is_deleted = false
    group by d.currency
  ) totals;

  select coalesce(
    jsonb_agg(
      to_jsonb(item)
      order by item.occurred_at desc, item.kind, item.id
    ),
    '[]'::jsonb
  )
  into v_rows
  from (
    select *
    from (
      select
        d.id,
        'debt'::text as kind,
        d.amount,
        d.remaining,
        d.currency,
        coalesce(d.custom_date, d.created_at) as occurred_at,
        d.due_date,
        d.status,
        d.description as note,
        d.items,
        d.created_at,
        null::text as payment_scope
      from public.debts d
      where d.customer_id = v_customer_id and d.is_deleted = false

      union all

      select
        p.id,
        'payment'::text,
        p.amount,
        null::numeric,
        d.currency,
        p.created_at,
        null::date,
        null::text,
        p.note,
        '[]'::jsonb,
        p.created_at,
        'debt'::text
      from public.payments p
      join public.debts d on d.id = p.debt_id
      where d.customer_id = v_customer_id and d.is_deleted = false

      union all

      select
        g.id,
        'payment'::text,
        g.amount,
        null::numeric,
        'IQD'::text,
        g.created_at,
        null::date,
        null::text,
        g.note,
        '[]'::jsonb,
        g.created_at,
        'general'::text
      from public.customer_general_payments g
      where g.customer_id = v_customer_id
    ) ledger
    order by occurred_at desc, kind, id
    limit 51 offset v_offset
  ) item;

  return jsonb_build_object(
    'customer_name', v_customer_name,
    'customer_phone', v_customer_phone,
    'market_name', v_market_name,
    'market_phone', v_market_phone,
    'market_address', v_market_address,
    'receipt_title', v_receipt_title,
    'footer_note', v_footer_note,
    'primary_color', v_primary_color,
    'debt_limit', v_debt_limit,
    'can_subscribe', v_can_subscribe,
    'totals', v_totals,
    'general_paid_iqd', v_general_paid_iqd,
    'gross_remaining_iqd', v_gross_remaining_iqd,
    'effective_remaining_iqd', v_effective_remaining_iqd,
    'rows', case when jsonb_array_length(v_rows) > 50 then v_rows - 50 else v_rows end,
    'offset', v_offset,
    'has_more', jsonb_array_length(v_rows) > 50,
    'as_of', now()
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.record_customer_payment_service(p_actor_id uuid, p_customer_id uuid, p_amount numeric, p_note text DEFAULT ''::text, p_reference_kind text DEFAULT NULL::text, p_reference_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text;
  v_admin_id uuid;
  v_customer_admin_id uuid;
  v_can_record boolean := false;
  v_gross_remaining numeric := 0;
  v_general_paid_before numeric := 0;
  v_effective_before numeric := 0;
  v_effective_after numeric := 0;
  v_general public.customer_general_payments%rowtype;
begin
  if p_actor_id is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select p.role,
         case when p.role = 'admin' then p.id else p.admin_id end,
         case
           when p.role = 'admin' then true
           when p.role = 'employee' then coalesce(p.can_record_payments, false)
           else false
         end
    into v_role, v_admin_id, v_can_record
  from public.profiles p
  join public.profiles tenant
    on tenant.id = case when p.role = 'admin' then p.id else p.admin_id end
   and tenant.role = 'admin'
   and tenant.active = true
   and tenant.approved = true
   and (tenant.subscription_end is null or tenant.subscription_end >= now())
  where p.id = p_actor_id
    and p.role in ('admin', 'employee')
    and p.active = true
    and p.approved = true;

  if v_role is null or v_admin_id is null or not v_can_record then
    raise exception 'payment_forbidden' using errcode = '42501';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_payment_amount' using errcode = '22023';
  end if;

  select customer.admin_id
    into v_customer_admin_id
  from public.profiles customer
  where customer.id = p_customer_id
    and customer.role = 'customer'
    and customer.active = true
    and customer.approved = true
  for update;

  if v_customer_admin_id is null or v_customer_admin_id <> v_admin_id then
    raise exception 'customer_not_found_or_forbidden' using errcode = '42501';
  end if;

  select coalesce(
    (
      select o.balance_iqd
      from private.get_daftar_official_customer_totals(p_customer_id) o
      limit 1
    ),
    (
      select coalesce(sum(d.remaining), 0)::numeric
      from public.debts d
      where d.customer_id = p_customer_id
        and d.is_deleted = false
        and d.remaining > 0
    ),
    0
  )
  into v_gross_remaining;

  select coalesce(sum(g.amount), 0)::numeric
    into v_general_paid_before
  from public.customer_general_payments g
  where g.customer_id = p_customer_id;

  v_effective_before := greatest(v_gross_remaining - v_general_paid_before, 0);

  if v_effective_before <= 0 then
    raise exception 'customer_balance_already_paid' using errcode = '22023';
  end if;

  if p_amount > v_effective_before + 0.0001 then
    raise exception 'payment_exceeds_customer_balance' using errcode = '22023';
  end if;

  insert into public.customer_general_payments(
    admin_id,
    customer_id,
    amount,
    note,
    created_by,
    reference_kind,
    reference_id
  ) values (
    v_admin_id,
    p_customer_id,
    p_amount,
    coalesce(p_note, ''),
    p_actor_id,
    p_reference_kind,
    p_reference_id
  )
  returning * into v_general;

  v_effective_after := greatest(v_effective_before - p_amount, 0);

  return jsonb_build_object(
    'id', v_general.id,
    'customer_id', p_customer_id,
    'payment_scope', 'general',
    'amount', v_general.amount,
    'note', v_general.note,
    'created_by', v_general.created_by,
    'created_at', v_general.created_at,
    'allocation_count', 0,
    'remaining', v_effective_after,
    'gross_remaining', v_gross_remaining,
    'general_paid_total', v_general_paid_before + p_amount,
    'payments', '[]'::jsonb
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.record_payment_service(p_actor_id uuid, p_debt_id uuid, p_amount numeric, p_note text DEFAULT ''::text, p_reference_kind text DEFAULT NULL::text, p_reference_id uuid DEFAULT NULL::uuid)
 RETURNS payments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text;
  v_admin_id uuid;
  v_can_record boolean := false;
  v_debt public.debts%rowtype;
  v_payment public.payments%rowtype;
  v_gross_remaining numeric := 0;
  v_general_paid numeric := 0;
  v_effective_before numeric := 0;
  v_new_remaining numeric;
  v_total_remaining numeric := 0;
  v_market_name text := '';
  v_currency text := 'IQD';
  v_display_amount numeric := 0;
begin
  if p_actor_id is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select p.role,
         case when p.role = 'admin' then p.id else p.admin_id end,
         case
           when p.role = 'admin' then true
           when p.role = 'employee' then coalesce(p.can_record_payments, false)
           else false
         end
    into v_role, v_admin_id, v_can_record
  from public.profiles p
  join public.profiles tenant
    on tenant.id = case when p.role = 'admin' then p.id else p.admin_id end
   and tenant.role = 'admin'
   and tenant.active = true
   and tenant.approved = true
   and (tenant.subscription_end is null or tenant.subscription_end >= now())
  where p.id = p_actor_id
    and p.role in ('admin', 'employee')
    and p.active = true
    and p.approved = true;

  if v_role is null or v_admin_id is null or not v_can_record then
    raise exception 'payment_forbidden' using errcode = '42501';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_payment_amount' using errcode = '22023';
  end if;

  select d.* into v_debt
  from public.debts d
  join public.profiles customer on customer.id = d.customer_id
  where d.id = p_debt_id
    and d.is_deleted = false
    and customer.admin_id = v_admin_id
  for update of d;

  if not found then
    raise exception 'debt_not_found_or_forbidden' using errcode = '42501';
  end if;

  if v_debt.remaining <= 0 then
    raise exception 'debt_already_paid' using errcode = '22023';
  end if;

  select coalesce(
    (
      select o.balance_iqd
      from private.get_daftar_official_customer_totals(v_debt.customer_id) o
      limit 1
    ),
    (
      select coalesce(sum(d.remaining), 0)::numeric
      from public.debts d
      where d.customer_id = v_debt.customer_id
        and d.is_deleted = false
        and d.remaining > 0
    ),
    0
  )
  into v_gross_remaining;

  select coalesce(sum(g.amount), 0)::numeric
    into v_general_paid
  from public.customer_general_payments g
  where g.customer_id = v_debt.customer_id;

  v_effective_before := greatest(v_gross_remaining - v_general_paid, 0);

  if p_amount > v_debt.remaining + 0.0001 then
    raise exception 'payment_exceeds_debt_balance' using errcode = '22023';
  end if;

  if p_amount > v_effective_before + 0.0001 then
    raise exception 'payment_exceeds_customer_balance' using errcode = '22023';
  end if;

  perform set_config('zhirox.payment_rpc', 'on', true);

  v_new_remaining := greatest(v_debt.remaining - p_amount, 0);

  insert into public.payments(
    debt_id, amount, note, created_by, reference_kind, reference_id
  ) values (
    p_debt_id, p_amount, coalesce(p_note, ''),
    p_actor_id, p_reference_kind, p_reference_id
  )
  returning * into v_payment;

  update public.debts
  set remaining = v_new_remaining,
      status = case when v_new_remaining <= 0 then 'paid' else 'partial' end,
      updated_at = now()
  where id = p_debt_id;

  v_total_remaining := greatest(v_effective_before - p_amount, 0);

  select coalesce(p.market_name, '')
    into v_market_name
  from public.profiles p
  where p.id = v_admin_id;

  if upper(coalesce(v_debt.currency, 'IQD')) = 'USD'
     and coalesce(v_debt.dollar_rate, 0) > 0 then
    v_currency := 'USD';
    v_display_amount := round((v_payment.amount / v_debt.dollar_rate)::numeric, 2);
  else
    v_currency := 'IQD';
    v_display_amount := v_payment.amount;
  end if;

  begin
    perform public.enqueue_customer_push_event_service(
      v_admin_id,
      v_debt.customer_id,
      'payment_created',
      v_payment.id,
      'payment_created:' || v_payment.id::text,
      jsonb_build_object(
        'amount', v_display_amount,
        'currency', v_currency,
        'remaining_iqd', v_total_remaining,
        'market_name', v_market_name,
        'occurred_at', coalesce(v_payment.created_at, now()),
        'payment_scope', 'debt'
      )
    );
  exception when others then
    raise warning 'customer payment push enqueue deferred for %: %',
      v_payment.id, sqlerrm;
  end;

  return v_payment;
end;
$function$;


drop trigger if exists customer_general_payments_populate_financial_reference
  on public.customer_general_payments;
create trigger customer_general_payments_populate_financial_reference
before insert or update of reference_kind, reference_id
on public.customer_general_payments
for each row execute function private.populate_financial_reference();

drop trigger if exists audit_customer_general_payments_changes
  on public.customer_general_payments;
create trigger audit_customer_general_payments_changes
after insert or delete or update
on public.customer_general_payments
for each row execute function private.audit_tenant_row();

revoke all on function public.get_customer_effective_balance(uuid)
  from public, anon;
grant execute on function public.get_customer_effective_balance(uuid)
  to authenticated, service_role;

revoke all on function public.record_customer_payment_service(
  uuid,uuid,numeric,text,text,uuid
) from public, anon, authenticated;
grant execute on function public.record_customer_payment_service(
  uuid,uuid,numeric,text,text,uuid
) to service_role;

revoke all on function public.record_payment_service(
  uuid,uuid,numeric,text,text,uuid
) from public, anon, authenticated;
grant execute on function public.record_payment_service(
  uuid,uuid,numeric,text,text,uuid
) to service_role;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname='supabase_realtime'
      and schemaname='public'
      and tablename='customer_general_payments'
  ) then
    alter publication supabase_realtime
      add table public.customer_general_payments;
  end if;
end
$$;
