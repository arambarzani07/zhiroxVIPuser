-- Mirrors production migration 20260924214549: audit40_financial_integrity.
-- Payment writes are serialized per customer, general IQD credits never offset USD debt,
-- push outbox writes are part of the financial transaction, and general payments are reversible.

CREATE OR REPLACE FUNCTION private.get_customer_virtual_debt_balances(p_customer_id uuid)
 RETURNS TABLE(debt_id uuid, effective_remaining numeric, applied_general_credit numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with general_credit as (
    select coalesce(sum(g.amount), 0)::numeric as amount
    from public.customer_general_payments g
    where g.customer_id = p_customer_id
  ),
  ordered as (
    select
      d.id,
      d.remaining,
      upper(coalesce(d.currency, 'IQD')) as currency,
      coalesce(
        sum(
          case
            when upper(coalesce(d.currency, 'IQD')) <> 'USD'
              then d.remaining
            else 0
          end
        ) over (
          order by coalesce(d.custom_date, d.created_at) asc,
                   d.created_at asc,
                   d.id asc
          rows between unbounded preceding and 1 preceding
        ),
        0
      )::numeric as prior_iqd_remaining
    from public.debts d
    where d.customer_id = p_customer_id
      and d.is_deleted = false
      and d.remaining > 0
  )
  select
    o.id,
    case
      when o.currency = 'USD' then o.remaining
      else greatest(
        o.remaining - greatest(g.amount - o.prior_iqd_remaining, 0),
        0
      )
    end::numeric as effective_remaining,
    case
      when o.currency = 'USD' then 0
      else least(
        o.remaining,
        greatest(g.amount - o.prior_iqd_remaining, 0)
      )
    end::numeric as applied_general_credit
  from ordered o
  cross join general_credit g;
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
      and upper(coalesce(d.currency, 'IQD')) <> 'USD'
  ),
  general_paid as (
    select coalesce(sum(g.amount), 0)::numeric as amount
    from public.customer_general_payments g
    where g.customer_id = p_customer_id
  )
  select greatest(
    coalesce(
      (select balance_iqd from official),
      (select amount from local_balance),
      0
    ) - coalesce((select amount from general_paid), 0),
    0
  )::numeric;
$function$;
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
  if v_uid is not null and not exists (
    select 1
    from public.profiles c
    where c.id = p_customer_id
      and c.role = 'customer'
      and (
        (v_role = 'customer' and c.id = v_uid)
        or (
          v_role = any(array['admin'::text, 'employee'::text])
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
  where d.customer_id = p_customer_id
    and upper(coalesce(d.currency, 'IQD')) <> 'USD';

  select coalesce(sum(g.amount), 0)::numeric
    into v_general
  from public.customer_general_payments g
  where g.customer_id = p_customer_id;

  return coalesce(v_specific, 0) + coalesce(v_general, 0);
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
  v_market_name text := '';
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
   and (
     tenant.is_system_owner
     or tenant.subscription_end is null
     or tenant.subscription_end >= now()
   )
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
        and upper(coalesce(d.currency, 'IQD')) <> 'USD'
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
    admin_id, customer_id, amount, note, created_by, reference_kind, reference_id
  ) values (
    v_admin_id, p_customer_id, p_amount, coalesce(p_note, ''),
    p_actor_id, p_reference_kind, p_reference_id
  )
  returning * into v_general;

  v_effective_after := greatest(v_effective_before - p_amount, 0);

  select coalesce(p.market_name, '')
    into v_market_name
  from public.profiles p
  where p.id = v_admin_id;

  perform public.enqueue_customer_push_event_service(
    v_admin_id,
    p_customer_id,
    'payment_created',
    v_general.id,
    'payment_created:' || v_general.id::text,
    jsonb_build_object(
      'amount', v_general.amount,
      'currency', 'IQD',
      'remaining_iqd', v_effective_after,
      'market_name', v_market_name,
      'occurred_at', coalesce(v_general.created_at, now()),
      'payment_scope', 'general'
    )
  );

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
  v_customer_id uuid;
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
   and (
     tenant.is_system_owner
     or tenant.subscription_end is null
     or tenant.subscription_end >= now()
   )
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

  select d.customer_id
    into v_customer_id
  from public.debts d
  join public.profiles customer on customer.id = d.customer_id
  where d.id = p_debt_id
    and d.is_deleted = false
    and customer.role = 'customer'
    and customer.admin_id = v_admin_id;

  if v_customer_id is null then
    raise exception 'debt_not_found_or_forbidden' using errcode = '42501';
  end if;

  perform 1
  from public.profiles customer
  where customer.id = v_customer_id
    and customer.role = 'customer'
    and customer.active = true
    and customer.approved = true
  for update;

  if not found then
    raise exception 'customer_not_found_or_forbidden' using errcode = '42501';
  end if;

  select d.*
    into v_debt
  from public.debts d
  where d.id = p_debt_id
    and d.customer_id = v_customer_id
    and d.is_deleted = false
  for update;

  if not found then
    raise exception 'debt_not_found_or_forbidden' using errcode = '42501';
  end if;

  if v_debt.remaining <= 0 then
    raise exception 'debt_already_paid' using errcode = '22023';
  end if;

  if p_amount > v_debt.remaining + 0.0001 then
    raise exception 'payment_exceeds_debt_balance' using errcode = '22023';
  end if;

  if upper(coalesce(v_debt.currency, 'IQD')) <> 'USD' then
    select coalesce(
      (
        select o.balance_iqd
        from private.get_daftar_official_customer_totals(v_customer_id) o
        limit 1
      ),
      (
        select coalesce(sum(d.remaining), 0)::numeric
        from public.debts d
        where d.customer_id = v_customer_id
          and d.is_deleted = false
          and d.remaining > 0
          and upper(coalesce(d.currency, 'IQD')) <> 'USD'
      ),
      0
    )
    into v_gross_remaining;

    select coalesce(sum(g.amount), 0)::numeric
      into v_general_paid
    from public.customer_general_payments g
    where g.customer_id = v_customer_id;

    v_effective_before := greatest(v_gross_remaining - v_general_paid, 0);

    if p_amount > v_effective_before + 0.0001 then
      raise exception 'payment_exceeds_customer_balance' using errcode = '22023';
    end if;
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

  v_total_remaining := public.get_customer_effective_balance(v_customer_id);

  select coalesce(p.market_name, '')
    into v_market_name
  from public.profiles p
  where p.id = v_admin_id;

  if upper(coalesce(v_debt.currency, 'IQD')) = 'USD'
     and coalesce(v_debt.dollar_rate, 0) > 0 then
    v_currency := 'USD';
    v_display_amount := round((v_payment.amount / v_debt.dollar_rate)::numeric, 2);
  elsif upper(coalesce(v_debt.currency, 'IQD')) = 'USD' then
    v_currency := 'USD';
    v_display_amount := v_payment.amount;
  else
    v_currency := 'IQD';
    v_display_amount := v_payment.amount;
  end if;

  perform public.enqueue_customer_push_event_service(
    v_admin_id,
    v_customer_id,
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

  return v_payment;
end;
$function$;
CREATE OR REPLACE FUNCTION public.delete_general_payment_service(p_actor_id uuid, p_general_payment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_admin_id uuid;
  v_customer_id uuid;
  v_amount numeric;
  v_remaining numeric;
begin
  select p.id
    into v_admin_id
  from public.profiles p
  where p.id = p_actor_id
    and p.role = 'admin'
    and p.active = true
    and p.approved = true
    and (
      p.is_system_owner
      or p.subscription_end is null
      or p.subscription_end >= now()
    );

  if v_admin_id is null then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  select g.customer_id, g.amount
    into v_customer_id, v_amount
  from public.customer_general_payments g
  where g.id = p_general_payment_id
    and g.admin_id = v_admin_id
  for update;

  if v_customer_id is null then
    raise exception 'payment_not_found_or_forbidden' using errcode = '42501';
  end if;

  perform 1
  from public.profiles customer
  where customer.id = v_customer_id
    and customer.admin_id = v_admin_id
    and customer.role = 'customer'
  for update;

  if not found then
    raise exception 'customer_not_found_or_forbidden' using errcode = '42501';
  end if;

  delete from public.customer_general_payments
  where id = p_general_payment_id
    and admin_id = v_admin_id;

  v_remaining := public.get_customer_effective_balance(v_customer_id);

  return jsonb_build_object(
    'payment_deleted', true,
    'payment_scope', 'general',
    'payment_id', p_general_payment_id,
    'customer_id', v_customer_id,
    'deleted_amount', v_amount,
    'remaining', v_remaining
  );
end;
$function$;
revoke all on function private.get_customer_virtual_debt_balances(uuid)
  from public, anon;
grant execute on function private.get_customer_virtual_debt_balances(uuid)
  to authenticated, service_role;

revoke all on function public.get_customer_effective_balance(uuid)
  from public, anon;
grant execute on function public.get_customer_effective_balance(uuid)
  to authenticated, service_role;

revoke all on function private.customer_lifetime_paid_total(uuid)
  from public, anon;
grant execute on function private.customer_lifetime_paid_total(uuid)
  to authenticated, service_role;

revoke all on function public.record_customer_payment_service(
  uuid, uuid, numeric, text, text, uuid
) from public, anon, authenticated;
grant execute on function public.record_customer_payment_service(
  uuid, uuid, numeric, text, text, uuid
) to service_role;

revoke all on function public.record_payment_service(
  uuid, uuid, numeric, text, text, uuid
) from public, anon, authenticated;
grant execute on function public.record_payment_service(
  uuid, uuid, numeric, text, text, uuid
) to service_role;

revoke all on function public.delete_general_payment_service(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.delete_general_payment_service(uuid, uuid)
  to service_role;

-- Restore platform operations objects that exist in production but were absent
-- from the historical repository migration chain.
create table if not exists public.owner_platform_audit (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references public.profiles(id) on delete restrict,
  target_admin_id uuid references public.profiles(id) on delete set null,
  action text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.owner_platform_audit enable row level security;
revoke all on table public.owner_platform_audit from public, anon, authenticated;
grant all on table public.owner_platform_audit to service_role;

create table if not exists public.platform_operations_config (
  id smallint primary key default 1 check (id = 1),
  platform_status text not null default 'operational'
    check (platform_status in ('operational','degraded','partial_outage','maintenance')),
  maintenance_enabled boolean not null default false,
  maintenance_message text not null default ''
    check (char_length(maintenance_message) <= 1000),
  maintenance_starts_at timestamptz,
  maintenance_ends_at timestamptz,
  announcement_enabled boolean not null default false,
  announcement_title text not null default ''
    check (char_length(announcement_title) <= 160),
  announcement_message text not null default ''
    check (char_length(announcement_message) <= 1500),
  announcement_severity text not null default 'info'
    check (announcement_severity in ('info','success','warning','critical')),
  announcement_starts_at timestamptz,
  announcement_ends_at timestamptz,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null,
  check (
    maintenance_starts_at is null
    or maintenance_ends_at is null
    or maintenance_ends_at > maintenance_starts_at
  ),
  check (
    announcement_starts_at is null
    or announcement_ends_at is null
    or announcement_ends_at > announcement_starts_at
  )
);
alter table public.platform_operations_config enable row level security;
revoke all on table public.platform_operations_config from public, anon, authenticated;
grant all on table public.platform_operations_config to service_role;

insert into public.platform_operations_config(id)
values (1)
on conflict (id) do nothing;

CREATE OR REPLACE FUNCTION public.get_platform_operations_state()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_row public.platform_operations_config%rowtype;
  v_maintenance_effective boolean := false;
  v_announcement_effective boolean := false;
begin
  select *
    into v_row
  from public.platform_operations_config
  where id = 1;

  if not found then
    return jsonb_build_object(
      'platform_status', 'operational',
      'maintenance_enabled', false,
      'maintenance_effective', false,
      'maintenance_message', '',
      'maintenance_starts_at', null,
      'maintenance_ends_at', null,
      'announcement_enabled', false,
      'announcement_effective', false,
      'announcement_title', '',
      'announcement_message', '',
      'announcement_severity', 'info',
      'announcement_starts_at', null,
      'announcement_ends_at', null,
      'updated_at', null
    );
  end if;

  v_maintenance_effective :=
    v_row.maintenance_enabled
    and (v_row.maintenance_starts_at is null or v_row.maintenance_starts_at <= now())
    and (v_row.maintenance_ends_at is null or v_row.maintenance_ends_at > now());

  v_announcement_effective :=
    v_row.announcement_enabled
    and (v_row.announcement_starts_at is null or v_row.announcement_starts_at <= now())
    and (v_row.announcement_ends_at is null or v_row.announcement_ends_at > now());

  return jsonb_build_object(
    'platform_status', v_row.platform_status,
    'maintenance_enabled', v_row.maintenance_enabled,
    'maintenance_effective', v_maintenance_effective,
    'maintenance_message', v_row.maintenance_message,
    'maintenance_starts_at', v_row.maintenance_starts_at,
    'maintenance_ends_at', v_row.maintenance_ends_at,
    'announcement_enabled', v_row.announcement_enabled,
    'announcement_effective', v_announcement_effective,
    'announcement_title', v_row.announcement_title,
    'announcement_message', v_row.announcement_message,
    'announcement_severity', v_row.announcement_severity,
    'announcement_starts_at', v_row.announcement_starts_at,
    'announcement_ends_at', v_row.announcement_ends_at,
    'updated_at', v_row.updated_at
  );
end;
$function$;
CREATE OR REPLACE FUNCTION public.set_system_owner_operations_state(p_platform_status text, p_maintenance_enabled boolean, p_maintenance_message text DEFAULT ''::text, p_maintenance_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_maintenance_ends_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_announcement_enabled boolean DEFAULT false, p_announcement_title text DEFAULT ''::text, p_announcement_message text DEFAULT ''::text, p_announcement_severity text DEFAULT 'info'::text, p_announcement_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_announcement_ends_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not exists (
    select 1
    from public.profiles p
    where p.id = v_uid
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'system_owner_required' using errcode = '42501';
  end if;

  if p_platform_status not in ('operational','degraded','partial_outage','maintenance')
     or p_announcement_severity not in ('info','success','warning','critical')
     or char_length(coalesce(p_maintenance_message, '')) > 1000
     or char_length(coalesce(p_announcement_title, '')) > 160
     or char_length(coalesce(p_announcement_message, '')) > 1500
     or (
       p_maintenance_starts_at is not null
       and p_maintenance_ends_at is not null
       and p_maintenance_ends_at <= p_maintenance_starts_at
     )
     or (
       p_announcement_starts_at is not null
       and p_announcement_ends_at is not null
       and p_announcement_ends_at <= p_announcement_starts_at
     )
  then
    raise exception 'invalid_operations_state' using errcode = '22023';
  end if;

  if p_maintenance_enabled
     and trim(coalesce(p_maintenance_message, '')) = '' then
    raise exception 'maintenance_message_required' using errcode = '22023';
  end if;

  if p_announcement_enabled
     and (
       trim(coalesce(p_announcement_title, '')) = ''
       or trim(coalesce(p_announcement_message, '')) = ''
     )
  then
    raise exception 'announcement_content_required' using errcode = '22023';
  end if;

  insert into public.platform_operations_config (
    id,
    platform_status,
    maintenance_enabled,
    maintenance_message,
    maintenance_starts_at,
    maintenance_ends_at,
    announcement_enabled,
    announcement_title,
    announcement_message,
    announcement_severity,
    announcement_starts_at,
    announcement_ends_at,
    updated_at,
    updated_by
  ) values (
    1,
    p_platform_status,
    coalesce(p_maintenance_enabled, false),
    trim(coalesce(p_maintenance_message, '')),
    p_maintenance_starts_at,
    p_maintenance_ends_at,
    coalesce(p_announcement_enabled, false),
    trim(coalesce(p_announcement_title, '')),
    trim(coalesce(p_announcement_message, '')),
    p_announcement_severity,
    p_announcement_starts_at,
    p_announcement_ends_at,
    now(),
    v_uid
  )
  on conflict (id) do update
    set platform_status = excluded.platform_status,
        maintenance_enabled = excluded.maintenance_enabled,
        maintenance_message = excluded.maintenance_message,
        maintenance_starts_at = excluded.maintenance_starts_at,
        maintenance_ends_at = excluded.maintenance_ends_at,
        announcement_enabled = excluded.announcement_enabled,
        announcement_title = excluded.announcement_title,
        announcement_message = excluded.announcement_message,
        announcement_severity = excluded.announcement_severity,
        announcement_starts_at = excluded.announcement_starts_at,
        announcement_ends_at = excluded.announcement_ends_at,
        updated_at = now(),
        updated_by = v_uid;

  insert into public.owner_platform_audit (
    actor_id,
    target_admin_id,
    action,
    metadata
  ) values (
    v_uid,
    null,
    'platform_operations_changed',
    jsonb_build_object(
      'platform_status', p_platform_status,
      'maintenance_enabled', coalesce(p_maintenance_enabled, false),
      'maintenance_scheduled', p_maintenance_starts_at is not null or p_maintenance_ends_at is not null,
      'announcement_enabled', coalesce(p_announcement_enabled, false),
      'announcement_severity', p_announcement_severity,
      'announcement_scheduled', p_announcement_starts_at is not null or p_announcement_ends_at is not null
    )
  );

  return public.get_platform_operations_state();
end;
$function$;
revoke execute on function public.set_system_owner_operations_state(
  text, boolean, text, timestamptz, timestamptz,
  boolean, text, text, text, timestamptz, timestamptz
) from public, anon;
grant execute on function public.set_system_owner_operations_state(
  text, boolean, text, timestamptz, timestamptz,
  boolean, text, text, text, timestamptz, timestamptz
) to authenticated, service_role;

revoke execute on function public.get_platform_operations_state()
  from public, anon;
grant execute on function public.get_platform_operations_state()
  to authenticated, service_role;