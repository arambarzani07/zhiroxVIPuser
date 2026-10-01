create or replace function public.set_telegram_bot_token_service(p_bot_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text := btrim(coalesce(p_bot_token, ''));
  v_id uuid;
begin
  if v_token = '' or length(v_token) < 20 or length(v_token) > 512 or position(':' in v_token) = 0 then
    raise exception 'invalid_telegram_bot_token';
  end if;

  select s.id
    into v_id
  from vault.secrets s
  where s.name = 'telegram_bot_token'
  order by s.created_at desc
  limit 1;

  if v_id is null then
    perform vault.create_secret(
      v_token,
      'telegram_bot_token',
      'ZHIROX official Telegram bot token; managed by system owner only'
    );
  else
    perform vault.update_secret(
      v_id,
      v_token,
      'telegram_bot_token',
      'ZHIROX official Telegram bot token; managed by system owner only'
    );
  end if;
end;
$$;

revoke all on function public.set_telegram_bot_token_service(text) from public, anon, authenticated;
grant execute on function public.set_telegram_bot_token_service(text) to service_role;

create or replace function public.clear_telegram_bot_token_service()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from vault.secrets where name = 'telegram_bot_token';
$$;

revoke all on function public.clear_telegram_bot_token_service() from public, anon, authenticated;
grant execute on function public.clear_telegram_bot_token_service() to service_role;
