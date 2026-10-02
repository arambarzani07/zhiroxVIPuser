create table if not exists private.owner_telegram_os_command_log (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references public.profiles(id) on delete cascade,
  command text not null,
  result text not null default 'ok',
  context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists owner_telegram_os_command_log_owner_created_idx
  on private.owner_telegram_os_command_log(owner_user_id, created_at desc);

alter table private.owner_telegram_os_command_log enable row level security;
revoke all on table private.owner_telegram_os_command_log from public, anon, authenticated;
grant select, insert on table private.owner_telegram_os_command_log to service_role;

drop policy if exists owner_telegram_os_command_log_deny_client on private.owner_telegram_os_command_log;
create policy owner_telegram_os_command_log_deny_client
  on private.owner_telegram_os_command_log
  for all to anon, authenticated
  using (false) with check (false);

create or replace function public.log_owner_telegram_os_command_service(
  p_owner_user_id uuid,
  p_command text,
  p_result text default 'ok',
  p_context jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_command text := left(btrim(coalesce(p_command,'')),64);
  v_result text := left(btrim(coalesce(p_result,'ok')),32);
begin
  if not exists(select 1 from public.profiles p where p.id=p_owner_user_id and p.is_system_owner=true and p.active=true and p.approved=true) then
    raise exception 'owner_required' using errcode='42501';
  end if;
  if v_command='' then raise exception 'command_required' using errcode='22023'; end if;
  insert into private.owner_telegram_os_command_log(owner_user_id,command,result,context)
  values(p_owner_user_id,v_command,coalesce(nullif(v_result,''),'ok'),coalesce(p_context,'{}'::jsonb))
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.log_owner_telegram_os_command_service(uuid,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.log_owner_telegram_os_command_service(uuid,text,text,jsonb) to service_role;
