-- Fix critical cross-tenant read access on financial_events.
-- Admins and employees may only read events belonging to their current tenant.
-- Customers may only read their own events.

drop policy if exists financial_events_permission_read
  on public.financial_events;

create policy financial_events_permission_read
on public.financial_events
for select
to authenticated
using (
  (
    (select private."current_role"()) = 'customer'
    and customer_id = (select auth.uid())
  )
  or
  (
    (select private."current_role"()) = 'admin'
    and private.profile_tenant_id(customer_id) =
        (select private.current_admin_id())
  )
  or
  (
    (select private."current_role"()) = 'employee'
    and (select private.employee_has_permission('view_financial_reports'))
    and private.profile_tenant_id(customer_id) =
        (select private.current_admin_id())
  )
);
