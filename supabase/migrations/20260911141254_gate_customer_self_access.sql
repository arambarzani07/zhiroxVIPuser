drop policy if exists debts_select_authorized on public.debts;
create policy debts_select_authorized
on public.debts for select to authenticated
using (
  (customer_id = (select auth.uid()) and private.current_role() = 'customer')
  or (
    private.current_role() = any(array['admin'::text, 'employee'::text])
    and private.profile_tenant_id(customer_id) = private.current_admin_id()
  )
);

drop policy if exists payments_select_authorized on public.payments;
create policy payments_select_authorized
on public.payments for select to authenticated
using (
  (private.debt_customer_id(debt_id) = (select auth.uid()) and private.current_role() = 'customer')
  or (
    private.current_role() = any(array['admin'::text, 'employee'::text])
    and private.debt_tenant_id(debt_id) = private.current_admin_id()
  )
);

drop policy if exists financial_events_select_authorized on public.financial_events;
create policy financial_events_select_authorized
on public.financial_events for select to authenticated
using (
  (customer_id = (select auth.uid()) and private.current_role() = 'customer')
  or (
    private.current_role() = any(array['admin'::text, 'employee'::text])
    and private.profile_tenant_id(customer_id) = private.current_admin_id()
  )
);

drop policy if exists notifications_select_authorized on public.notifications;
create policy notifications_select_authorized
on public.notifications for select to authenticated
using (
  (customer_id = (select auth.uid()) and private.current_role() = 'customer')
  or (
    private.current_role() = any(array['admin'::text, 'employee'::text])
    and private.profile_tenant_id(customer_id) = private.current_admin_id()
  )
);

drop policy if exists notifications_delete_authorized on public.notifications;
create policy notifications_delete_authorized
on public.notifications for delete to authenticated
using (
  (customer_id = (select auth.uid()) and private.current_role() = 'customer')
  or (
    private.current_role() = 'admin'
    and private.profile_tenant_id(customer_id) = private.current_admin_id()
  )
);

drop policy if exists notifications_update_recipient on public.notifications;
create policy notifications_update_recipient
on public.notifications for update to authenticated
using (customer_id = (select auth.uid()) and private.current_role() = 'customer')
with check (customer_id = (select auth.uid()) and private.current_role() = 'customer');

drop policy if exists financial_chat_reads_select_own on public.financial_chat_reads;
create policy financial_chat_reads_select_own
on public.financial_chat_reads for select to authenticated
using (viewer_id = (select auth.uid()) and private.current_role() is not null);

drop policy if exists financial_chat_reads_insert_own on public.financial_chat_reads;
create policy financial_chat_reads_insert_own
on public.financial_chat_reads for insert to authenticated
with check (
  viewer_id = (select auth.uid())
  and (
    (customer_id = (select auth.uid()) and private.current_role() = 'customer')
    or (
      private.current_role() = any(array['admin'::text, 'employee'::text])
      and private.profile_tenant_id(customer_id) = private.current_admin_id()
    )
  )
);

drop policy if exists financial_chat_reads_update_own on public.financial_chat_reads;
create policy financial_chat_reads_update_own
on public.financial_chat_reads for update to authenticated
using (
  viewer_id = (select auth.uid())
  and (
    (customer_id = (select auth.uid()) and private.current_role() = 'customer')
    or (
      private.current_role() = any(array['admin'::text, 'employee'::text])
      and private.profile_tenant_id(customer_id) = private.current_admin_id()
    )
  )
)
with check (
  viewer_id = (select auth.uid())
  and (
    (customer_id = (select auth.uid()) and private.current_role() = 'customer')
    or (
      private.current_role() = any(array['admin'::text, 'employee'::text])
      and private.profile_tenant_id(customer_id) = private.current_admin_id()
    )
  )
);
