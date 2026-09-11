create or replace function public.renew_system_owner_admin_subscription(
  p_admin_id uuid,
  p_days integer
)
returns timestamptz
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_new_end timestamptz;
begin
  if v_uid is null or not exists (
    select 1
    from public.profiles p
    where p.id = v_uid
      and p.is_system_owner = true
      and p.active = true
  ) then
    raise exception 'system_owner_required' using errcode = '42501';
  end if;

  if p_admin_id is null or p_days is null or p_days < 1 or p_days > 3650 then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  update public.profiles a
     set subscription_end = greatest(coalesce(a.subscription_end, now()), now())
                            + make_interval(days => p_days),
         updated_at = now()
   where a.id = p_admin_id
     and a.role = 'admin'
     and a.is_system_owner = false
  returning a.subscription_end into v_new_end;

  if v_new_end is null then
    raise exception 'admin_not_found' using errcode = 'P0002';
  end if;

  return v_new_end;
end;
$function$;

revoke all on function public.renew_system_owner_admin_subscription(uuid, integer) from public, anon;
grant execute on function public.renew_system_owner_admin_subscription(uuid, integer) to authenticated;
