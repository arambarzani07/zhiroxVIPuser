create or replace function public.initialize_customer_push_runtime_config_service(
  p_vapid_public text,
  p_vapid_private text,
  p_vapid_subject text,
  p_worker_secret text,
  p_rate_limit_salt text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('zhirox_customer_push_runtime'));

  if not exists (select 1 from vault.decrypted_secrets where name='customer_push_vapid_public') then
    perform vault.create_secret(p_vapid_public, 'customer_push_vapid_public', 'ZHIROX Web Push public key');
  end if;
  if not exists (select 1 from vault.decrypted_secrets where name='customer_push_vapid_private') then
    perform vault.create_secret(p_vapid_private, 'customer_push_vapid_private', 'ZHIROX Web Push private key');
  end if;
  if not exists (select 1 from vault.decrypted_secrets where name='customer_push_vapid_subject') then
    perform vault.create_secret(p_vapid_subject, 'customer_push_vapid_subject', 'ZHIROX Web Push VAPID subject');
  end if;
  if not exists (select 1 from vault.decrypted_secrets where name='customer_push_worker_secret') then
    perform vault.create_secret(p_worker_secret, 'customer_push_worker_secret', 'ZHIROX push worker authentication secret');
  end if;
  if not exists (select 1 from vault.decrypted_secrets where name='customer_push_rate_limit_salt') then
    perform vault.create_secret(p_rate_limit_salt, 'customer_push_rate_limit_salt', 'ZHIROX push rate-limit salt');
  end if;

  return public.get_customer_push_runtime_config_service();
end;
$$;

revoke all on function public.initialize_customer_push_runtime_config_service(text,text,text,text,text)
from public, anon, authenticated;
grant execute on function public.initialize_customer_push_runtime_config_service(text,text,text,text,text)
to service_role;
