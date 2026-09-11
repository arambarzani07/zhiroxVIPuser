-- Complete the runtime path used by the existing Flutter debt-delete UI.
-- Admin DELETE is intercepted as a soft delete so debt/payment history remains
-- restorable, while receipt files stay protected while referenced by any debt.

create or replace function private.soft_delete_debt_on_delete()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  -- Backend/service maintenance without an end-user session may hard-delete.
  if (select auth.uid()) is null then
    return old;
  end if;

  if private.current_role() <> 'admin' then
    raise exception 'admin_required';
  end if;

  if private.profile_tenant_id(old.customer_id) <> private.current_admin_id() then
    raise exception 'cross_tenant_forbidden';
  end if;

  update public.debts
  set is_deleted = true,
      deleted_at = now(),
      deleted_by = (select auth.uid()),
      updated_at = now()
  where id = old.id and is_deleted = false;

  return null;
end;
$$;

revoke all on function private.soft_delete_debt_on_delete() from public, anon, authenticated;

drop trigger if exists debts_soft_delete_before_delete on public.debts;
create trigger debts_soft_delete_before_delete
before delete on public.debts
for each row execute function private.soft_delete_debt_on_delete();

revoke delete on table public.debts from anon;
grant delete on table public.debts to authenticated;

drop policy if exists debts_delete_staff on public.debts;
drop policy if exists debts_delete_admin_soft on public.debts;
create policy debts_delete_admin_soft
  on public.debts for delete
  to authenticated
  using (
    private.current_role() = 'admin'
    and private.profile_tenant_id(customer_id) = private.current_admin_id()
    and is_deleted = false
  );

create or replace function private.receipt_is_referenced(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.debts d
    where d.receipt_image_path = p_name
      and p_name <> ''
  );
$$;

revoke all on function private.receipt_is_referenced(text) from public, anon;
grant execute on function private.receipt_is_referenced(text) to authenticated;

drop policy if exists receipts_delete_staff on storage.objects;
create policy receipts_delete_staff
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'receipts'
    and private.current_role() = any (array['admin'::text, 'employee'::text])
    and (storage.foldername(name))[1] = private.current_admin_id()::text
    and not private.receipt_is_referenced(name)
  );
