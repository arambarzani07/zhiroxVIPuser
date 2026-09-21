-- Materialize the visible customer set once per dashboard request. The
-- previous implementation called get_daftar_official_customer_totals once
-- for every debt/payment row, which made the mobile dashboard take seconds
-- to render as the ledger grew.

create or replace function public.get_admin_dashboard_snapshot()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
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
    'total_remaining', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_balance_iqd')::numeric, 0)
      else coalesce((
        select sum(d.remaining)
        from public.debts d
        join visible_customer_ids visible on visible.id = d.customer_id
        where d.is_deleted = false
          and upper(coalesce(d.currency, 'IQD')) <> 'USD'
      ), 0)
    end,
    'total_payments', case
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
    end,
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
$$;

revoke all on function public.get_admin_dashboard_snapshot()
  from public, anon;
grant execute on function public.get_admin_dashboard_snapshot()
  to authenticated, service_role;

