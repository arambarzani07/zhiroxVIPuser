-- Direct, authenticated admin debt restore path.
-- Avoids Edge Function gateway/auth ambiguity while keeping tenant checks server-side.

create or replace function public.list_deleted_debts(p_limit integer default 200)
returns table(
  id uuid,
  customer_id uuid,
  customer_name text,
  description text,
  amount numeric,
  remaining numeric,
  status text,
  currency text,
  due_date date,
  custom_date timestamptz,
  created_at timestamptz,
  deleted_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_admin_id uuid;
  v_limit integer := greatest(1, least(coalesce(p_limit, 200), 500));
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select p.id
    into v_admin_id
  from public.profiles p
  where p.id = v_uid
    and p.role = 'admin'
    and p.active = true
    and p.approved = true
    and (p.subscription_end is null or p.subscription_end >= now());

  if v_admin_id is null then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  return query
  select
    d.id,
    d.customer_id,
    customer.name,
    d.description,
    d.amount,
    d.remaining,
    d.status,
    d.currency,
    d.due_date,
    d.custom_date,
    d.created_at,
    d.deleted_at
  from public.debts d
  join public.profiles customer on customer.id = d.customer_id
  where d.is_deleted = true
    and (case when customer.role = 'admin' then customer.id else customer.admin_id end) = v_admin_id
  order by d.deleted_at desc nulls last, d.id desc
  limit v_limit;
end;
$function$;

revoke all on function public.list_deleted_debts(integer) from public, anon;
grant execute on function public.list_deleted_debts(integer) to authenticated, service_role;

create or replace function public.restore_deleted_debt(p_debt_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  return public.restore_debt_service(v_uid, p_debt_id);
end;
$$;

revoke all on function public.restore_deleted_debt(uuid) from public, anon;
grant execute on function public.restore_deleted_debt(uuid) to authenticated, service_role;