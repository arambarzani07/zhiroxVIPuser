create or replace function public.ask_owner_telegram_os_service(
  p_owner_user_id uuid,
  p_text text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  v_result := public.ask_owner_telegram_os_phase2_service(p_owner_user_id, p_text);

  if lower(trim(coalesce(p_text,''))) = 'help'
     and coalesce(v_result->>'intent','') = 'help' then
    v_result := jsonb_set(v_result, '{intent}', to_jsonb('brief_help'::text), true);
  end if;

  return v_result;
end;
$function$;

revoke all on function public.ask_owner_telegram_os_service(uuid,text) from public, anon, authenticated;
grant execute on function public.ask_owner_telegram_os_service(uuid,text) to service_role;
