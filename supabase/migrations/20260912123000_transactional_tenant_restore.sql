-- Transactional tenant restore. Restores business records only; authentication
-- identities and owner authority fields are intentionally never restored.
create or replace function private.restore_backup_row(
  p_table regclass,
  p_row jsonb,
  p_excluded_columns text[] default '{}'
)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  cols text;
  updates text;
  table_name text;
begin
  table_name := p_table::text;
  select string_agg(format('%I', a.attname), ', ' order by a.attnum),
         string_agg(format('%1$I = excluded.%1$I', a.attname), ', ' order by a.attnum)
           filter (where a.attname <> 'id')
    into cols, updates
  from pg_catalog.pg_attribute a
  where a.attrelid = p_table
    and a.attnum > 0
    and not a.attisdropped
    and a.attgenerated = ''
    and not (a.attname = any(p_excluded_columns));

  execute format(
    'insert into %s (%s) select %s from jsonb_populate_record(null::%s, $1) r on conflict (id) do update set %s',
    table_name, cols, cols, table_name, updates
  ) using p_row;
end;
$$;

revoke all on function private.restore_backup_row(regclass,jsonb,text[])
  from public, anon, authenticated;

create or replace function public.restore_tenant_backup(p_backup_id uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  tenant_id uuid;
  snapshot jsonb;
  item jsonb;
  restored_debts integer := 0;
  restored_payments integer := 0;
  restored_permissions integer := 0;
  safety_backup uuid;
begin
  if private."current_role"() <> 'admin' then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  tenant_id := private.current_admin_id();

  select b.payload into snapshot
  from public.tenant_backups b
  where b.id = p_backup_id and b.admin_id = tenant_id
  for share;
  if snapshot is null then
    raise exception 'backup_not_found' using errcode = 'P0002';
  end if;
  if coalesce((snapshot->>'version')::integer, 0) <> 1 then
    raise exception 'unsupported_backup_version' using errcode = '22023';
  end if;

  safety_backup := public.create_tenant_backup(
    'Automatic safety backup before restore', 'before_restore'
  );

  for item in select value from jsonb_array_elements(coalesce(snapshot->'debts','[]'::jsonb))
  loop
    if private.profile_tenant_id(nullif(item->>'customer_id','')::uuid) <> tenant_id then
      raise exception 'cross_tenant_debt_in_backup' using errcode = '42501';
    end if;
    perform private.restore_backup_row('public.debts'::regclass, item);
    restored_debts := restored_debts + 1;
  end loop;

  for item in select value from jsonb_array_elements(coalesce(snapshot->'payments','[]'::jsonb))
  loop
    if private.debt_tenant_id(nullif(item->>'debt_id','')::uuid) <> tenant_id then
      raise exception 'cross_tenant_payment_in_backup' using errcode = '42501';
    end if;
    perform private.restore_backup_row('public.payments'::regclass, item);
    restored_payments := restored_payments + 1;
  end loop;

  for item in select value from jsonb_array_elements(coalesce(snapshot->'employee_permissions','[]'::jsonb))
  loop
    if nullif(item->>'admin_id','')::uuid <> tenant_id then
      raise exception 'cross_tenant_permission_in_backup' using errcode = '42501';
    end if;
    perform private.restore_backup_row(
      'public.employee_permissions'::regclass,
      item || jsonb_build_object('updated_by', auth.uid(), 'updated_at', now())
    );
    restored_permissions := restored_permissions + 1;
  end loop;

  insert into public.audit_logs(
    admin_id, actor_id, action, entity_type, entity_id, after_data
  ) values (
    tenant_id, auth.uid(), 'backup_restore', 'tenant_backups',
    p_backup_id::text,
    jsonb_build_object(
      'safety_backup_id', safety_backup,
      'debts', restored_debts,
      'payments', restored_payments,
      'permissions', restored_permissions
    )
  );

  return jsonb_build_object(
    'success', true,
    'safety_backup_id', safety_backup,
    'debts', restored_debts,
    'payments', restored_payments,
    'permissions', restored_permissions
  );
end;
$$;

revoke all on function public.restore_tenant_backup(uuid) from public, anon;
grant execute on function public.restore_tenant_backup(uuid) to authenticated;
