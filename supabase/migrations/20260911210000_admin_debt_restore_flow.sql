-- Admin-only debt trash / restore flow.
-- Ordinary app queries only see active debts; restore operations are performed
-- by the authenticated debt-restore-admin Edge Function after tenant checks.

alter table public.debts
  add column if not exists is_deleted boolean not null default false,
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references public.profiles(id) on delete set null;

alter table public.debts
  drop constraint if exists debts_deleted_metadata_check;
alter table public.debts
  add constraint debts_deleted_metadata_check
  check (
    (is_deleted = false and deleted_at is null and deleted_by is null)
    or (is_deleted = true and deleted_at is not null)
  );

create index if not exists debts_active_customer_created_idx
  on public.debts (customer_id, created_at desc)
  where is_deleted = false;
create index if not exists debts_deleted_customer_deleted_idx
  on public.debts (customer_id, deleted_at desc)
  where is_deleted = true;
create index if not exists debts_deleted_by_idx
  on public.debts (deleted_by)
  where deleted_by is not null;

drop policy if exists debts_select_authorized on public.debts;
create policy debts_select_authorized
  on public.debts for select
  to authenticated
  using (
    is_deleted = false
    and (
      (
        customer_id = (select auth.uid())
        and private."current_role"() = 'customer'
      )
      or (
        private."current_role"() = any (array['admin'::text, 'employee'::text])
        and private.profile_tenant_id(customer_id) = private.current_admin_id()
      )
    )
  );

drop policy if exists debts_insert_staff on public.debts;
create policy debts_insert_staff
  on public.debts for insert
  to authenticated
  with check (
    private."current_role"() = any (array['admin'::text, 'employee'::text])
    and private.profile_tenant_id(customer_id) = private.current_admin_id()
    and created_by = (select auth.uid())
    and is_deleted = false
    and deleted_at is null
    and deleted_by is null
  );

drop policy if exists debts_update_staff on public.debts;
create policy debts_update_staff
  on public.debts for update
  to authenticated
  using (
    (
      private."current_role"() = 'admin'
      or (
        private."current_role"() = 'employee'
        and private.current_can_edit_debts()
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
        and private.current_can_edit_debts()
      )
    )
    and private.profile_tenant_id(customer_id) = private.current_admin_id()
    and is_deleted = false
    and deleted_at is null
    and deleted_by is null
  );

drop policy if exists debts_delete_staff on public.debts;
revoke delete on table public.debts from anon, authenticated;

drop policy if exists payments_select_authorized on public.payments;
create policy payments_select_authorized
  on public.payments for select
  to authenticated
  using (
    exists (
      select 1 from public.debts d
      where d.id = debt_id and d.is_deleted = false
    )
    and (
      (
        private.debt_customer_id(debt_id) = (select auth.uid())
        and private."current_role"() = 'customer'
      )
      or (
        private."current_role"() = any (array['admin'::text, 'employee'::text])
        and private.debt_tenant_id(debt_id) = private.current_admin_id()
      )
    )
  );

drop policy if exists payments_insert_staff on public.payments;
create policy payments_insert_staff
  on public.payments for insert
  to authenticated
  with check (
    private."current_role"() = any (array['admin'::text, 'employee'::text])
    and private.debt_tenant_id(debt_id) = private.current_admin_id()
    and created_by = (select auth.uid())
    and exists (
      select 1 from public.debts d
      where d.id = debt_id and d.is_deleted = false
    )
  );

drop policy if exists payments_update_admin on public.payments;
create policy payments_update_admin
  on public.payments for update
  to authenticated
  using (
    private."current_role"() = 'admin'
    and private.debt_tenant_id(debt_id) = private.current_admin_id()
    and exists (
      select 1 from public.debts d
      where d.id = debt_id and d.is_deleted = false
    )
  )
  with check (
    private."current_role"() = 'admin'
    and private.debt_tenant_id(debt_id) = private.current_admin_id()
    and exists (
      select 1 from public.debts d
      where d.id = debt_id and d.is_deleted = false
    )
  );

drop policy if exists payments_delete_admin on public.payments;
create policy payments_delete_admin
  on public.payments for delete
  to authenticated
  using (
    private."current_role"() = 'admin'
    and private.debt_tenant_id(debt_id) = private.current_admin_id()
    and exists (
      select 1 from public.debts d
      where d.id = debt_id and d.is_deleted = false
    )
  );

create or replace function private.guard_payment_active_debt()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.debts d
    where d.id = new.debt_id
      and d.is_deleted = false
  ) then
    raise exception 'debt_deleted_or_missing' using errcode = '23503';
  end if;
  return new;
end;
$$;

drop trigger if exists payments_guard_active_debt on public.payments;
create trigger payments_guard_active_debt
before insert or update of debt_id on public.payments
for each row execute function private.guard_payment_active_debt();

revoke all on function private.guard_payment_active_debt() from public, anon, authenticated;

-- Legacy restore RPCs, if present from an older deployment, must not be
-- directly callable by frontend roles. The Edge Function owns this boundary.
do $$
begin
  if to_regprocedure('public.soft_delete_debt(uuid)') is not null then
    execute 'revoke all on function public.soft_delete_debt(uuid) from public, anon, authenticated';
    execute 'grant execute on function public.soft_delete_debt(uuid) to service_role';
  end if;
  if to_regprocedure('public.restore_debt(uuid)') is not null then
    execute 'revoke all on function public.restore_debt(uuid) from public, anon, authenticated';
    execute 'grant execute on function public.restore_debt(uuid) to service_role';
  end if;
  if to_regprocedure('public.list_deleted_debts(integer)') is not null then
    execute 'revoke all on function public.list_deleted_debts(integer) from public, anon, authenticated';
    execute 'grant execute on function public.list_deleted_debts(integer) to service_role';
  end if;
end;
$$;
