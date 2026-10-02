create or replace function public.get_system_owner_autopilot_overview_v2_service(
  p_search text default '',
  p_health text default 'all',
  p_page integer default 1,
  p_per_page integer default 30
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_items jsonb := '[]'::jsonb;
begin
  v_base := public.get_system_owner_autopilot_overview_service(
    p_search,
    p_health,
    p_page,
    p_per_page
  );

  select coalesce(
    jsonb_agg(
      (e.item - 'recent_issues') || jsonb_build_object(
        'issue_count',
        case
          when jsonb_typeof(e.item->'recent_issues') = 'array'
            then jsonb_array_length(e.item->'recent_issues')
          else 0
        end
      )
      order by e.ord
    ),
    '[]'::jsonb
  )
  into v_items
  from jsonb_array_elements(coalesce(v_base->'items', '[]'::jsonb))
       with ordinality as e(item, ord);

  return jsonb_set(v_base, '{items}', v_items, true);
end;
$function$;

revoke all on function public.get_system_owner_autopilot_overview_v2_service(text,text,integer,integer) from public;
revoke all on function public.get_system_owner_autopilot_overview_v2_service(text,text,integer,integer) from anon;
revoke all on function public.get_system_owner_autopilot_overview_v2_service(text,text,integer,integer) from authenticated;
grant execute on function public.get_system_owner_autopilot_overview_v2_service(text,text,integer,integer) to service_role;
