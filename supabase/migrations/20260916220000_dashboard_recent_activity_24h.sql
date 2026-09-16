-- Dashboard recent activity keeps every debt/payment event from the last
-- rolling 24 hours, newest first. The payload is intentionally compact so
-- the snapshot remains lightweight even when activity is busy.
create or replace function public.get_admin_dashboard_snapshot()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if private."current_role"() is distinct from 'admin' then
    raise insufficient_privilege using message = 'admin role required';
  end if;

  select jsonb_build_object(
    'total_customers', (
      select count(*) from public.profiles p
      where p.role = 'customer' and p.approved = true
    ),
    'pending_requests', (
      select count(*) from public.profiles p
      where p.role = 'customer' and p.approved = false
    ),
    'total_debt', coalesce((
      select sum(d.amount) from public.debts d
      where d.is_deleted = false
        and upper(coalesce(d.currency, 'IQD')) <> 'USD'
    ), 0),
    'total_remaining', coalesce((
      select sum(d.remaining) from public.debts d
      where d.is_deleted = false
        and upper(coalesce(d.currency, 'IQD')) <> 'USD'
    ), 0),
    'total_payments', coalesce((
      select sum(pay.amount)
      from public.payments pay
      join public.debts d on d.id = pay.debt_id
      where d.is_deleted = false
        and upper(coalesce(d.currency, 'IQD')) <> 'USD'
    ), 0),
    'total_debt_usd', coalesce((
      select sum(d.amount) from public.debts d
      where d.is_deleted = false
        and upper(coalesce(d.currency, 'IQD')) = 'USD'
    ), 0),
    'total_remaining_usd', coalesce((
      select sum(d.remaining) from public.debts d
      where d.is_deleted = false
        and upper(coalesce(d.currency, 'IQD')) = 'USD'
    ), 0),
    'total_payments_usd', coalesce((
      select sum(pay.amount)
      from public.payments pay
      join public.debts d on d.id = pay.debt_id
      where d.is_deleted = false
        and upper(coalesce(d.currency, 'IQD')) = 'USD'
    ), 0),
    'pending_debts', (
      select count(*) from public.debts d
      where d.is_deleted = false and d.status <> 'paid'
    ),
    'recent_activity', coalesce((
      select jsonb_agg(
        recent_row.payload
        order by recent_row.created_at desc, recent_row.id desc
      )
      from (
        select
          d.created_at,
          d.id::text as id,
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
        join public.profiles customer on customer.id = d.customer_id
        left join public.profiles creator on creator.id = d.created_by
        where d.is_deleted = false
          and d.created_at >= now() - interval '24 hours'
          and d.created_at <= now()

        union all

        select
          pay.created_at,
          pay.id::text as id,
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
        join public.profiles customer on customer.id = d.customer_id
        left join public.profiles creator on creator.id = pay.created_by
        where d.is_deleted = false
          and pay.created_at >= now() - interval '24 hours'
          and pay.created_at <= now()
      ) recent_row
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_admin_dashboard_snapshot() from public, anon;
grant execute on function public.get_admin_dashboard_snapshot() to authenticated;
