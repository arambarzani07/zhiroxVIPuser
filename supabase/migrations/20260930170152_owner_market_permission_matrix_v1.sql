create or replace function private.get_system_owner_market_permission_matrix_internal(
  p_admin_id uuid,
  p_owner_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := coalesce(p_owner_id, auth.uid());
  v_market record;
  v_items jsonb;
begin
  if v_owner_id is null or not exists (
    select 1 from public.profiles p
    where p.id = v_owner_id
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'system_owner_required' using errcode = '42501';
  end if;

  if not private.system_owner_has_permission('owner_access_console', 'platform', null, v_owner_id) then
    raise exception 'owner_permission_required:owner_access_console' using errcode = '42501';
  end if;

  select p.id, p.market_name, p.name, p.phone, p.active, p.approved
    into v_market
  from public.profiles p
  where p.id = p_admin_id
    and p.role = 'admin'
    and p.is_system_owner = false;

  if not found then
    raise exception 'admin_not_found' using errcode = 'P0002';
  end if;

  select coalesce(jsonb_agg(item order by item->>'group_key', (item->>'risk_level')::int, item->>'key'), '[]'::jsonb)
    into v_items
  from (
    select jsonb_build_object(
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
      'applicable', case when 'market' = any(c.scopes) or 'admin' = any(c.scopes) then true else false end,
      'scope_type', case
        when 'market' = any(c.scopes) then 'market'
        when 'admin' = any(c.scopes) then 'admin'
        else null
      end,
      'mode', case
        when not ('market' = any(c.scopes) or 'admin' = any(c.scopes)) then 'platform_only'
        when g.id is null then 'inherit'
        when g.allowed then 'allow'
        else 'deny'
      end,
      'effective_allowed', case
        when 'market' = any(c.scopes) then private.system_owner_has_permission(c.permission_key, 'market', p_admin_id, v_owner_id)
        when 'admin' = any(c.scopes) then private.system_owner_has_permission(c.permission_key, 'admin', p_admin_id, v_owner_id)
        else private.system_owner_has_permission(c.permission_key, 'platform', null, v_owner_id)
      end
    ) as item
    from private.owner_permission_catalog c
    left join private.owner_permission_grants g
      on g.owner_id = v_owner_id
     and g.permission_key = c.permission_key
     and g.scope_type = case
       when 'market' = any(c.scopes) then 'market'
       when 'admin' = any(c.scopes) then 'admin'
       else '__none__'
     end
     and g.scope_id = p_admin_id
     and (g.expires_at is null or g.expires_at > now())
    where c.active = true
  ) s;

  return jsonb_build_object(
    'market', jsonb_build_object(
      'id', v_market.id,
      'market_name', coalesce(v_market.market_name, ''),
      'admin_name', coalesce(v_market.name, ''),
      'phone', coalesce(v_market.phone, ''),
      'active', v_market.active,
      'approved', v_market.approved
    ),
    'count', jsonb_array_length(v_items),
    'editable_count', (
      select count(*) from private.owner_permission_catalog c
      where c.active = true and ('market' = any(c.scopes) or 'admin' = any(c.scopes))
    ),
    'permissions', v_items
  );
end;
$$;

create or replace function public.get_system_owner_market_permission_matrix(p_admin_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select private.get_system_owner_market_permission_matrix_internal(p_admin_id, auth.uid());
$$;

create or replace function public.set_system_owner_market_permission_matrix(
  p_admin_id uuid,
  p_changes jsonb,
  p_reason text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := auth.uid();
  v_change jsonb;
  v_key text;
  v_mode text;
  v_scope_type text;
  v_risk smallint;
  v_requires_reason boolean;
  v_changed int := 0;
  v_audit_changes jsonb := '[]'::jsonb;
begin
  if v_owner_id is null or not exists (
    select 1 from public.profiles p
    where p.id = v_owner_id
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'system_owner_required' using errcode = '42501';
  end if;

  if not private.system_owner_has_permission('owner_access_console', 'platform', null, v_owner_id) then
    raise exception 'owner_permission_required:owner_access_console' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = p_admin_id and p.role = 'admin' and p.is_system_owner = false
  ) then
    raise exception 'admin_not_found' using errcode = 'P0002';
  end if;

  if jsonb_typeof(p_changes) <> 'array' then
    raise exception 'invalid_permission_changes' using errcode = '22023';
  end if;

  if jsonb_array_length(p_changes) > 200 then
    raise exception 'too_many_permission_changes' using errcode = '22023';
  end if;

  for v_change in select value from jsonb_array_elements(p_changes)
  loop
    v_key := nullif(trim(v_change->>'key'), '');
    v_mode := lower(nullif(trim(v_change->>'mode'), ''));
    if v_key is null or v_mode not in ('inherit','allow','deny') then
      raise exception 'invalid_permission_change' using errcode = '22023';
    end if;

    select case
             when 'market' = any(c.scopes) then 'market'
             when 'admin' = any(c.scopes) then 'admin'
             else null
           end,
           c.risk_level,
           c.requires_reason
      into v_scope_type, v_risk, v_requires_reason
    from private.owner_permission_catalog c
    where c.permission_key = v_key and c.active = true;

    if not found then
      raise exception 'unknown_owner_permission:%', v_key using errcode = '22023';
    end if;
    if v_scope_type is null then
      raise exception 'platform_only_owner_permission:%', v_key using errcode = '22023';
    end if;
    if (v_requires_reason or v_risk >= 3) and length(trim(coalesce(p_reason,''))) < 4 then
      raise exception 'permission_change_reason_required:%', v_key using errcode = '22023';
    end if;

    delete from private.owner_permission_grants g
    where g.owner_id = v_owner_id
      and g.permission_key = v_key
      and g.scope_type = v_scope_type
      and g.scope_id = p_admin_id;

    if v_mode <> 'inherit' then
      insert into private.owner_permission_grants(
        owner_id, permission_key, scope_type, scope_id, allowed,
        expires_at, reason, granted_by, created_at, updated_at
      ) values (
        v_owner_id, v_key, v_scope_type, p_admin_id, v_mode = 'allow',
        null, trim(coalesce(p_reason,'')), v_owner_id, now(), now()
      );
    end if;

    v_changed := v_changed + 1;
    v_audit_changes := v_audit_changes || jsonb_build_array(jsonb_build_object(
      'key', v_key,
      'mode', v_mode,
      'scope_type', v_scope_type,
      'risk_level', v_risk
    ));
  end loop;

  if v_changed > 0 then
    insert into public.owner_platform_audit(actor_id, target_admin_id, action, metadata)
    values (
      v_owner_id,
      p_admin_id,
      'market_permission_matrix_updated',
      jsonb_build_object(
        'change_count', v_changed,
        'reason', trim(coalesce(p_reason,'')),
        'changes', v_audit_changes
      )
    );
  end if;

  return private.get_system_owner_market_permission_matrix_internal(p_admin_id, v_owner_id);
end;
$$;

revoke all on function public.get_system_owner_market_permission_matrix(uuid) from public, anon;
revoke all on function public.set_system_owner_market_permission_matrix(uuid,jsonb,text) from public, anon;
grant execute on function public.get_system_owner_market_permission_matrix(uuid) to authenticated;
grant execute on function public.set_system_owner_market_permission_matrix(uuid,jsonb,text) to authenticated;
