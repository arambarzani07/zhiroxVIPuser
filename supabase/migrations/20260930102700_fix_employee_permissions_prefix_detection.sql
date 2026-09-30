create or replace function private.employee_has_permission(permission_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  permission_key text;
  allowed boolean := false;
begin
  if private.current_role() = 'admin' then return true; end if;
  if private.current_role() <> 'employee' then return false; end if;

  permission_key := case
    when left(permission_name, 4) = 'can_' then permission_name
    else 'can_' || permission_name
  end;

  if permission_key !~ '^can_[a-z0-9_]+$' then return false; end if;

  select coalesce((to_jsonb(ep)->>permission_key)::boolean, false)
    into allowed
  from public.employee_permissions ep
  where ep.employee_id = auth.uid()
    and ep.admin_id = private.current_admin_id();

  return coalesce(allowed, false);
exception
  when invalid_text_representation then
    return false;
end;
$function$;
