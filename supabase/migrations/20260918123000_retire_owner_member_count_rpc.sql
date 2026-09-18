-- Retire the legacy System Owner paging RPC because it exposed tenant member
-- counts. Owner platform management must remain metadata-only.

revoke execute on function public.get_system_owner_admins_page(integer, integer)
  from authenticated;

grant execute on function public.get_system_owner_admins_page(integer, integer)
  to service_role;
