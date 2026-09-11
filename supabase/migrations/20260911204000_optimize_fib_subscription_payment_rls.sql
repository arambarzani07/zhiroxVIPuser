drop policy if exists subscription_payments_select_own on public.subscription_payments;
create policy subscription_payments_select_own
  on public.subscription_payments for select
  to authenticated
  using (
    admin_id = (select auth.uid())
    or exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.is_system_owner = true
    )
  );
