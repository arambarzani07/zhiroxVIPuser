-- Platform Operations Center.
-- Global platform status, maintenance scheduling and system announcements.
-- Strict privacy boundary: no tenant business content is queried or stored.

create table if not exists public.platform_operations_config (
  id smallint primary key default 1 check (id = 1),
  platform_status text not null default 'operational'
    check (platform_status in ('operational','degraded','partial_outage','maintenance')),
  maintenance_enabled boolean not null default false,
  maintenance_message text not null default ''
    check (char_length(maintenance_message) <= 1000),
  maintenance_starts_at timestamptz,
  maintenance_ends_at timestamptz,
  announcement_enabled boolean not null default false,
  announcement_title text not null default ''
    check (char_length(announcement_title) <= 160),
  announcement_message text not null default ''
    check (char_length(announcement_message) <= 1500),
  announcement_severity text not null default 'info'
    check (announcement_severity in ('info','success','warning','critical')),
  announcement_starts_at timestamptz,
  announcement_ends_at timestamptz,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null,
  check (
    maintenance_starts_at is null
    or maintenance_ends_at is null
    or maintenance_ends_at > maintenance_starts_at
  ),
  check (
    announcement_starts_at is null
    or announcement_ends_at is null
    or announcement_ends_at > announcement_starts_at
  )
);

insert into public.platform_operations_config(id)
values (1)
on conflict (id) do nothing;

alter table public.platform_operations_config enable row level security;

revoke all privileges on table public.platform_operations_config
  from public, anon, authenticated;
grant select, insert, update, delete on table public.platform_operations_config
  to service_role;

create or replace function public.get_platform_operations_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row public.platform_operations_config%rowtype;
  v_maintenance_effective boolean := false;
  v_announcement_effective boolean := false;
begin
  select *
    into v_row
  from public.platform_operations_config
  where id = 1;

  if not found then
    return jsonb_build_object(
      'platform_status', 'operational',
      'maintenance_enabled', false,
      'maintenance_effective', false,
      'maintenance_message', '',
      'maintenance_starts_at', null,
      'maintenance_ends_at', null,
      'announcement_enabled', false,
      'announcement_effective', false,
      'announcement_title', '',
      'announcement_message', '',
      'announcement_severity', 'info',
      'announcement_starts_at', null,
      'announcement_ends_at', null,
      'updated_at', null
    );
  end if;

  v_maintenance_effective :=
    v_row.maintenance_enabled
    and (v_row.maintenance_starts_at is null or v_row.maintenance_starts_at <= now())
    and (v_row.maintenance_ends_at is null or v_row.maintenance_ends_at > now());

  v_announcement_effective :=
    v_row.announcement_enabled
    and (v_row.announcement_starts_at is null or v_row.announcement_starts_at <= now())
    and (v_row.announcement_ends_at is null or v_row.announcement_ends_at > now());

  return jsonb_build_object(
    'platform_status', v_row.platform_status,
    'maintenance_enabled', v_row.maintenance_enabled,
    'maintenance_effective', v_maintenance_effective,
    'maintenance_message', v_row.maintenance_message,
    'maintenance_starts_at', v_row.maintenance_starts_at,
    'maintenance_ends_at', v_row.maintenance_ends_at,
    'announcement_enabled', v_row.announcement_enabled,
    'announcement_effective', v_announcement_effective,
    'announcement_title', v_row.announcement_title,
    'announcement_message', v_row.announcement_message,
    'announcement_severity', v_row.announcement_severity,
    'announcement_starts_at', v_row.announcement_starts_at,
    'announcement_ends_at', v_row.announcement_ends_at,
    'updated_at', v_row.updated_at
  );
end;
$$;

create or replace function public.set_system_owner_operations_state(
  p_platform_status text,
  p_maintenance_enabled boolean,
  p_maintenance_message text default '',
  p_maintenance_starts_at timestamptz default null,
  p_maintenance_ends_at timestamptz default null,
  p_announcement_enabled boolean default false,
  p_announcement_title text default '',
  p_announcement_message text default '',
  p_announcement_severity text default 'info',
  p_announcement_starts_at timestamptz default null,
  p_announcement_ends_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not exists (
    select 1
    from public.profiles p
    where p.id = v_uid
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'system_owner_required' using errcode = '42501';
  end if;

  if p_platform_status not in ('operational','degraded','partial_outage','maintenance')
     or p_announcement_severity not in ('info','success','warning','critical')
     or char_length(coalesce(p_maintenance_message, '')) > 1000
     or char_length(coalesce(p_announcement_title, '')) > 160
     or char_length(coalesce(p_announcement_message, '')) > 1500
     or (
       p_maintenance_starts_at is not null
       and p_maintenance_ends_at is not null
       and p_maintenance_ends_at <= p_maintenance_starts_at
     )
     or (
       p_announcement_starts_at is not null
       and p_announcement_ends_at is not null
       and p_announcement_ends_at <= p_announcement_starts_at
     )
  then
    raise exception 'invalid_operations_state' using errcode = '22023';
  end if;

  if p_maintenance_enabled
     and trim(coalesce(p_maintenance_message, '')) = '' then
    raise exception 'maintenance_message_required' using errcode = '22023';
  end if;

  if p_announcement_enabled
     and (
       trim(coalesce(p_announcement_title, '')) = ''
       or trim(coalesce(p_announcement_message, '')) = ''
     )
  then
    raise exception 'announcement_content_required' using errcode = '22023';
  end if;

  insert into public.platform_operations_config (
    id,
    platform_status,
    maintenance_enabled,
    maintenance_message,
    maintenance_starts_at,
    maintenance_ends_at,
    announcement_enabled,
    announcement_title,
    announcement_message,
    announcement_severity,
    announcement_starts_at,
    announcement_ends_at,
    updated_at,
    updated_by
  ) values (
    1,
    p_platform_status,
    coalesce(p_maintenance_enabled, false),
    trim(coalesce(p_maintenance_message, '')),
    p_maintenance_starts_at,
    p_maintenance_ends_at,
    coalesce(p_announcement_enabled, false),
    trim(coalesce(p_announcement_title, '')),
    trim(coalesce(p_announcement_message, '')),
    p_announcement_severity,
    p_announcement_starts_at,
    p_announcement_ends_at,
    now(),
    v_uid
  )
  on conflict (id) do update
    set platform_status = excluded.platform_status,
        maintenance_enabled = excluded.maintenance_enabled,
        maintenance_message = excluded.maintenance_message,
        maintenance_starts_at = excluded.maintenance_starts_at,
        maintenance_ends_at = excluded.maintenance_ends_at,
        announcement_enabled = excluded.announcement_enabled,
        announcement_title = excluded.announcement_title,
        announcement_message = excluded.announcement_message,
        announcement_severity = excluded.announcement_severity,
        announcement_starts_at = excluded.announcement_starts_at,
        announcement_ends_at = excluded.announcement_ends_at,
        updated_at = now(),
        updated_by = v_uid;

  insert into public.owner_platform_audit (
    actor_id,
    target_admin_id,
    action,
    metadata
  ) values (
    v_uid,
    null,
    'platform_operations_changed',
    jsonb_build_object(
      'platform_status', p_platform_status,
      'maintenance_enabled', coalesce(p_maintenance_enabled, false),
      'maintenance_scheduled', p_maintenance_starts_at is not null or p_maintenance_ends_at is not null,
      'announcement_enabled', coalesce(p_announcement_enabled, false),
      'announcement_severity', p_announcement_severity,
      'announcement_scheduled', p_announcement_starts_at is not null or p_announcement_ends_at is not null
    )
  );

  return public.get_platform_operations_state();
end;
$$;

revoke all on function public.get_platform_operations_state()
  from public;
revoke all on function public.set_system_owner_operations_state(
  text, boolean, text, timestamptz, timestamptz,
  boolean, text, text, text, timestamptz, timestamptz
) from public, anon;

grant execute on function public.get_platform_operations_state()
  to anon, authenticated;
grant execute on function public.set_system_owner_operations_state(
  text, boolean, text, timestamptz, timestamptz,
  boolean, text, text, text, timestamptz, timestamptz
) to authenticated;
