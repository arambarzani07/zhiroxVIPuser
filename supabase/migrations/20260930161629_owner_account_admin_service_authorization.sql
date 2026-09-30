-- Service-only authorization bridge for account-admin Edge Function.
-- Whitelists only Owner actions that account-admin is allowed to perform.

create or replace function public.authorize_system_owner_account_admin_service(
  p_actor_id uuid,
  p_permission_key text,
  p_target_admin_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_scope_type text;
  v_scope_id uuid;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = p_actor_id
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'system_owner_required' using errcode = '42501';
  end if;

  case p_permission_key
    when 'owner_view_all_admins' then v_scope_type := 'platform'; v_scope_id := null;
    when 'owner_create_admin' then v_scope_type := 'admin'; v_scope_id := null;
    when 'owner_create_market' then v_scope_type := 'market'; v_scope_id := null;
    when 'owner_create_subscription' then v_scope_type := 'market'; v_scope_id := null;
    when 'owner_renew_subscription' then v_scope_type := 'market'; v_scope_id := p_target_admin_id;
    when 'owner_extend_subscription_days' then v_scope_type := 'market'; v_scope_id := p_target_admin_id;
    when 'owner_change_subscription_plan' then v_scope_type := 'market'; v_scope_id := p_target_admin_id;
    else raise exception 'account_admin_permission_not_allowed' using errcode = '42501';
  end case;

  if v_scope_type = 'market' and p_permission_key in (
    'owner_renew_subscription',
    'owner_extend_subscription_days',
    'owner_change_subscription_plan'
  ) then
    if p_target_admin_id is null or not exists (
      select 1 from public.profiles a
      where a.id = p_target_admin_id
        and a.role = 'admin'
        and a.is_system_owner = false
    ) then
      raise exception 'admin_not_found' using errcode = 'P0002';
    end if;
  end if;

  if not private.system_owner_has_permission(
    p_permission_key, v_scope_type, v_scope_id, p_actor_id
  ) then
    raise exception 'owner_permission_denied:%', p_permission_key using errcode = '42501';
  end if;

  return jsonb_build_object(
    'authorized', true,
    'permission_key', p_permission_key,
    'scope_type', v_scope_type,
    'scope_id', v_scope_id
  );
end;
$$;

revoke all on function public.authorize_system_owner_account_admin_service(uuid,text,uuid)
  from public, anon, authenticated;
grant execute on function public.authorize_system_owner_account_admin_service(uuid,text,uuid)
  to service_role;
