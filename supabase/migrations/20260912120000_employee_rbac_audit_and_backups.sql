-- Fine-grained employee permissions, visible audit history, and tenant backups.
-- All access is tenant-scoped and enforced at the database boundary.

create table if not exists public.employee_permissions (
  employee_id uuid primary key references public.profiles(id) on delete cascade,
  admin_id uuid not null references public.profiles(id) on delete cascade,
  can_view_customers boolean not null default true,
  can_add_customers boolean not null default false,
  can_edit_customers boolean not null default false,
  can_delete_customers boolean not null default false,
  can_view_debts boolean not null default true,
  can_add_debts boolean not null default false,
  can_edit_debts boolean not null default false,
  can_delete_debts boolean not null default false,
  can_record_payments boolean not null default false,
  can_view_financial_reports boolean not null default false,
  can_export_data boolean not null default false,
  can_send_notifications boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null,
  constraint employee_permissions_tenant_check check (employee_id <> admin_id)
);

create index if not exists employee_permissions_admin_idx
  on public.employee_permissions(admin_id);

alter table public.employee_permissions enable row level security;

drop policy if exists employee_permissions_admin_manage on public.employee_permissions;
create policy employee_permissions_admin_manage
  on public.employee_permissions
  for all to authenticated
  using (
    private."current_role"() = 'admin'
    and admin_id = private.current_admin_id()
  )
  with check (
    private."current_role"() = 'admin'
    and admin_id = private.current_admin_id()
    and updated_by = auth.uid()
    and exists (
      select 1 from public.profiles p
      where p.id = employee_id
        and p.role = 'employee'
        and p.admin_id = private.current_admin_id()
    )
  );

drop policy if exists employee_permissions_employee_read on public.employee_permissions;
create policy employee_permissions_employee_read
  on public.employee_permissions
  for select to authenticated
  using (employee_id = auth.uid() and admin_id = private.current_admin_id());

revoke all on table public.employee_permissions from anon;
grant select, insert, update, delete on table public.employee_permissions to authenticated;

create or replace function private.employee_has_permission(permission_name text)
returns boolean
language plpgsql stable security definer
set search_path = ''
as $$
declare
  allowed boolean := false;
begin
  if private."current_role"() = 'admin' then return true; end if;
  if private."current_role"() <> 'employee' then return false; end if;

  select case permission_name
    when 'view_customers' then ep.can_view_customers
    when 'add_customers' then ep.can_add_customers
    when 'edit_customers' then ep.can_edit_customers
    when 'delete_customers' then ep.can_delete_customers
    when 'view_debts' then ep.can_view_debts
    when 'add_debts' then ep.can_add_debts
    when 'edit_debts' then ep.can_edit_debts
    when 'delete_debts' then ep.can_delete_debts
    when 'record_payments' then ep.can_record_payments
    when 'view_financial_reports' then ep.can_view_financial_reports
    when 'export_data' then ep.can_export_data
    when 'send_notifications' then ep.can_send_notifications
    else false
  end into allowed
  from public.employee_permissions ep
  where ep.employee_id = auth.uid()
    and ep.admin_id = private.current_admin_id();

  return coalesce(allowed, false);
end;
$$;

revoke all on function private.employee_has_permission(text)
  from public, anon, authenticated;

create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  admin_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null check (action in ('insert','update','delete','restore','permission_change','backup','backup_restore')),
  entity_type text not null,
  entity_id text,
  before_data jsonb,
  after_data jsonb,
  changed_fields text[] not null default '{}',
  occurred_at timestamptz not null default now(),
  request_id uuid not null default gen_random_uuid()
);

create index if not exists audit_logs_admin_time_idx
  on public.audit_logs(admin_id, occurred_at desc);
create index if not exists audit_logs_actor_time_idx
  on public.audit_logs(actor_id, occurred_at desc);
create index if not exists audit_logs_entity_idx
  on public.audit_logs(admin_id, entity_type, entity_id);

alter table public.audit_logs enable row level security;

drop policy if exists audit_logs_admin_read on public.audit_logs;
create policy audit_logs_admin_read
  on public.audit_logs for select to authenticated
  using (
    private."current_role"() = 'admin'
    and admin_id = private.current_admin_id()
  );

revoke all on table public.audit_logs from anon, authenticated;
grant select on table public.audit_logs to authenticated;

create or replace function private.audit_tenant_row()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  old_row jsonb;
  new_row jsonb;
  tenant_id uuid;
  row_id text;
  changed text[];
begin
  old_row := case when tg_op = 'INSERT' then null else to_jsonb(old) end;
  new_row := case when tg_op = 'DELETE' then null else to_jsonb(new) end;

  tenant_id := coalesce(
    nullif(coalesce(new_row, old_row)->>'admin_id','')::uuid,
    case
      when tg_table_name = 'profiles' and coalesce(new_row, old_row)->>'role' = 'admin'
        then nullif(coalesce(new_row, old_row)->>'id','')::uuid
      when tg_table_name in ('debts','payments') then private.current_admin_id()
      else private.current_admin_id()
    end
  );

  if tenant_id is null then return coalesce(new, old); end if;
  row_id := coalesce(coalesce(new_row, old_row)->>'id',
                     coalesce(new_row, old_row)->>'employee_id');

  if tg_op = 'UPDATE' then
    select coalesce(array_agg(n.key order by n.key), '{}')
      into changed
    from jsonb_each(new_row) n
    join jsonb_each(old_row) o using (key)
    where n.value is distinct from o.value;
  else
    changed := '{}';
  end if;

  insert into public.audit_logs(
    admin_id, actor_id, action, entity_type, entity_id,
    before_data, after_data, changed_fields
  ) values (
    tenant_id, auth.uid(),
    case
      when tg_table_name = 'employee_permissions' then 'permission_change'
      else lower(tg_op)
    end,
    tg_table_name, row_id, old_row, new_row, changed
  );

  return coalesce(new, old);
end;
$$;

revoke all on function private.audit_tenant_row()
  from public, anon, authenticated;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'profiles','debts','payments','notifications','employee_permissions'
  ] loop
    if to_regclass('public.' || table_name) is not null then
      execute format('drop trigger if exists audit_%I_changes on public.%I', table_name, table_name);
      execute format(
        'create trigger audit_%I_changes after insert or update or delete on public.%I for each row execute function private.audit_tenant_row()',
        table_name, table_name
      );
    end if;
  end loop;
end;
$$;

create table if not exists public.tenant_backups (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  created_by uuid references public.profiles(id) on delete set null,
  label text not null default 'Automatic backup',
  backup_type text not null default 'manual'
    check (backup_type in ('manual','automatic','before_restore')),
  payload jsonb not null,
  record_counts jsonb not null default '{}',
  created_at timestamptz not null default now(),
  expires_at timestamptz
);

create index if not exists tenant_backups_admin_time_idx
  on public.tenant_backups(admin_id, created_at desc);

alter table public.tenant_backups enable row level security;

drop policy if exists tenant_backups_admin_read on public.tenant_backups;
create policy tenant_backups_admin_read
  on public.tenant_backups for select to authenticated
  using (
    private."current_role"() = 'admin'
    and admin_id = private.current_admin_id()
  );

revoke all on table public.tenant_backups from anon, authenticated;
grant select on table public.tenant_backups to authenticated;

create or replace function public.create_tenant_backup(
  p_label text default 'Manual backup',
  p_type text default 'manual'
)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  tenant_id uuid;
  backup_id uuid;
  snapshot jsonb;
  counts jsonb;
begin
  if private."current_role"() <> 'admin' then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if p_type not in ('manual','automatic','before_restore') then
    raise exception 'invalid_backup_type' using errcode = '22023';
  end if;

  tenant_id := private.current_admin_id();

  snapshot := jsonb_build_object(
    'version', 1,
    'created_at', now(),
    'profiles', coalesce((
      select jsonb_agg(to_jsonb(p) - 'password_hash')
      from public.profiles p
      where p.id = tenant_id or p.admin_id = tenant_id
    ), '[]'::jsonb),
    'debts', coalesce((
      select jsonb_agg(to_jsonb(d))
      from public.debts d
      where private.profile_tenant_id(d.customer_id) = tenant_id
    ), '[]'::jsonb),
    'payments', coalesce((
      select jsonb_agg(to_jsonb(pay))
      from public.payments pay
      where private.debt_tenant_id(pay.debt_id) = tenant_id
    ), '[]'::jsonb),
    'employee_permissions', coalesce((
      select jsonb_agg(to_jsonb(ep))
      from public.employee_permissions ep
      where ep.admin_id = tenant_id
    ), '[]'::jsonb)
  );

  counts := jsonb_build_object(
    'profiles', jsonb_array_length(snapshot->'profiles'),
    'debts', jsonb_array_length(snapshot->'debts'),
    'payments', jsonb_array_length(snapshot->'payments'),
    'employee_permissions', jsonb_array_length(snapshot->'employee_permissions')
  );

  insert into public.tenant_backups(
    admin_id, created_by, label, backup_type, payload, record_counts,
    expires_at
  ) values (
    tenant_id, auth.uid(), left(coalesce(nullif(trim(p_label),''),'Backup'),120),
    p_type, snapshot, counts,
    case when p_type = 'automatic' then now() + interval '90 days' else null end
  ) returning id into backup_id;

  insert into public.audit_logs(
    admin_id, actor_id, action, entity_type, entity_id, after_data
  ) values (
    tenant_id, auth.uid(), 'backup', 'tenant_backups', backup_id::text, counts
  );

  return backup_id;
end;
$$;

revoke all on function public.create_tenant_backup(text,text) from public, anon;
grant execute on function public.create_tenant_backup(text,text) to authenticated;

create or replace function public.get_tenant_export()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare tenant_id uuid;
begin
  if private."current_role"() <> 'admin'
     and not private.employee_has_permission('export_data') then
    raise exception 'export_permission_required' using errcode = '42501';
  end if;
  tenant_id := private.current_admin_id();
  return jsonb_build_object(
    'exported_at', now(),
    'profiles', coalesce((select jsonb_agg(to_jsonb(p) - 'password_hash')
      from public.profiles p where p.id = tenant_id or p.admin_id = tenant_id), '[]'::jsonb),
    'debts', coalesce((select jsonb_agg(to_jsonb(d)) from public.debts d
      where private.profile_tenant_id(d.customer_id) = tenant_id), '[]'::jsonb),
    'payments', coalesce((select jsonb_agg(to_jsonb(pay)) from public.payments pay
      where private.debt_tenant_id(pay.debt_id) = tenant_id), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_tenant_export() from public, anon;
grant execute on function public.get_tenant_export() to authenticated;

-- Keep at most 30 automatic backups per tenant and purge expired snapshots.
create or replace function public.cleanup_tenant_backups()
returns integer
language plpgsql security definer
set search_path = ''
as $$
declare removed integer;
begin
  delete from public.tenant_backups b
  where b.expires_at is not null and b.expires_at < now();

  delete from public.tenant_backups b
  using (
    select id, row_number() over(
      partition by admin_id order by created_at desc
    ) as rn
    from public.tenant_backups
    where backup_type = 'automatic'
  ) ranked
  where b.id = ranked.id and ranked.rn > 30;

  get diagnostics removed = row_count;
  return removed;
end;
$$;

revoke all on function public.cleanup_tenant_backups() from public, anon, authenticated;
grant execute on function public.cleanup_tenant_backups() to service_role;
