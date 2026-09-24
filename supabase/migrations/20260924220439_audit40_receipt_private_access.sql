-- Mirrors production migration 20260924220439: audit40_receipt_private_access.
-- Legacy tenant/<file> receipts remain readable by the owning customer, while
-- new receipts use tenant/customer/<file> paths.

create or replace function private.receipt_belongs_to_customer(
  p_name text,
  p_customer_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists(
    select 1
    from public.debts d
    where d.receipt_image_path = p_name
      and d.customer_id = p_customer_id
      and d.is_deleted = false
  );
$function$;

revoke all on function private.receipt_belongs_to_customer(text,uuid)
  from public, anon;
grant execute on function private.receipt_belongs_to_customer(text,uuid)
  to authenticated, service_role;

drop policy if exists receipts_select on storage.objects;
create policy receipts_select
on storage.objects
for select
to authenticated
using (
  bucket_id='receipts'
  and (storage.foldername(name))[1]=private.current_admin_id()::text
  and (
    private."current_role"() in ('admin','employee')
    or (
      private."current_role"()='customer'
      and (
        (storage.foldername(name))[2]=auth.uid()::text
        or private.receipt_belongs_to_customer(name,auth.uid())
      )
    )
  )
);
