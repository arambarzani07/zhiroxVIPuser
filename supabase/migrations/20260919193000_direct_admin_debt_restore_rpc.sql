-- Direct, authenticated admin debt restore path.
-- Avoids Edge Function gateway/auth ambiguity while keeping tenant checks server-side.

revoke all on function public.list_deleted_debts(integer) from public, anon;
grant execute on function public.list_deleted_debts(integer) to authenticated, service_role;

create or replace function public.restore_deleted_debt(p_debt_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  return public.restore_debt_service(v_uid, p_debt_id);
end;
$$;

revoke all on function public.restore_deleted_debt(uuid) from public, anon;
grant execute on function public.restore_deleted_debt(uuid) to authenticated, service_role;
