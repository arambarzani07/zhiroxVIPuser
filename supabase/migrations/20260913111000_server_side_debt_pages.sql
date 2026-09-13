create or replace function public.get_customer_debts_page(
  p_customer_id uuid,
  p_status text default null,
  p_page integer default 1,
  p_limit integer default 20
)
returns jsonb
language sql
stable
set search_path to ''
as $function$
  with settings as (
    select
      greatest(1, coalesce(p_page, 1)) as page_number,
      greatest(1, least(coalesce(p_limit, 20), 100)) as page_size
  ),
  matching as materialized (
    select d.*
    from public.debts d
    where d.customer_id = p_customer_id
      and d.is_deleted = false
      and (p_status is null or d.status = p_status)
  ),
  page_rows as (
    select d.*
    from matching d
    cross join settings s
    order by coalesce(d.custom_date, d.created_at) desc, d.id desc
    limit (select page_size from settings)
    offset (select (page_number - 1) * page_size from settings)
  )
  select jsonb_build_object(
    'items', coalesce(
      (select jsonb_agg(to_jsonb(d) order by coalesce(d.custom_date, d.created_at) desc, d.id desc)
       from page_rows d),
      '[]'::jsonb
    ),
    'total_count', (select count(*) from matching),
    'page', (select page_number from settings),
    'page_size', (select page_size from settings)
  );
$function$;

revoke all on function public.get_customer_debts_page(uuid, text, integer, integer)
  from public, anon;
grant execute on function public.get_customer_debts_page(uuid, text, integer, integer)
  to authenticated;
