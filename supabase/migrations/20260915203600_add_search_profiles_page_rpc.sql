create or replace function public.search_profiles_page(
  p_search text default '',
  p_role text default null,
  p_admin_id uuid default null,
  p_approved boolean default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns setof public.profiles
language sql
stable
set search_path = ''
as $$
  select p.*
  from public.profiles p
  where (p_role is null or p.role = p_role)
    and (p_admin_id is null or p.admin_id = p_admin_id)
    and (p_approved is null or p.approved = p_approved)
    and (
      nullif(trim(coalesce(p_search, '')), '') is null
      or lower(
        coalesce(p.name, '') || ' ' ||
        coalesce(p.father_name, '') || ' ' ||
        coalesce(p.grandfather_name, '') || ' ' ||
        coalesce(p.phone, '')
      ) like '%' || lower(trim(p_search)) || '%'
    )
  order by p.created_at desc, p.id desc
  limit greatest(1, least(coalesce(p_limit, 100), 500))
  offset greatest(coalesce(p_offset, 0), 0);
$$;

revoke all on function public.search_profiles_page(text, text, uuid, boolean, integer, integer) from public;
grant execute on function public.search_profiles_page(text, text, uuid, boolean, integer, integer) to authenticated;
