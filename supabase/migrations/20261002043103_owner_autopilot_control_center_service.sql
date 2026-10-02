create or replace function public.get_system_owner_autopilot_overview_service(
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
  v_search text := lower(btrim(coalesce(p_search, '')));
  v_health text := lower(btrim(coalesce(p_health, 'all')));
  v_page integer := greatest(coalesce(p_page, 1), 1);
  v_per_page integer := least(greatest(coalesce(p_per_page, 30), 1), 100);
  v_offset integer;
  v_all jsonb := '[]'::jsonb;
  v_filtered jsonb := '[]'::jsonb;
  v_page_items jsonb := '[]'::jsonb;
  v_item jsonb;
  v_dashboard jsonb;
  v_status text;
  v_total integer := 0;
  v_total_filtered integer := 0;
  v_healthy integer := 0;
  v_degraded integer := 0;
  v_attention integer := 0;
  v_enabled integer := 0;
  v_disabled integer := 0;
  v_linked bigint := 0;
  v_queue bigint := 0;
  v_retrying bigint := 0;
  v_failed bigint := 0;
  v_dead bigint := 0;
  v_risk_total bigint := 0;
  v_risk_high bigint := 0;
  v_risk_critical bigint := 0;
  r record;
begin
  if v_health not in ('all','healthy','degraded','attention') then
    raise exception 'invalid_health_filter' using errcode = '22023';
  end if;

  v_offset := (v_page - 1) * v_per_page;

  for r in
    select p.id, p.market_name, p.name, p.active, p.approved
    from public.profiles p
    where p.role = 'admin'
      and p.active = true
      and p.approved = true
      and coalesce(p.is_system_owner, false) = false
    order by lower(coalesce(nullif(btrim(p.market_name), ''), p.name, '')), p.id
  loop
    v_dashboard := public.get_tenant_autopilot_dashboard_service(r.id);
    v_status := coalesce(v_dashboard #>> '{health,status}', 'healthy');

    v_item := jsonb_build_object(
      'market_id', r.id,
      'market_name', coalesce(nullif(btrim(r.market_name), ''), nullif(btrim(r.name), ''), 'مارکێت'),
      'admin_name', coalesce(r.name, ''),
      'health', coalesce(v_dashboard->'health', '{}'::jsonb),
      'autopilot', coalesce(v_dashboard->'autopilot', '{}'::jsonb),
      'telegram', coalesce(v_dashboard->'telegram', '{}'::jsonb),
      'receipts', coalesce(v_dashboard->'receipts', '{}'::jsonb),
      'statements', coalesce(v_dashboard->'statements', '{}'::jsonb),
      'notifications', coalesce(v_dashboard->'notifications', '{}'::jsonb),
      'risk', coalesce(v_dashboard->'risk', '{}'::jsonb),
      'recent_issues', coalesce(v_dashboard->'recent_issues', '[]'::jsonb)
    );

    v_all := v_all || jsonb_build_array(v_item);
    v_total := v_total + 1;
    if v_status = 'attention' then
      v_attention := v_attention + 1;
    elsif v_status = 'degraded' then
      v_degraded := v_degraded + 1;
    else
      v_healthy := v_healthy + 1;
    end if;

    if coalesce((v_dashboard #>> '{autopilot,enabled}')::boolean, false) then
      v_enabled := v_enabled + 1;
    else
      v_disabled := v_disabled + 1;
    end if;

    v_linked := v_linked + coalesce((v_dashboard #>> '{telegram,linked_customers}')::bigint, 0);
    v_queue := v_queue + coalesce((v_dashboard #>> '{health,active_queue}')::bigint, 0);
    v_retrying := v_retrying + coalesce((v_dashboard #>> '{health,retrying}')::bigint, 0);
    v_failed := v_failed + coalesce((v_dashboard #>> '{health,failed}')::bigint, 0);
    v_dead := v_dead + coalesce((v_dashboard #>> '{health,dead_letter}')::bigint, 0);
    v_risk_total := v_risk_total + coalesce((v_dashboard #>> '{risk,total}')::bigint, 0);
    v_risk_high := v_risk_high + coalesce((v_dashboard #>> '{risk,high}')::bigint, 0);
    v_risk_critical := v_risk_critical + coalesce((v_dashboard #>> '{risk,critical}')::bigint, 0);

    if (v_health = 'all' or v_status = v_health)
       and (v_search = ''
            or lower(coalesce(r.market_name, '')) like '%' || v_search || '%'
            or lower(coalesce(r.name, '')) like '%' || v_search || '%') then
      v_filtered := v_filtered || jsonb_build_array(v_item);
      v_total_filtered := v_total_filtered + 1;
    end if;
  end loop;

  select coalesce(
    jsonb_agg(
      x.item
      order by
        case coalesce(x.item #>> '{health,status}', 'healthy')
          when 'attention' then 0
          when 'degraded' then 1
          else 2
        end,
        lower(coalesce(x.item->>'market_name','')),
        x.item->>'market_id'
    ),
    '[]'::jsonb
  )
  into v_page_items
  from (
    select e.item
    from jsonb_array_elements(v_filtered) with ordinality as e(item, ord)
    order by
      case coalesce(e.item #>> '{health,status}', 'healthy')
        when 'attention' then 0
        when 'degraded' then 1
        else 2
      end,
      lower(coalesce(e.item->>'market_name','')),
      e.item->>'market_id'
    offset v_offset
    limit v_per_page
  ) x;

  return jsonb_build_object(
    'generated_at', now(),
    'overview', jsonb_build_object(
      'total_markets', v_total,
      'healthy', v_healthy,
      'degraded', v_degraded,
      'attention', v_attention,
      'autopilot_enabled', v_enabled,
      'autopilot_disabled', v_disabled,
      'telegram_linked_customers', v_linked,
      'active_queue', v_queue,
      'retrying', v_retrying,
      'failed', v_failed,
      'dead_letter', v_dead,
      'risk_total', v_risk_total,
      'risk_high', v_risk_high,
      'risk_critical', v_risk_critical
    ),
    'filters', jsonb_build_object('search', v_search, 'health', v_health),
    'page', v_page,
    'per_page', v_per_page,
    'total_items', v_total_filtered,
    'total_pages', case
      when v_total_filtered = 0 then 0
      else ceil(v_total_filtered::numeric / v_per_page)::integer
    end,
    'items', v_page_items
  );
end;
$function$;

revoke all on function public.get_system_owner_autopilot_overview_service(text,text,integer,integer) from public;
revoke all on function public.get_system_owner_autopilot_overview_service(text,text,integer,integer) from anon;
revoke all on function public.get_system_owner_autopilot_overview_service(text,text,integer,integer) from authenticated;
grant execute on function public.get_system_owner_autopilot_overview_service(text,text,integer,integer) to service_role;
