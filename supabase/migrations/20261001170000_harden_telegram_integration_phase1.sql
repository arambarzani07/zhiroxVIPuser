alter table private.telegram_credentials
  alter column bot_token set default '';

alter table private.telegram_credentials
  add column if not exists telegram_user_id bigint,
  add column if not exists telegram_username text,
  add column if not exists connected_at timestamptz,
  add column if not exists last_tested_at timestamptz;

revoke all on table private.telegram_credentials from public, anon, authenticated;
grant select, insert, update, delete on table private.telegram_credentials to service_role;

revoke all on function public.get_my_telegram_credentials() from public, anon, authenticated;
grant execute on function public.get_my_telegram_credentials() to service_role;
revoke all on function public.set_my_telegram_credentials(text, text) from public, anon, authenticated;
grant execute on function public.set_my_telegram_credentials(text, text) to service_role;

create table if not exists private.telegram_link_codes (
  user_id uuid primary key references auth.users(id) on delete cascade,
  code_hash text not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);
revoke all on table private.telegram_link_codes from public, anon, authenticated;
grant select, insert, update, delete on table private.telegram_link_codes to service_role;

create or replace function public.get_my_telegram_status()
returns table(
  connected boolean,
  telegram_username text,
  chat_hint text,
  connected_at timestamptz,
  last_tested_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;

  return query
  select
    (nullif(btrim(tc.chat_id), '') is not null),
    nullif(btrim(tc.telegram_username), ''),
    case
      when nullif(btrim(tc.chat_id), '') is null then null
      when length(tc.chat_id) <= 4 then '••••'
      else '••••' || right(tc.chat_id, 4)
    end,
    tc.connected_at,
    tc.last_tested_at
  from private.telegram_credentials tc
  where tc.user_id = v_uid;

  if not found then
    return query
    select false, null::text, null::text, null::timestamptz, null::timestamptz;
  end if;
end;
$$;
revoke all on function public.get_my_telegram_status() from public, anon;
grant execute on function public.get_my_telegram_status() to authenticated, service_role;

create or replace function public.disconnect_my_telegram()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;
  delete from private.telegram_link_codes where user_id = v_uid;
  delete from private.telegram_credentials where user_id = v_uid;
end;
$$;
revoke all on function public.disconnect_my_telegram() from public, anon;
grant execute on function public.disconnect_my_telegram() to authenticated, service_role;

create or replace function public.get_telegram_runtime_config_service()
returns table(bot_token text)
language sql
security definer
set search_path = ''
as $$
  select max(v.decrypted_secret) filter (where v.name = 'telegram_bot_token')
  from vault.decrypted_secrets v
  where v.name = 'telegram_bot_token';
$$;
revoke all on function public.get_telegram_runtime_config_service() from public, anon, authenticated;
grant execute on function public.get_telegram_runtime_config_service() to service_role;

create or replace function public.get_telegram_connection_for_service(p_user_id uuid)
returns table(
  chat_id text,
  telegram_user_id bigint,
  telegram_username text,
  connected_at timestamptz,
  last_tested_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
  select tc.chat_id, tc.telegram_user_id, tc.telegram_username,
         tc.connected_at, tc.last_tested_at
  from private.telegram_credentials tc
  where tc.user_id = p_user_id
    and nullif(btrim(tc.chat_id), '') is not null;
$$;
revoke all on function public.get_telegram_connection_for_service(uuid) from public, anon, authenticated;
grant execute on function public.get_telegram_connection_for_service(uuid) to service_role;

create or replace function public.create_telegram_link_code_service(
  p_user_id uuid,
  p_code_hash text,
  p_expires_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_user_id is null or nullif(btrim(p_code_hash), '') is null or p_expires_at <= now() then
    raise exception 'invalid_input';
  end if;

  insert into private.telegram_link_codes(user_id, code_hash, expires_at, used_at, created_at)
  values (p_user_id, p_code_hash, p_expires_at, null, now())
  on conflict (user_id) do update
    set code_hash = excluded.code_hash,
        expires_at = excluded.expires_at,
        used_at = null,
        created_at = now();
end;
$$;
revoke all on function public.create_telegram_link_code_service(uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function public.create_telegram_link_code_service(uuid, text, timestamptz) to service_role;

create or replace function public.consume_telegram_link_code_service(
  p_code_hash text,
  p_chat_id text,
  p_telegram_user_id bigint,
  p_telegram_username text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
begin
  if nullif(btrim(p_code_hash), '') is null or nullif(btrim(p_chat_id), '') is null then
    return null;
  end if;

  select c.user_id into v_user_id
  from private.telegram_link_codes c
  where c.code_hash = p_code_hash
    and c.used_at is null
    and c.expires_at > now()
  for update;

  if v_user_id is null then
    return null;
  end if;

  update private.telegram_link_codes set used_at = now()
  where user_id = v_user_id;

  insert into private.telegram_credentials(
    user_id, bot_token, chat_id, telegram_user_id, telegram_username,
    connected_at, last_tested_at, updated_at
  ) values (
    v_user_id, '', p_chat_id, p_telegram_user_id,
    nullif(btrim(p_telegram_username), ''), now(), null, now()
  )
  on conflict (user_id) do update
    set bot_token = '',
        chat_id = excluded.chat_id,
        telegram_user_id = excluded.telegram_user_id,
        telegram_username = excluded.telegram_username,
        connected_at = now(),
        last_tested_at = null,
        updated_at = now();

  return v_user_id;
end;
$$;
revoke all on function public.consume_telegram_link_code_service(text, text, bigint, text) from public, anon, authenticated;
grant execute on function public.consume_telegram_link_code_service(text, text, bigint, text) to service_role;

create or replace function public.mark_telegram_tested_service(p_user_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.telegram_credentials
  set last_tested_at = now(), updated_at = now()
  where user_id = p_user_id;
$$;
revoke all on function public.mark_telegram_tested_service(uuid) from public, anon, authenticated;
grant execute on function public.mark_telegram_tested_service(uuid) to service_role;

create or replace function public.disconnect_telegram_for_service(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from private.telegram_link_codes where user_id = p_user_id;
  delete from private.telegram_credentials where user_id = p_user_id;
end;
$$;
revoke all on function public.disconnect_telegram_for_service(uuid) from public, anon, authenticated;
grant execute on function public.disconnect_telegram_for_service(uuid) to service_role;
