create or replace function public.get_customer_push_runtime_config_service()
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_object_agg(s.name, s.decrypted_secret),
    '{}'::jsonb
  )
  from vault.decrypted_secrets s
  where s.name in (
    'customer_push_vapid_public',
    'customer_push_vapid_private',
    'customer_push_vapid_subject',
    'customer_push_worker_secret',
    'customer_push_rate_limit_salt'
  );
$$;

revoke all on function public.get_customer_push_runtime_config_service()
from public, anon, authenticated;
grant execute on function public.get_customer_push_runtime_config_service()
to service_role;
