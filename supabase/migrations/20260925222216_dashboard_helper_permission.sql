-- Allow security-invoker dashboard/finance RPCs to call the private
-- general-payment balance helper while keeping it unavailable to anon users.
revoke all on function private.customer_unmirrored_general_paid_total(uuid)
  from public, anon;
grant execute on function private.customer_unmirrored_general_paid_total(uuid)
  to authenticated, service_role;
