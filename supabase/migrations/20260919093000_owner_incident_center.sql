-- Owner Incident & Status Center.
-- Platform operational metadata only; no tenant business content is accessed.

create table if not exists public.platform_incidents (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  summary text not null default '',
  severity text not null default 'minor',
  status text not null default 'investigating',
  affected_component text not null default 'platform',
  public_visible boolean not null default true,
  starts_at timestamptz not null default now(),
  resolved_at timestamptz null,
  created_by uuid null references public.profiles(id) on delete set null,
  updated_by uuid null references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_incidents_severity_check
    check (severity in ('info','minor','major','critical')),
  constraint platform_incidents_status_check
    check (status in ('scheduled','investigating','identified','monitoring','resolved')),
  constraint platform_incidents_component_len
    check (char_length(affected_component) between 1 and 120),
  constraint platform_incidents_title_len
    check (char_length(title) between 1 and 180),
  constraint platform_incidents_summary_len
    check (char_length(summary) <= 4000)
);

create index if not exists platform_incidents_status_idx
  on public.platform_incidents(status, severity, starts_at desc);

alter table public.platform_incidents enable row level security;

revoke all on table public.platform_incidents from public, anon, authenticated;

create or replace function public.get_system_owner_incident_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_active integer := 0;
  v_critical integer := 0;
  v_scheduled integer := 0;
  v_resolved_30d integer := 0;
  v_latest timestamptz;
begin
  v_uid := private.require_system_owner();

  select
    count(*) filter (where status <> 'resolved')::integer,
    count(*) filter (where status <> 'resolved' and severity = 'critical')::integer,
    count(*) filter (
      where status = 'scheduled' and starts_at >= now()
    )::integer,
    count(*) filter (
      where status = 'resolved'
        and resolved_at >= now() - interval '30 days'
    )::integer,
    max(updated_at)
  into v_active, v_critical, v_scheduled, v_resolved_30d, v_latest
  from public.platform_incidents;

  return jsonb_build_object(
    'active_incidents', coalesce(v_active, 0),
    'critical_incidents', coalesce(v_critical, 0),
    'scheduled_incidents', coalesce(v_scheduled, 0),
    'resolved_30d', coalesce(v_resolved_30d, 0),
    'last_incident_update_at', v_latest,
    'checked_at', now()
  );
end;
$$;

create or replace function public.get_system_owner_incidents_page(
  p_page integer default 1,
  p_per_page integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_page integer := greatest(coalesce(p_page, 1), 1);
  v_per_page integer := least(greatest(coalesce(p_per_page, 50), 1), 100);
  v_total integer := 0;
  v_items jsonb := '[]'::jsonb;
begin
  v_uid := private.require_system_owner();

  select count(*)::integer into v_total
  from public.platform_incidents;

  select coalesce(jsonb_agg(item order by sort_rank, sort_time desc, sort_id desc), '[]'::jsonb)
    into v_items
  from (
    select
      case i.status
        when 'investigating' then 1
        when 'identified' then 2
        when 'monitoring' then 3
        when 'scheduled' then 4
        else 5
      end as sort_rank,
      i.updated_at as sort_time,
      i.id as sort_id,
      jsonb_build_object(
        'id', i.id,
        'title', i.title,
        'summary', i.summary,
        'severity', i.severity,
        'status', i.status,
        'affected_component', i.affected_component,
        'public_visible', i.public_visible,
        'starts_at', i.starts_at,
        'resolved_at', i.resolved_at,
        'created_at', i.created_at,
        'updated_at', i.updated_at
      ) as item
    from public.platform_incidents i
    order by
      case i.status
        when 'investigating' then 1
        when 'identified' then 2
        when 'monitoring' then 3
        when 'scheduled' then 4
        else 5
      end,
      i.updated_at desc,
      i.id desc
    offset (v_page - 1) * v_per_page
    limit v_per_page
  ) rows;

  return jsonb_build_object(
    'items', v_items,
    'total_items', v_total,
    'total_pages', greatest(1, ceil(v_total::numeric / v_per_page)::integer),
    'page', v_page
  );
end;
$$;

create or replace function public.create_system_owner_incident(
  p_title text,
  p_summary text,
  p_severity text,
  p_status text,
  p_affected_component text,
  p_public_visible boolean,
  p_starts_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_title text := trim(coalesce(p_title, ''));
  v_summary text := trim(coalesce(p_summary, ''));
  v_severity text := lower(trim(coalesce(p_severity, 'minor')));
  v_status text := lower(trim(coalesce(p_status, 'investigating')));
  v_component text := trim(coalesce(p_affected_component, 'platform'));
  v_row public.platform_incidents%rowtype;
begin
  v_uid := private.require_system_owner();

  if char_length(v_title) < 1 or char_length(v_title) > 180 then
    raise exception 'invalid_incident_title' using errcode = '22023';
  end if;
  if char_length(v_summary) > 4000 then
    raise exception 'incident_summary_too_long' using errcode = '22023';
  end if;
  if v_severity not in ('info','minor','major','critical') then
    raise exception 'invalid_incident_severity' using errcode = '22023';
  end if;
  if v_status not in ('scheduled','investigating','identified','monitoring','resolved') then
    raise exception 'invalid_incident_status' using errcode = '22023';
  end if;
  if char_length(v_component) < 1 or char_length(v_component) > 120 then
    raise exception 'invalid_incident_component' using errcode = '22023';
  end if;

  insert into public.platform_incidents (
    title, summary, severity, status, affected_component, public_visible,
    starts_at, resolved_at, created_by, updated_by
  ) values (
    v_title, v_summary, v_severity, v_status, v_component,
    coalesce(p_public_visible, true),
    coalesce(p_starts_at, now()),
    case when v_status = 'resolved' then now() else null end,
    v_uid, v_uid
  )
  returning * into v_row;

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    v_uid,
    null,
    'platform_incident_created',
    jsonb_build_object(
      'incident_id', v_row.id,
      'severity', v_row.severity,
      'status', v_row.status,
      'affected_component', v_row.affected_component,
      'public_visible', v_row.public_visible
    )
  );

  return jsonb_build_object(
    'id', v_row.id,
    'status', v_row.status,
    'severity', v_row.severity
  );
end;
$$;

create or replace function public.update_system_owner_incident(
  p_incident_id uuid,
  p_title text,
  p_summary text,
  p_severity text,
  p_status text,
  p_affected_component text,
  p_public_visible boolean,
  p_starts_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_title text := trim(coalesce(p_title, ''));
  v_summary text := trim(coalesce(p_summary, ''));
  v_severity text := lower(trim(coalesce(p_severity, 'minor')));
  v_status text := lower(trim(coalesce(p_status, 'investigating')));
  v_component text := trim(coalesce(p_affected_component, 'platform'));
  v_row public.platform_incidents%rowtype;
begin
  v_uid := private.require_system_owner();

  if p_incident_id is null then
    raise exception 'incident_id_required' using errcode = '22023';
  end if;
  if char_length(v_title) < 1 or char_length(v_title) > 180 then
    raise exception 'invalid_incident_title' using errcode = '22023';
  end if;
  if char_length(v_summary) > 4000 then
    raise exception 'incident_summary_too_long' using errcode = '22023';
  end if;
  if v_severity not in ('info','minor','major','critical') then
    raise exception 'invalid_incident_severity' using errcode = '22023';
  end if;
  if v_status not in ('scheduled','investigating','identified','monitoring','resolved') then
    raise exception 'invalid_incident_status' using errcode = '22023';
  end if;
  if char_length(v_component) < 1 or char_length(v_component) > 120 then
    raise exception 'invalid_incident_component' using errcode = '22023';
  end if;

  update public.platform_incidents
     set title = v_title,
         summary = v_summary,
         severity = v_severity,
         status = v_status,
         affected_component = v_component,
         public_visible = coalesce(p_public_visible, true),
         starts_at = coalesce(p_starts_at, starts_at),
         resolved_at = case
           when v_status = 'resolved' then coalesce(resolved_at, now())
           else null
         end,
         updated_by = v_uid,
         updated_at = now()
   where id = p_incident_id
   returning * into v_row;

  if not found then
    raise exception 'incident_not_found' using errcode = 'P0002';
  end if;

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    v_uid,
    null,
    'platform_incident_updated',
    jsonb_build_object(
      'incident_id', v_row.id,
      'severity', v_row.severity,
      'status', v_row.status,
      'affected_component', v_row.affected_component,
      'public_visible', v_row.public_visible
    )
  );

  return jsonb_build_object(
    'id', v_row.id,
    'status', v_row.status,
    'severity', v_row.severity,
    'resolved_at', v_row.resolved_at
  );
end;
$$;

create or replace function public.get_platform_incident_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_items jsonb := '[]'::jsonb;
begin
  if v_uid is null or not exists (
    select 1
    from public.profiles p
    where p.id = v_uid
      and p.active = true
      and p.approved = true
      and p.role in ('admin','employee')
  ) then
    raise exception 'platform_account_required' using errcode = '42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', i.id,
        'title', i.title,
        'summary', i.summary,
        'severity', i.severity,
        'status', i.status,
        'affected_component', i.affected_component,
        'starts_at', i.starts_at,
        'updated_at', i.updated_at
      )
      order by
        case i.severity
          when 'critical' then 1
          when 'major' then 2
          when 'minor' then 3
          else 4
        end,
        i.updated_at desc
    ),
    '[]'::jsonb
  )
  into v_items
  from public.platform_incidents i
  where i.public_visible = true
    and i.status <> 'resolved'
    and i.starts_at <= now()
  limit 10;

  return jsonb_build_object(
    'active', jsonb_array_length(v_items) > 0,
    'incidents', v_items,
    'checked_at', now()
  );
end;
$$;

revoke all on function public.get_system_owner_incident_overview()
  from public, anon;
revoke all on function public.get_system_owner_incidents_page(integer, integer)
  from public, anon;
revoke all on function public.create_system_owner_incident(text, text, text, text, text, boolean, timestamptz)
  from public, anon;
revoke all on function public.update_system_owner_incident(uuid, text, text, text, text, text, boolean, timestamptz)
  from public, anon;
revoke all on function public.get_platform_incident_status()
  from public, anon;

grant execute on function public.get_system_owner_incident_overview()
  to authenticated;
grant execute on function public.get_system_owner_incidents_page(integer, integer)
  to authenticated;
grant execute on function public.create_system_owner_incident(text, text, text, text, text, boolean, timestamptz)
  to authenticated;
grant execute on function public.update_system_owner_incident(uuid, text, text, text, text, text, boolean, timestamptz)
  to authenticated;
grant execute on function public.get_platform_incident_status()
  to authenticated;
