create or replace function private.customer_lifetime_paid_total(p_customer_id uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := private."current_role"();
  v_admin_id uuid := private.current_admin_id();
  v_total numeric;
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

  select coalesce(
           sum(greatest(coalesce(d.amount, 0) - coalesce(d.remaining, 0), 0)),
           0
         )::numeric
    into v_total
  from public.debts d
  where d.customer_id = p_customer_id;

  return coalesce(v_total, 0);
end;
$$;

revoke all on function private.customer_lifetime_paid_total(uuid) from public, anon;
grant execute on function private.customer_lifetime_paid_total(uuid) to authenticated, service_role;

create or replace function public.get_customer_finance_snapshot(p_customer_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with debt_rows as materialized (
    select d.*
    from public.debts d
    where d.customer_id = p_customer_id
      and d.is_deleted = false
  ),
  summary as (
    select
      coalesce(sum(d.remaining), 0)::numeric as total_remaining_iqd,
      count(*) filter (where d.remaining > 0)::bigint as open_debt_count
    from debt_rows d
  ),
  lifetime as (
    select private.customer_lifetime_paid_total(p_customer_id)::numeric as total_paid_iqd
  ),
  open_debts as (
    select coalesce(
      jsonb_agg(to_jsonb(d) order by coalesce(d.custom_date, d.created_at) desc, d.id desc),
      '[]'::jsonb
    ) as items
    from debt_rows d
    where d.remaining > 0
  )
  select jsonb_build_object(
    'total_debt_iqd', s.total_remaining_iqd + l.total_paid_iqd,
    'total_remaining_iqd', s.total_remaining_iqd,
    'total_paid_iqd', l.total_paid_iqd,
    'open_debt_count', s.open_debt_count,
    'open_debts', o.items,
    'complete', true
  )
  from summary s
  cross join lifetime l
  cross join open_debts o;
$$;

revoke all on function public.get_customer_finance_snapshot(uuid) from public, anon;
grant execute on function public.get_customer_finance_snapshot(uuid) to authenticated, service_role;
