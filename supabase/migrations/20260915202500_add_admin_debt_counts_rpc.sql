create or replace function public.get_admin_debt_counts(p_admin_id uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_role text;
  v_current_admin uuid;
  v_result jsonb;
begin
  v_role := private."current_role"();
  v_current_admin := private.current_admin_id();

  if v_role is distinct from 'system_owner'
     and v_current_admin is distinct from p_admin_id then
    raise insufficient_privilege using message = 'cross_tenant_forbidden';
  end if;

  select jsonb_build_object(
    'pending', count(*) filter (where d.status = 'pending'),
    'partial', count(*) filter (where d.status = 'partial'),
    'paid', count(*) filter (where d.status = 'paid')
  )
  into v_result
  from public.debts d
  join public.profiles p on p.id = d.customer_id
  where p.admin_id = p_admin_id
    and d.is_deleted = false;

  return coalesce(
    v_result,
    jsonb_build_object('pending', 0, 'partial', 0, 'paid', 0)
  );
end;
$function$;

revoke all on function public.get_admin_debt_counts(uuid) from public, anon;
grant execute on function public.get_admin_debt_counts(uuid) to authenticated;
