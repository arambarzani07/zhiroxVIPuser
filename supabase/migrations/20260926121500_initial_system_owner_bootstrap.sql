-- One-time first owner bootstrap for a fresh ZHIROX database.
-- The claim requires an authenticated Supabase user and closes permanently
-- once a system owner exists.

create or replace function public.claim_initial_system_owner(
  p_name text,
  p_phone text
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
begin
  if v_uid is null then
    raise exception 'authentication_required';
  end if;

  if exists (select 1 from public.profiles where is_system_owner = true) then
    raise exception 'bootstrap_closed';
  end if;

  if exists (select 1 from public.profiles) then
    raise exception 'bootstrap_requires_empty_profiles';
  end if;

  if length(trim(coalesce(p_name, ''))) < 2 then
    raise exception 'invalid_name';
  end if;

  if trim(coalesce(p_phone, '')) !~ '^[0-9]{8,15}$' then
    raise exception 'invalid_phone';
  end if;

  insert into public.profiles (
    id, name, phone, role, market_name, admin_id, created_by,
    approved, active, is_system_owner,
    can_add_customers, can_set_debt_limit, can_set_due_date,
    can_edit_debts, can_send_notifications,
    can_view_customers, can_edit_customers, can_delete_customers,
    can_view_debts, can_add_debts, can_delete_debts,
    can_record_payments, can_view_financial_reports,
    can_export_data, can_import_data
  ) values (
    v_uid, trim(p_name), trim(p_phone), 'admin', '', null, null,
    true, true, true,
    true, true, true,
    true, true,
    true, true, true,
    true, true, true,
    true, true,
    true, true
  )
  returning * into v_profile;

  return v_profile;
end;
$function$;

create or replace function public.initial_owner_bootstrap_open()
returns boolean
language sql
security invoker
stable
set search_path = ''
as $function$
  select not exists (
    select 1 from public.profiles where is_system_owner = true
  );
$function$;

revoke all on function public.claim_initial_system_owner(text,text) from public, anon;
grant execute on function public.claim_initial_system_owner(text,text) to authenticated;
grant execute on function public.claim_initial_system_owner(text,text) to service_role;

revoke all on function public.initial_owner_bootstrap_open() from public;
grant execute on function public.initial_owner_bootstrap_open() to anon;
grant execute on function public.initial_owner_bootstrap_open() to authenticated;
grant execute on function public.initial_owner_bootstrap_open() to service_role;
