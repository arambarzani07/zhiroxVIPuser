-- Fix Owner permission catalog RPC invoker chain.
-- The public SECURITY INVOKER wrapper must not call the private guard directly,
-- because authenticated intentionally has no EXECUTE privilege on that guard.
-- Permission enforcement lives inside the private SECURITY DEFINER implementation.

create or replace function private.get_system_owner_permission_catalog_internal()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_items jsonb;
begin
  if v_uid is null or not exists (
    select 1
    from public.profiles p
    where p.id = v_uid
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'system_owner_required' using errcode = '42501';
  end if;

  if not private.system_owner_has_permission(
    'owner_access_console', 'platform', null, v_uid
  ) then
    raise exception 'owner_permission_required:owner_access_console'
      using errcode = '42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'key', c.permission_key,
        'label', c.label,
        'group_key', c.group_key,
        'group_label', c.group_label,
        'risk_level', c.risk_level,
        'scopes', to_jsonb(c.scopes),
        'requires_reason', c.requires_reason,
        'requires_reauth', c.requires_reauth,
        'requires_typed_confirmation', c.requires_typed_confirmation,
        'requires_two_person_approval', c.requires_two_person_approval,
        'active', c.active,
        'allowed_platform', case
          when 'platform' = any(c.scopes)
          then private.system_owner_has_permission(c.permission_key, 'platform', null, v_uid)
          else false
        end
      )
      order by c.group_key, c.risk_level, c.permission_key
    ),
    '[]'::jsonb
  )
  into v_items
  from private.owner_permission_catalog c
  where c.active = true;

  return jsonb_build_object(
    'count', jsonb_array_length(v_items),
    'permissions', v_items
  );
end;
$$;

create or replace function public.get_system_owner_permission_catalog()
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
begin
  return private.get_system_owner_permission_catalog_internal();
end;
$$;

revoke all on function public.get_system_owner_permission_catalog() from public, anon;
grant execute on function public.get_system_owner_permission_catalog() to authenticated;
