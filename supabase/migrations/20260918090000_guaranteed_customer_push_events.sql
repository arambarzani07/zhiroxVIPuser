-- Guarantee automatic Web Push for every live debt/payment transaction.
-- Manual notifications remain handled by enqueue_manual_customer_push_service.
-- Push side effects are best-effort: notification failures must never roll back
-- a successfully committed financial transaction.

create or replace function private.enqueue_customer_push_debt_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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

  -- Historical imports/live sync are intentionally excluded from automatic
  -- customer pushes; those rows are not newly-created market transactions.
  if coalesce(new.reference_snapshot ->> 'source', '') in ('legacy_import', 'daftar_live_sync') then
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
   and (tenant.is_system_owner or tenant.subscription_end is null or tenant.subscription_end >= now())
  where customer.id = new.customer_id
    and customer.role = 'customer'
    and customer.active = true
    and customer.approved = true;

  if v_market_id is null then
    return new;
  end if;

  select coalesce(sum(d.remaining), 0)::numeric
    into v_remaining_iqd
  from public.debts d
  where d.customer_id = new.customer_id
    and d.is_deleted = false
    and d.remaining > 0;

  if upper(coalesce(new.currency, 'IQD')) = 'USD' and coalesce(new.dollar_rate, 0) > 0 then
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
    raise warning 'customer debt push enqueue deferred for %: %', new.id, sqlerrm;
  end;

  return new;
end;
$$;

drop trigger if exists trg_customer_push_debt_insert on public.debts;
create trigger trg_customer_push_debt_insert
after insert on public.debts
for each row
execute function private.enqueue_customer_push_debt_after_insert();


create or replace function private.enqueue_customer_push_payment_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer_id uuid;
  v_market_id uuid;
  v_market_name text := '';
  v_currency text := 'IQD';
  v_dollar_rate numeric := 0;
  v_remaining_iqd numeric := 0;
  v_amount numeric := 0;
begin
  -- Normal payment RPCs set this before inserting and enqueue once at the end.
  -- Import/sync RPCs also set it so historical allocations never spam customers.
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
   and (tenant.is_system_owner or tenant.subscription_end is null or tenant.subscription_end >= now())
  where d.id = new.debt_id
    and d.is_deleted = false;

  if v_customer_id is null or v_market_id is null then
    return new;
  end if;

  select coalesce(sum(d.remaining), 0)::numeric
    into v_remaining_iqd
  from public.debts d
  where d.customer_id = v_customer_id
    and d.is_deleted = false
    and d.remaining > 0;

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
        'occurred_at', coalesce(new.created_at, now())
      )
    );
  exception when others then
    raise warning 'customer payment push enqueue deferred for %: %', new.id, sqlerrm;
  end;

  return new;
end;
$$;

drop trigger if exists trg_customer_push_payment_insert on public.payments;
create constraint trigger trg_customer_push_payment_insert
after insert on public.payments
deferrable initially deferred
for each row
execute function private.enqueue_customer_push_payment_after_insert();


create or replace function public.record_payment_service(
  p_actor_id uuid,
  p_debt_id uuid,
  p_amount numeric,
  p_note text default '',
  p_reference_kind text default null,
  p_reference_id uuid default null
)
returns public.payments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_admin_id uuid;
  v_debt public.debts%rowtype;
  v_payment public.payments%rowtype;
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
         case when p.role = 'admin' then p.id else p.admin_id end
    into v_role, v_admin_id
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

  if v_role is null or v_admin_id is null then
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
    and (case when customer.role = 'admin' then customer.id else customer.admin_id end) = v_admin_id
  for update of d;

  if not found then
    raise exception 'debt_not_found_or_forbidden' using errcode = '42501';
  end if;
  if v_debt.remaining <= 0 then
    raise exception 'debt_already_paid' using errcode = '22023';
  end if;

  -- Suppress the generic deferred trigger; this RPC enqueues once after the
  -- debt balance has been updated so the notification contains the final balance.
  perform set_config('zhirox.payment_rpc', 'on', true);

  v_new_remaining := greatest(v_debt.remaining - p_amount, 0);
  insert into public.payments (
    debt_id, amount, note, created_by, reference_kind, reference_id
  ) values (
    p_debt_id, least(p_amount, v_debt.remaining), coalesce(p_note, ''),
    p_actor_id, p_reference_kind, p_reference_id
  )
  returning * into v_payment;

  update public.debts
  set remaining = v_new_remaining,
      status = case when v_new_remaining <= 0 then 'paid' else 'partial' end,
      updated_at = now()
  where id = p_debt_id;

  select coalesce(sum(d.remaining), 0)::numeric
    into v_total_remaining
  from public.debts d
  where d.customer_id = v_debt.customer_id
    and d.is_deleted = false
    and d.remaining > 0;

  select coalesce(p.market_name, '')
    into v_market_name
  from public.profiles p
  where p.id = v_admin_id;

  if upper(coalesce(v_debt.currency, 'IQD')) = 'USD' and coalesce(v_debt.dollar_rate, 0) > 0 then
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
        'occurred_at', coalesce(v_payment.created_at, now())
      )
    );
  exception when others then
    raise warning 'customer payment push enqueue deferred for %: %', v_payment.id, sqlerrm;
  end;

  return v_payment;
end;
$$;


create or replace function public.record_customer_payment_service(
  p_actor_id uuid,
  p_customer_id uuid,
  p_amount numeric,
  p_note text default '',
  p_reference_kind text default null,
  p_reference_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_admin_id uuid;
  v_customer_admin_id uuid;
  v_left numeric := p_amount;
  v_piece numeric;
  v_total_remaining numeric := 0;
  v_allocation_count integer := 0;
  v_debt public.debts%rowtype;
  v_payment public.payments%rowtype;
  v_first_payment_id uuid;
  v_first_payment_created_at timestamptz;
  v_market_name text := '';
  v_payments jsonb := '[]'::jsonb;
begin
  if p_actor_id is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select p.role,
         case when p.role = 'admin' then p.id else p.admin_id end
    into v_role, v_admin_id
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

  if v_role is null or v_admin_id is null then
    raise exception 'payment_forbidden' using errcode = '42501';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_payment_amount' using errcode = '22023';
  end if;

  select case when customer.role = 'admin' then customer.id else customer.admin_id end
    into v_customer_admin_id
  from public.profiles customer
  where customer.id = p_customer_id
    and customer.role = 'customer';

  if v_customer_admin_id is null or v_customer_admin_id <> v_admin_id then
    raise exception 'customer_not_found_or_forbidden' using errcode = '42501';
  end if;

  perform set_config('zhirox.payment_rpc', 'on', true);

  for v_debt in
    select d.*
    from public.debts d
    where d.customer_id = p_customer_id
      and d.is_deleted = false
      and d.remaining > 0
    order by coalesce(d.custom_date, d.created_at) asc,
             d.created_at asc,
             d.id asc
    for update
  loop
    exit when v_left <= 0;

    v_piece := least(v_left, v_debt.remaining);

    insert into public.payments (
      debt_id,
      amount,
      note,
      created_by,
      reference_kind,
      reference_id
    ) values (
      v_debt.id,
      v_piece,
      coalesce(p_note, ''),
      p_actor_id,
      p_reference_kind,
      p_reference_id
    )
    returning * into v_payment;

    if v_first_payment_id is null then
      v_first_payment_id := v_payment.id;
      v_first_payment_created_at := v_payment.created_at;
    end if;

    update public.debts
    set remaining = greatest(v_debt.remaining - v_piece, 0),
        status = case
          when greatest(v_debt.remaining - v_piece, 0) <= 0 then 'paid'
          else 'partial'
        end,
        updated_at = now()
    where id = v_debt.id;

    v_payments := v_payments || jsonb_build_array(to_jsonb(v_payment));
    v_allocation_count := v_allocation_count + 1;
    v_left := v_left - v_piece;
  end loop;

  if v_left > 0 then
    raise exception 'payment_exceeds_customer_balance' using errcode = '22023';
  end if;

  select coalesce(sum(d.remaining), 0)::numeric
    into v_total_remaining
  from public.debts d
  where d.customer_id = p_customer_id
    and d.is_deleted = false
    and d.remaining > 0;

  select coalesce(p.market_name, '')
    into v_market_name
  from public.profiles p
  where p.id = v_admin_id;

  if v_first_payment_id is not null then
    begin
      perform public.enqueue_customer_push_event_service(
        v_admin_id,
        p_customer_id,
        'payment_created',
        v_first_payment_id,
        'payment_created:' || v_first_payment_id::text,
        jsonb_build_object(
          'amount', p_amount,
          'currency', 'IQD',
          'remaining_iqd', v_total_remaining,
          'market_name', v_market_name,
          'occurred_at', coalesce(v_first_payment_created_at, now())
        )
      );
    exception when others then
      raise warning 'customer-wide payment push enqueue deferred for %: %', v_first_payment_id, sqlerrm;
    end;
  end if;

  return jsonb_build_object(
    'customer_id', p_customer_id,
    'amount', p_amount,
    'allocation_count', v_allocation_count,
    'remaining', v_total_remaining,
    'payments', v_payments
  );
end;
$$;


create or replace function public.legacy_import_apply_payment(
  p_admin_id uuid,
  p_debt_id uuid,
  p_payment_id uuid,
  p_amount numeric,
  p_note text,
  p_created_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_debt public.debts%rowtype;
  v_customer_admin uuid;
  v_new_remaining numeric;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_payment_amount';
  end if;

  select d.*
    into v_debt
  from public.debts d
  where d.id = p_debt_id
    and coalesce(d.is_deleted, false) = false
  for update;

  if not found then
    raise exception 'debt_not_found';
  end if;

  select p.admin_id
    into v_customer_admin
  from public.profiles p
  where p.id = v_debt.customer_id;

  if v_customer_admin is distinct from p_admin_id then
    raise exception 'cross_tenant_forbidden';
  end if;

  if exists(select 1 from public.payments where id = p_payment_id) then
    return;
  end if;
  if p_amount > v_debt.remaining then
    raise exception 'payment_exceeds_remaining';
  end if;

  -- Historical import/sync allocations must not generate customer push.
  perform set_config('zhirox.payment_rpc', 'on', true);

  insert into public.payments(id, debt_id, amount, note, created_by, created_at)
  values (p_payment_id, p_debt_id, p_amount, coalesce(p_note, ''), p_admin_id, p_created_at);

  v_new_remaining := v_debt.remaining - p_amount;

  update public.debts
  set remaining = v_new_remaining,
      status = case when v_new_remaining = 0 then 'paid' else 'partial' end,
      updated_at = greatest(coalesce(updated_at, p_created_at), p_created_at)
  where id = p_debt_id;
end;
$$;

revoke all on function public.record_payment_service(uuid,uuid,numeric,text,text,uuid)
  from public, anon, authenticated;
grant execute on function public.record_payment_service(uuid,uuid,numeric,text,text,uuid)
  to service_role;

revoke all on function public.record_customer_payment_service(uuid,uuid,numeric,text,text,uuid)
  from public, anon, authenticated;
grant execute on function public.record_customer_payment_service(uuid,uuid,numeric,text,text,uuid)
  to service_role;

revoke all on function public.legacy_import_apply_payment(uuid,uuid,uuid,numeric,text,timestamptz)
  from public, anon, authenticated;
grant execute on function public.legacy_import_apply_payment(uuid,uuid,uuid,numeric,text,timestamptz)
  to service_role;
