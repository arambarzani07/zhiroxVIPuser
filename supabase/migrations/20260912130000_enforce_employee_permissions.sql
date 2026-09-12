-- Enforce the governance-center permissions in both legacy UI fields and RLS.
alter table public.profiles
  add column if not exists can_view_customers boolean not null default true,
  add column if not exists can_edit_customers boolean not null default false,
  add column if not exists can_delete_customers boolean not null default false,
  add column if not exists can_view_debts boolean not null default true,
  add column if not exists can_add_debts boolean not null default false,
  add column if not exists can_delete_debts boolean not null default false,
  add column if not exists can_record_payments boolean not null default false,
  add column if not exists can_view_financial_reports boolean not null default false,
  add column if not exists can_export_data boolean not null default false;

insert into public.employee_permissions(
  employee_id, admin_id,
  can_view_customers, can_add_customers, can_edit_customers,
  can_delete_customers, can_view_debts, can_add_debts,
  can_edit_debts, can_delete_debts, can_record_payments,
  can_view_financial_reports, can_export_data, can_send_notifications,
  updated_by
)
select
  p.id, p.admin_id,
  coalesce(p.can_view_customers, true),
  coalesce(p.can_add_customers, false),
  coalesce(p.can_edit_customers, false),
  coalesce(p.can_delete_customers, false),
  coalesce(p.can_view_debts, true),
  coalesce(p.can_add_debts, false),
  coalesce(p.can_edit_debts, false),
  coalesce(p.can_delete_debts, false),
  coalesce(p.can_record_payments, false),
  coalesce(p.can_view_financial_reports, false),
  coalesce(p.can_export_data, false),
  coalesce(p.can_send_notifications, false),
  p.admin_id
from public.profiles p
where p.role = 'employee' and p.admin_id is not null
on conflict (employee_id) do nothing;

create or replace function private.sync_employee_permissions_to_profile()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  update public.profiles
  set can_view_customers = new.can_view_customers,
      can_add_customers = new.can_add_customers,
      can_edit_customers = new.can_edit_customers,
      can_delete_customers = new.can_delete_customers,
      can_view_debts = new.can_view_debts,
      can_add_debts = new.can_add_debts,
      can_edit_debts = new.can_edit_debts,
      can_delete_debts = new.can_delete_debts,
      can_record_payments = new.can_record_payments,
      can_view_financial_reports = new.can_view_financial_reports,
      can_export_data = new.can_export_data,
      can_send_notifications = new.can_send_notifications,
      updated_at = now()
  where id = new.employee_id
    and role = 'employee'
    and admin_id = new.admin_id;
  return new;
end;
$$;

-- Remove remaining advisor findings without broadening any tenant boundary.
create index if not exists app_update_settings_updated_by_idx
  on public.app_update_settings(updated_by);
create index if not exists employee_permissions_updated_by_idx
  on public.employee_permissions(updated_by);
create index if not exists receipt_documents_created_by_idx
  on public.receipt_documents(created_by);
create index if not exists tenant_backups_created_by_idx
  on public.tenant_backups(created_by);

-- One SELECT policy avoids evaluating two permissive policies for each row;
-- write policies remain admin-only and keep USING/WITH CHECK separate.
drop policy if exists employee_permissions_admin_manage on public.employee_permissions;
drop policy if exists employee_permissions_employee_read on public.employee_permissions;
drop policy if exists employee_permissions_select_authorized on public.employee_permissions;
create policy employee_permissions_select_authorized
  on public.employee_permissions for select to authenticated
  using (
    (
      (select private."current_role"()) = 'admin'
      and admin_id = (select private.current_admin_id())
    )
    or (
      employee_id = (select auth.uid())
      and admin_id = (select private.current_admin_id())
    )
  );

drop policy if exists employee_permissions_insert_admin on public.employee_permissions;
create policy employee_permissions_insert_admin
  on public.employee_permissions for insert to authenticated
  with check (
    (select private."current_role"()) = 'admin'
    and admin_id = (select private.current_admin_id())
    and updated_by = (select auth.uid())
    and exists (
      select 1 from public.profiles p
      where p.id = employee_id
        and p.role = 'employee'
        and p.admin_id = (select private.current_admin_id())
    )
  );

drop policy if exists employee_permissions_update_admin on public.employee_permissions;
create policy employee_permissions_update_admin
  on public.employee_permissions for update to authenticated
  using (
    (select private."current_role"()) = 'admin'
    and admin_id = (select private.current_admin_id())
  )
  with check (
    (select private."current_role"()) = 'admin'
    and admin_id = (select private.current_admin_id())
    and updated_by = (select auth.uid())
    and exists (
      select 1 from public.profiles p
      where p.id = employee_id
        and p.role = 'employee'
        and p.admin_id = (select private.current_admin_id())
    )
  );

drop policy if exists employee_permissions_delete_admin on public.employee_permissions;
create policy employee_permissions_delete_admin
  on public.employee_permissions for delete to authenticated
  using (
    (select private."current_role"()) = 'admin'
    and admin_id = (select private.current_admin_id())
  );

drop policy if exists market_receipt_settings_insert_admin on public.market_receipt_settings;
create policy market_receipt_settings_insert_admin
  on public.market_receipt_settings for insert to authenticated
  with check (
    (select private."current_role"()) = 'admin'
    and admin_id = (select auth.uid())
    and admin_id = (select private.current_admin_id())
  );
drop policy if exists market_receipt_settings_update_admin on public.market_receipt_settings;
create policy market_receipt_settings_update_admin
  on public.market_receipt_settings for update to authenticated
  using (
    (select private."current_role"()) = 'admin'
    and admin_id = (select auth.uid())
    and admin_id = (select private.current_admin_id())
  )
  with check (
    (select private."current_role"()) = 'admin'
    and admin_id = (select auth.uid())
    and admin_id = (select private.current_admin_id())
  );
drop policy if exists market_receipt_settings_delete_admin on public.market_receipt_settings;
create policy market_receipt_settings_delete_admin
  on public.market_receipt_settings for delete to authenticated
  using (
    (select private."current_role"()) = 'admin'
    and admin_id = (select auth.uid())
    and admin_id = (select private.current_admin_id())
  );

drop policy if exists receipt_documents_insert_staff on public.receipt_documents;
create policy receipt_documents_insert_staff
  on public.receipt_documents for insert to authenticated
  with check (
    admin_id = (select private.current_admin_id())
    and (select private."current_role"()) in ('admin', 'employee')
    and created_by = (select auth.uid())
  );

-- Privileged implementations live outside the Data API. Public entrypoints are
-- SECURITY INVOKER wrappers, while the private implementations re-check role
-- and derive tenant/actor exclusively from the authenticated session.
create or replace function private.create_tenant_backup_impl(
  p_label text,
  p_type text
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
    'profiles', coalesce((select jsonb_agg(to_jsonb(p) - 'password_hash')
      from public.profiles p where p.id = tenant_id or p.admin_id = tenant_id), '[]'::jsonb),
    'debts', coalesce((select jsonb_agg(to_jsonb(d)) from public.debts d
      where private.profile_tenant_id(d.customer_id) = tenant_id), '[]'::jsonb),
    'payments', coalesce((select jsonb_agg(to_jsonb(pay)) from public.payments pay
      where private.debt_tenant_id(pay.debt_id) = tenant_id), '[]'::jsonb),
    'employee_permissions', coalesce((select jsonb_agg(to_jsonb(ep))
      from public.employee_permissions ep where ep.admin_id = tenant_id), '[]'::jsonb)
  );
  counts := jsonb_build_object(
    'profiles', jsonb_array_length(snapshot->'profiles'),
    'debts', jsonb_array_length(snapshot->'debts'),
    'payments', jsonb_array_length(snapshot->'payments'),
    'employee_permissions', jsonb_array_length(snapshot->'employee_permissions')
  );
  insert into public.tenant_backups(
    admin_id, created_by, label, backup_type, payload, record_counts, expires_at
  ) values (
    tenant_id, auth.uid(), left(coalesce(nullif(trim(p_label),''),'Backup'),120),
    p_type, snapshot, counts,
    case when p_type = 'automatic' then now() + interval '90 days' else null end
  ) returning id into backup_id;
  insert into public.audit_logs(
    admin_id, actor_id, action, entity_type, entity_id, after_data
  ) values (tenant_id, auth.uid(), 'backup', 'tenant_backups', backup_id::text, counts);
  return backup_id;
end;
$$;
revoke all on function private.create_tenant_backup_impl(text,text)
  from public, anon;
grant execute on function private.create_tenant_backup_impl(text,text)
  to authenticated;

create or replace function public.create_tenant_backup(
  p_label text default 'Manual backup',
  p_type text default 'manual'
)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.create_tenant_backup_impl(p_label, p_type)
$$;
revoke all on function public.create_tenant_backup(text,text) from public, anon;
grant execute on function public.create_tenant_backup(text,text) to authenticated;

create or replace function private.get_tenant_export_impl()
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
revoke all on function private.get_tenant_export_impl() from public, anon;
grant execute on function private.get_tenant_export_impl() to authenticated;

create or replace function public.get_tenant_export()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select private.get_tenant_export_impl()
$$;
revoke all on function public.get_tenant_export() from public, anon;
grant execute on function public.get_tenant_export() to authenticated;

drop trigger if exists employee_permissions_sync_profile
  on public.employee_permissions;
create trigger employee_permissions_sync_profile
after insert or update on public.employee_permissions
for each row execute function private.sync_employee_permissions_to_profile();

revoke all on function private.sync_employee_permissions_to_profile()
  from public, anon, authenticated;

drop policy if exists debts_select_authorized on public.debts;
create policy debts_select_authorized
  on public.debts for select to authenticated
  using (
    is_deleted = false
    and (
      (customer_id = (select auth.uid()) and (select private."current_role"()) = 'customer')
      or (
        (select private."current_role"()) = 'admin'
        and private.profile_tenant_id(customer_id) = (select private.current_admin_id())
      )
      or (
        (select private."current_role"()) = 'employee'
        and (select private.employee_has_permission('view_debts'))
        and private.profile_tenant_id(customer_id) = (select private.current_admin_id())
      )
    )
  );

drop policy if exists debts_insert_staff on public.debts;
create policy debts_insert_staff
  on public.debts for insert to authenticated
  with check (
    (
      (select private."current_role"()) = 'admin'
      or (
        (select private."current_role"()) = 'employee'
        and (select private.employee_has_permission('add_debts'))
      )
    )
    and private.profile_tenant_id(customer_id) = (select private.current_admin_id())
    and created_by = (select auth.uid())
    and is_deleted = false
    and deleted_at is null
    and deleted_by is null
  );

drop policy if exists debts_update_staff on public.debts;
create policy debts_update_staff
  on public.debts for update to authenticated
  using (
    (
      (select private."current_role"()) = 'admin'
      or (
        (select private."current_role"()) = 'employee'
        and (select private.employee_has_permission('edit_debts'))
      )
    )
    and private.profile_tenant_id(customer_id) = (select private.current_admin_id())
    and is_deleted = false
  )
  with check (
    (
      (select private."current_role"()) = 'admin'
      or (
        (select private."current_role"()) = 'employee'
        and (select private.employee_has_permission('edit_debts'))
      )
    )
    and private.profile_tenant_id(customer_id) = (select private.current_admin_id())
    and is_deleted = false
    and deleted_at is null
    and deleted_by is null
  );

drop policy if exists payments_select_authorized on public.payments;
create policy payments_select_authorized
  on public.payments for select to authenticated
  using (
    exists (
      select 1 from public.debts d
      where d.id = debt_id and d.is_deleted = false
    )
    and (
      (
        private.debt_customer_id(debt_id) = (select auth.uid())
        and (select private."current_role"()) = 'customer'
      )
      or (
        (select private."current_role"()) = 'admin'
        and private.debt_tenant_id(debt_id) = (select private.current_admin_id())
      )
      or (
        (select private."current_role"()) = 'employee'
        and (
          (select private.employee_has_permission('view_debts'))
          or (select private.employee_has_permission('view_financial_reports'))
        )
        and private.debt_tenant_id(debt_id) = (select private.current_admin_id())
      )
    )
  );

drop policy if exists payments_insert_staff on public.payments;
create policy payments_insert_staff
  on public.payments for insert to authenticated
  with check (
    (
      (select private."current_role"()) = 'admin'
      or (
        (select private."current_role"()) = 'employee'
        and (select private.employee_has_permission('record_payments'))
      )
    )
    and private.debt_tenant_id(debt_id) = (select private.current_admin_id())
    and created_by = (select auth.uid())
    and exists (
      select 1 from public.debts d
      where d.id = debt_id and d.is_deleted = false
    )
  );

-- These helpers are referenced while PostgreSQL evaluates RLS policies.
-- Without EXECUTE, every debts/payments read fails with SQLSTATE 42501 even
-- for admins. The helper is kept in the non-exposed private schema and scopes
-- its result to auth.uid() and the caller's tenant.
grant execute on function private.employee_has_permission(text)
  to authenticated;

-- Return the complete admin dashboard in one bounded, RLS-protected query.
-- SECURITY INVOKER is intentional: every aggregate and recent row still passes
-- through the authenticated caller's tenant policies.
create or replace function public.get_admin_dashboard_snapshot()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if private."current_role"() is distinct from 'admin' then
    raise insufficient_privilege using message = 'admin role required';
  end if;

  select jsonb_build_object(
    'total_customers', (
      select count(*) from public.profiles p
      where p.role = 'customer' and p.approved = true
    ),
    'pending_requests', (
      select count(*) from public.profiles p
      where p.role = 'customer' and p.approved = false
    ),
    'total_debt', coalesce((
      select sum(d.amount) from public.debts d where d.is_deleted = false
    ), 0),
    'total_remaining', coalesce((
      select sum(d.remaining) from public.debts d where d.is_deleted = false
    ), 0),
    'pending_debts', (
      select count(*) from public.debts d
      where d.is_deleted = false and d.status <> 'paid'
    ),
    'total_payments', coalesce((
      select sum(pay.amount)
      from public.payments pay
      join public.debts d on d.id = pay.debt_id
      where d.is_deleted = false
    ), 0),
    'recent_activity', coalesce((
      select jsonb_agg(recent_row.payload order by recent_row.created_at desc)
      from (
        select
          d.created_at,
          to_jsonb(d) || jsonb_build_object(
            'customer', jsonb_build_object(
              'id', customer.id,
              'name', customer.name,
              'role', customer.role,
              'created_at', customer.created_at,
              'updated_at', customer.updated_at
            ),
            'created_by', case when creator.id is null then null else jsonb_build_object(
              'id', creator.id,
              'name', creator.name,
              'role', creator.role,
              'created_at', creator.created_at,
              'updated_at', creator.updated_at
            ) end
          ) as payload
        from public.debts d
        join public.profiles customer on customer.id = d.customer_id
        left join public.profiles creator on creator.id = d.created_by
        where d.is_deleted = false
        order by d.created_at desc
        limit 5
      ) recent_row
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_admin_dashboard_snapshot() from public, anon;
grant execute on function public.get_admin_dashboard_snapshot() to authenticated;

-- Financial audit data is owner/admin-only unless explicitly granted.
do $$
declare policy_name text;
begin
  if to_regclass('public.financial_events') is not null then
    for policy_name in
      select pol.policyname
      from pg_catalog.pg_policies pol
      where pol.schemaname = 'public' and pol.tablename = 'financial_events'
    loop
      execute format('drop policy if exists %I on public.financial_events', policy_name);
    end loop;
    execute $policy$
      create policy financial_events_permission_read
      on public.financial_events for select to authenticated
      using (
        (select private."current_role"()) = 'admin'
        or (
          (select private."current_role"()) = 'employee'
          and (select private.employee_has_permission('view_financial_reports'))
        )
        or (
          (select private."current_role"()) = 'customer'
          and customer_id = (select auth.uid())
        )
      )
    $policy$;
  end if;
end;
$$;
