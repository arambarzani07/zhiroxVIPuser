create or replace function public.get_system_owner_admins_page(
  p_page integer default 1,
  p_per_page integer default 15
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_page integer := greatest(coalesce(p_page, 1), 1);
  v_per_page integer := least(greatest(coalesce(p_per_page, 15), 1), 100);
  v_total integer;
  v_total_pages integer;
  v_items jsonb;
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

  select count(*)::integer
    into v_total
  from public.profiles a
  where a.role = 'admin'
    and a.is_system_owner = false;

  v_total_pages := case
    when v_total = 0 then 1
    else ceil(v_total::numeric / v_per_page)::integer
  end;

  select coalesce(jsonb_agg(row_payload order by created_at desc, id desc), '[]'::jsonb)
    into v_items
  from (
    select
      a.id,
      a.created_at,
      jsonb_build_object(
        'admin', jsonb_build_object(
          'id', a.id,
          'name', a.name,
          'phone', a.phone,
          'role', a.role,
          'market_name', a.market_name,
          'subscription_end', a.subscription_end,
          'approved', a.approved,
          'active', a.active,
          'is_system_owner', a.is_system_owner,
          'created_at', a.created_at,
          'updated_at', a.updated_at
        ),
        'employee_count', count(m.id) filter (where m.role = 'employee'),
        'customer_count', count(m.id) filter (where m.role = 'customer')
      ) as row_payload
    from public.profiles a
    left join public.profiles m
      on m.admin_id = a.id
     and m.role in ('employee', 'customer')
    where a.role = 'admin'
      and a.is_system_owner = false
    group by a.id
    order by a.created_at desc, a.id desc
    offset (v_page - 1) * v_per_page
    limit v_per_page
  ) page_rows;

  return jsonb_build_object(
    'admins', v_items,
    'total_items', v_total,
    'total_pages', v_total_pages,
    'page', v_page
  );
end;
$function$;

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
     set subscription_end = now() + make_interval(days => p_days),
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

revoke all on function public.get_system_owner_admins_page(integer, integer) from public, anon;
revoke all on function public.renew_system_owner_admin_subscription(uuid, integer) from public, anon;
grant execute on function public.get_system_owner_admins_page(integer, integer) to authenticated;
grant execute on function public.renew_system_owner_admin_subscription(uuid, integer) to authenticated;
