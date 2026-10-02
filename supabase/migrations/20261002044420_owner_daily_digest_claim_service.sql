alter table private.owner_daily_digest_settings
  add column if not exists processing_local_date date,
  add column if not exists processing_started_at timestamptz;

create or replace function public.claim_owner_daily_digest_service()
returns table(owner_user_id uuid, chat_id text, telegram_username text, local_date date)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := now();
  v_row record;
  v_local_now timestamp;
  v_local_date date;
begin
  for v_row in
    select s.owner_user_id, s.timezone, s.local_hour, s.local_minute, tc.chat_id, tc.telegram_username
    from private.owner_daily_digest_settings s
    join public.profiles p on p.id=s.owner_user_id and p.is_system_owner=true and p.active=true and p.approved=true
    join private.telegram_credentials tc on tc.user_id=s.owner_user_id and nullif(btrim(tc.chat_id),'') is not null
    where s.enabled=true
    for update of s skip locked
  loop
    v_local_now := timezone(v_row.timezone, v_now);
    v_local_date := v_local_now::date;
    if (extract(hour from v_local_now)::int > v_row.local_hour
        or (extract(hour from v_local_now)::int = v_row.local_hour and extract(minute from v_local_now)::int >= v_row.local_minute))
       and coalesce((select last_sent_local_date from private.owner_daily_digest_settings where owner_user_id=v_row.owner_user_id), date '1900-01-01') < v_local_date
       and (
         (select processing_started_at from private.owner_daily_digest_settings where owner_user_id=v_row.owner_user_id) is null
         or (select processing_started_at from private.owner_daily_digest_settings where owner_user_id=v_row.owner_user_id) < v_now - interval '10 minutes'
       )
    then
      update private.owner_daily_digest_settings
      set processing_local_date=v_local_date, processing_started_at=v_now, last_error=null, updated_at=v_now
      where owner_user_id=v_row.owner_user_id;
      owner_user_id := v_row.owner_user_id;
      chat_id := v_row.chat_id;
      telegram_username := v_row.telegram_username;
      local_date := v_local_date;
      return next;
    end if;
  end loop;
end;
$$;
revoke all on function public.claim_owner_daily_digest_service() from public, anon, authenticated;
grant execute on function public.claim_owner_daily_digest_service() to service_role;

create or replace function public.finish_owner_daily_digest_service(p_owner_user_id uuid, p_local_date date, p_success boolean, p_error text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.owner_daily_digest_settings
  set last_sent_local_date = case when p_success then p_local_date else last_sent_local_date end,
      last_sent_at = case when p_success then now() else last_sent_at end,
      last_error = case when p_success then null else left(coalesce(p_error,'delivery_failed'),500) end,
      processing_local_date = null,
      processing_started_at = null,
      updated_at = now()
  where owner_user_id=p_owner_user_id;
end;
$$;
revoke all on function public.finish_owner_daily_digest_service(uuid,date,boolean,text) from public, anon, authenticated;
grant execute on function public.finish_owner_daily_digest_service(uuid,date,boolean,text) to service_role;
