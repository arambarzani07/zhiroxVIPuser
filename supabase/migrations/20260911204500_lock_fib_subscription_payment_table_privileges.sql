revoke all privileges on table public.subscription_payments from anon;
revoke all privileges on table public.subscription_payments from authenticated;
grant select on table public.subscription_payments to authenticated;

grant select, insert, update, delete on table public.subscription_payments to service_role;
