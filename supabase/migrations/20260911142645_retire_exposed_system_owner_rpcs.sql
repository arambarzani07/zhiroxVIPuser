revoke all on function public.get_system_owner_admins_page(integer, integer)
from public, anon, authenticated;
revoke all on function public.renew_system_owner_admin_subscription(uuid, integer)
from public, anon, authenticated;

grant execute on function public.get_system_owner_admins_page(integer, integer)
to service_role;
grant execute on function public.renew_system_owner_admin_subscription(uuid, integer)
to service_role;
