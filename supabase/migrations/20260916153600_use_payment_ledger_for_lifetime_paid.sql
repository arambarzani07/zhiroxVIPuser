create or replace function private.customer_lifetime_paid_total(p_customer_id uuid)
returns numeric
language plpgsql
stable
security definer
set search_path to ''
as $function$
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

  select coalesce(sum(p.amount), 0)::numeric
    into v_total
  from public.payments p
  join public.debts d on d.id = p.debt_id
  where d.customer_id = p_customer_id;

  return coalesce(v_total, 0);
end;
$function$;
