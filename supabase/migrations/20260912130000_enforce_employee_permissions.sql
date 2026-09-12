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
      (customer_id = auth.uid() and private."current_role"() = 'customer')
      or (
        private."current_role"() = 'admin'
        and private.profile_tenant_id(customer_id) = private.current_admin_id()
      )
      or (
        private."current_role"() = 'employee'
        and private.employee_has_permission('view_debts')
        and private.profile_tenant_id(customer_id) = private.current_admin_id()
      )
    )
  );

drop policy if exists debts_insert_staff on public.debts;
create policy debts_insert_staff
  on public.debts for insert to authenticated
  with check (
    (
      private."current_role"() = 'admin'
      or (
        private."current_role"() = 'employee'
        and private.employee_has_permission('add_debts')
      )
    )
    and private.profile_tenant_id(customer_id) = private.current_admin_id()
    and created_by = auth.uid()
    and is_deleted = false
    and deleted_at is null
    and deleted_by is null
  );

drop policy if exists debts_update_staff on public.debts;
create policy debts_update_staff
  on public.debts for update to authenticated
  using (
    (
      private."current_role"() = 'admin'
      or (
        private."current_role"() = 'employee'
        and private.employee_has_permission('edit_debts')
      )
    )
    and private.profile_tenant_id(customer_id) = private.current_admin_id()
    and is_deleted = false
  )
  with check (
    (
      private."current_role"() = 'admin'
      or (
        private."current_role"() = 'employee'
        and private.employee_has_permission('edit_debts')
      )
    )
    and private.profile_tenant_id(customer_id) = private.current_admin_id()
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
        private.debt_customer_id(debt_id) = auth.uid()
        and private."current_role"() = 'customer'
      )
      or (
        private."current_role"() = 'admin'
        and private.debt_tenant_id(debt_id) = private.current_admin_id()
      )
      or (
        private."current_role"() = 'employee'
        and (
          private.employee_has_permission('view_debts')
          or private.employee_has_permission('view_financial_reports')
        )
        and private.debt_tenant_id(debt_id) = private.current_admin_id()
      )
    )
  );

drop policy if exists payments_insert_staff on public.payments;
create policy payments_insert_staff
  on public.payments for insert to authenticated
  with check (
    (
      private."current_role"() = 'admin'
      or (
        private."current_role"() = 'employee'
        and private.employee_has_permission('record_payments')
      )
    )
    and private.debt_tenant_id(debt_id) = private.current_admin_id()
    and created_by = auth.uid()
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
        private."current_role"() = 'admin'
        or (
          private."current_role"() = 'employee'
          and private.employee_has_permission('view_financial_reports')
        )
        or (
          private."current_role"() = 'customer'
          and customer_id = auth.uid()
        )
      )
    $policy$;
  end if;
end;
$$;
