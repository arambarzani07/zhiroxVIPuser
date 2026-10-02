do $do$
declare
  v_def text;
begin
  if to_regprocedure('public.ask_owner_telegram_os_v1_service(uuid,text)') is null then
    select pg_get_functiondef('public.ask_owner_telegram_os_service(uuid,text)'::regprocedure) into v_def;
    v_def := replace(v_def,
      'CREATE OR REPLACE FUNCTION public.ask_owner_telegram_os_service',
      'CREATE OR REPLACE FUNCTION public.ask_owner_telegram_os_v1_service');
    execute v_def;
  end if;

  select pg_get_functiondef('public.ask_owner_telegram_os_phase2_service(uuid,text)'::regprocedure) into v_def;
  v_def := replace(v_def,
    'public.ask_owner_telegram_os_service(p_owner_user_id,v_raw)',
    'public.ask_owner_telegram_os_v1_service(p_owner_user_id,v_raw)');
  execute v_def;
end
$do$;

create or replace function public.ask_owner_telegram_os_service(
  p_owner_user_id uuid,
  p_text text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  return public.ask_owner_telegram_os_phase2_service(p_owner_user_id,p_text);
end;
$function$;

revoke all on function public.ask_owner_telegram_os_v1_service(uuid,text) from public,anon,authenticated;
grant execute on function public.ask_owner_telegram_os_v1_service(uuid,text) to service_role;
revoke all on function public.ask_owner_telegram_os_service(uuid,text) from public,anon,authenticated;
grant execute on function public.ask_owner_telegram_os_service(uuid,text) to service_role;
