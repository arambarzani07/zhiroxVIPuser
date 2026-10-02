create table if not exists private.owner_daily_digest_settings (
  owner_user_id uuid primary key references public.profiles(id) on delete cascade,
  enabled boolean not null default true,
  timezone text not null default 'Asia/Baghdad',
  local_hour smallint not null default 8 check (local_hour between 0 and 23),
  local_minute smallint not null default 30 check (local_minute between 0 and 59),
  last_sent_local_date date,
  last_sent_at timestamptz,
  last_error text,
  updated_at timestamptz not null default now()
);
alter table private.owner_daily_digest_settings enable row level security;
revoke all on private.owner_daily_digest_settings from public, anon, authenticated;
grant select, insert, update, delete on private.owner_daily_digest_settings to service_role;

insert into private.owner_daily_digest_settings(owner_user_id)
select id from public.profiles where is_system_owner = true and active = true
on conflict (owner_user_id) do nothing;

create or replace function public.get_telegram_system_owner_by_chat_service(p_chat_id text)
returns uuid
language sql
security definer
set search_path = ''
as $$
  select p.id
  from private.telegram_credentials tc
  join public.profiles p on p.id = tc.user_id
  where tc.chat_id = nullif(btrim(p_chat_id),'')
    and p.is_system_owner = true
    and p.active = true
    and p.approved = true
  limit 1;
$$;
revoke all on function public.get_telegram_system_owner_by_chat_service(text) from public, anon, authenticated;
grant execute on function public.get_telegram_system_owner_by_chat_service(text) to service_role;

create or replace function private.invoke_owner_daily_digest_worker_service()
returns bigint
language plpgsql
security definer
set search_path = 'pg_catalog','public'
as $$
declare
  v_config jsonb;
  v_secret text;
  v_request_id bigint;
begin
  v_config := public.get_customer_push_runtime_config_service();
  v_secret := nullif(v_config->>'customer_push_worker_secret','');
  if v_secret is null then raise exception 'customer_push_worker_secret_missing'; end if;
  select net.http_post(
    url := 'https://madoflmbretqghqbqaak.supabase.co/functions/v1/owner-daily-digest-worker',
    body := '{}'::jsonb,
    params := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','x-zhirox-push-worker',v_secret),
    timeout_milliseconds := 10000
  ) into v_request_id;
  return v_request_id;
end;
$$;
revoke all on function private.invoke_owner_daily_digest_worker_service() from public, anon, authenticated;
grant execute on function private.invoke_owner_daily_digest_worker_service() to service_role;

do $$
declare v_jobid bigint;
begin
  select jobid into v_jobid from cron.job where jobname='zhirox-owner-daily-digest-worker';
  if v_jobid is not null then perform cron.unschedule(v_jobid); end if;
  perform cron.schedule('zhirox-owner-daily-digest-worker','*/15 * * * *','select private.invoke_owner_daily_digest_worker_service();');
end $$;
