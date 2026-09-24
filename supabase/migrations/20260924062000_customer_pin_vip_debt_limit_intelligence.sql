alter table public.profiles
  add column if not exists is_pinned boolean not null default false,
  add column if not exists pinned_at timestamptz,
  add column if not exists is_vip boolean not null default false;

create index if not exists profiles_customer_priority_idx
  on public.profiles (admin_id, is_pinned desc, pinned_at desc, created_at desc, id desc)
  where role = 'customer';

create or replace function public.get_pinned_customers(p_search text default '')
returns setof public.profiles
language sql
stable
security invoker
set search_path to ''
as $function$
  with s as (
    select
      (select private.current_admin_id()) as tenant_id,
      nullif(trim(coalesce(p_search, '')), '') as search_text
  )
  select p.*
  from public.profiles p
  cross join s
  where s.tenant_id is not null
    and (select private."current_role"()) in ('admin','employee')
    and p.admin_id = s.tenant_id
    and p.role = 'customer'
    and p.is_pinned is true
    and (
      s.search_text is null
      or lower(
        coalesce(p.name,'') || ' ' ||
        coalesce(p.father_name,'') || ' ' ||
        coalesce(p.grandfather_name,'') || ' ' ||
        coalesce(p.phone,'')
      ) like '%' || lower(s.search_text) || '%'
    )
  order by p.pinned_at desc nulls last, p.created_at desc, p.id desc
  limit 100;
$function$;

revoke all on function public.get_pinned_customers(text) from public, anon;
grant execute on function public.get_pinned_customers(text) to authenticated;

create or replace function public.get_customer_debt_limit_recommendation(
  p_customer_id uuid
)
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
  with target as (
    select p.id, p.debt_limit
    from public.profiles p
    where p.id = p_customer_id
      and p.role = 'customer'
      and p.admin_id = (select private.current_admin_id())
      and (select private."current_role"()) in ('admin','employee')
    limit 1
  ),
  debt_rows as (
    select
      d.amount::numeric as amount,
      d.remaining::numeric as remaining,
      d.due_date,
      coalesce(d.custom_date, d.created_at) as happened_at
    from public.debts d
    join target t on t.id = d.customer_id
    where d.is_deleted = false
  ),
  metrics as (
    select
      count(*)::int as debt_count,
      count(*) filter (where remaining <= 0)::int as settled_count,
      count(*) filter (
        where remaining > 0
          and due_date is not null
          and due_date < current_date
      )::int as overdue_open_count,
      coalesce(sum(amount),0)::numeric as total_debt,
      coalesce(sum(greatest(amount - remaining,0)),0)::numeric as total_paid,
      coalesce(sum(greatest(remaining,0)),0)::numeric as current_balance,
      coalesce(avg(amount),0)::numeric as average_debt,
      coalesce(max(amount),0)::numeric as max_debt,
      max(happened_at) as last_debt_at
    from debt_rows
  ),
  scored as (
    select
      t.debt_limit as current_limit,
      m.*,
      case
        when m.total_debt > 0
          then least(1.0, greatest(0.0, (m.total_paid / m.total_debt)::numeric))
        else 0::numeric
      end as payment_ratio
    from target t
    cross join metrics m
  ),
  calculated as (
    select
      s.*,
      case
        when s.debt_count >= 5 and s.payment_ratio >= 0.90 and s.overdue_open_count = 0 then 1.25
        when s.payment_ratio >= 0.75 and s.overdue_open_count <= 1 then 1.10
        when s.payment_ratio >= 0.50 then 0.90
        else 0.70
      end::numeric as reliability_multiplier,
      greatest(
        s.average_debt * 2.0,
        s.max_debt * 1.10,
        s.current_balance + (s.average_debt * 0.50)
      )::numeric as base_limit
    from scored s
  )
  select jsonb_build_object(
    'eligible', true,
    'suggested_limit',
      case
        when c.debt_count = 0 then greatest(c.current_limit, 0)
        else ceil(
          greatest(
            c.current_balance,
            c.base_limit * c.reliability_multiplier
          ) / 5000.0
        ) * 5000
      end,
    'current_limit', c.current_limit,
    'current_balance', c.current_balance,
    'debt_count', c.debt_count,
    'settled_count', c.settled_count,
    'overdue_open_count', c.overdue_open_count,
    'total_debt', c.total_debt,
    'total_paid', c.total_paid,
    'average_debt', c.average_debt,
    'max_debt', c.max_debt,
    'payment_ratio', c.payment_ratio,
    'confidence',
      case
        when c.debt_count >= 10 then 'high'
        when c.debt_count >= 4 then 'medium'
        else 'low'
      end,
    'last_debt_at', c.last_debt_at
  )
  from calculated c;
$function$;

revoke all on function public.get_customer_debt_limit_recommendation(uuid)
  from public, anon;
grant execute on function public.get_customer_debt_limit_recommendation(uuid)
  to authenticated;
