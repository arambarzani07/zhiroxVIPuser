-- Owner permission enforcement batch 4: Operations + Release/App Version.
-- get_platform_operations_state remains an authenticated client-status surface;
-- Owner mutations and release telemetry are permission-gated.

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
  v_uid uuid;
  v_old public.platform_operations_config%rowtype;
  v_permission_keys jsonb := '[]'::jsonb;
  v_config_changed boolean := false;
  v_announcement_changed boolean := false;
begin
  v_uid := private.require_system_owner();

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

  select * into v_old
  from public.platform_operations_config
  where id = 1;

  v_config_changed := not found
    or p_platform_status is distinct from v_old.platform_status
    or coalesce(p_maintenance_enabled, false) is distinct from v_old.maintenance_enabled
    or trim(coalesce(p_maintenance_message, '')) is distinct from v_old.maintenance_message
    or p_maintenance_starts_at is distinct from v_old.maintenance_starts_at
    or p_maintenance_ends_at is distinct from v_old.maintenance_ends_at;

  v_announcement_changed := not found
    or coalesce(p_announcement_enabled, false) is distinct from v_old.announcement_enabled
    or trim(coalesce(p_announcement_title, '')) is distinct from v_old.announcement_title
    or trim(coalesce(p_announcement_message, '')) is distinct from v_old.announcement_message
    or p_announcement_severity is distinct from v_old.announcement_severity
    or p_announcement_starts_at is distinct from v_old.announcement_starts_at
    or p_announcement_ends_at is distinct from v_old.announcement_ends_at;

  if v_config_changed then
    perform private.assert_system_owner_permission(
      'owner_refresh_platform_config', 'platform', null
    );
    v_permission_keys := v_permission_keys || jsonb_build_array('owner_refresh_platform_config');
  end if;

  if v_announcement_changed then
    perform private.assert_system_owner_permission(
      'owner_publish_update_message', 'platform', null
    );
    v_permission_keys := v_permission_keys || jsonb_build_array('owner_publish_update_message');
  end if;

  if jsonb_array_length(v_permission_keys) = 0 then
    perform private.assert_system_owner_permission(
      'owner_view_platform_dashboard', 'platform', null
    );
    v_permission_keys := jsonb_build_array('owner_view_platform_dashboard');
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
      'permission_keys', v_permission_keys,
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

create or replace function public.get_system_owner_release_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_min integer := 0;
  v_devices integer := 0;
  v_known integer := 0;
  v_outdated integer := 0;
  v_unknown integer := 0;
  v_outdated_tenants integer := 0;
  v_policies jsonb := '[]'::jsonb;
begin
  perform private.assert_system_owner_permission(
    'owner_view_app_versions', 'platform', null
  );

  select coalesce(s.minimum_build, 0)
    into v_user_min
  from public.app_update_settings s
  where s.edition = 'user';

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'edition', s.edition,
        'mandatory', s.mandatory,
        'notes', coalesce(s.notes, ''),
        'rollout_percent', s.rollout_percent,
        'minimum_build', s.minimum_build,
        'updated_at', s.updated_at
      )
      order by s.edition
    ),
    '[]'::jsonb
  )
  into v_policies
  from public.app_update_settings s
  where s.edition in ('owner', 'user');

  with active_devices as (
    select
      d.admin_id,
      case
        when d.app_version ~ '^[0-9]{1,9}$' then d.app_version::integer
        else null
      end as build_number
    from public.platform_admin_devices d
    where d.status = 'approved'
      and d.last_seen_at >= now() - interval '30 days'
  )
  select
    count(*)::integer,
    count(*) filter (where build_number is not null)::integer,
    count(*) filter (
      where build_number is not null and build_number < v_user_min
    )::integer,
    count(*) filter (where build_number is null)::integer,
    count(distinct admin_id) filter (
      where build_number is not null and build_number < v_user_min
    )::integer
  into v_devices, v_known, v_outdated, v_unknown, v_outdated_tenants
  from active_devices;

  return jsonb_build_object(
    'policies', v_policies,
    'active_devices_30d', coalesce(v_devices, 0),
    'known_build_devices_30d', coalesce(v_known, 0),
    'outdated_devices_30d', coalesce(v_outdated, 0),
    'unknown_build_devices_30d', coalesce(v_unknown, 0),
    'outdated_tenants_30d', coalesce(v_outdated_tenants, 0),
    'user_minimum_build', coalesce(v_user_min, 0),
    'checked_at', now()
  );
end;
$$;

create or replace function public.get_system_owner_release_compliance_page(
  p_page integer default 1,
  p_per_page integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_page integer := greatest(coalesce(p_page, 1), 1);
  v_per_page integer := least(greatest(coalesce(p_per_page, 30), 1), 100);
  v_user_min integer := 0;
  v_total integer := 0;
  v_items jsonb := '[]'::jsonb;
begin
  perform private.assert_system_owner_permission(
    'owner_view_app_versions', 'platform', null
  );
  perform private.assert_system_owner_permission(
    'owner_view_admin_profile', 'admin', null
  );
  perform private.assert_system_owner_permission(
    'owner_view_admin_devices', 'admin', null
  );
  perform private.assert_system_owner_permission(
    'owner_view_admin_status', 'admin', null
  );

  select coalesce(s.minimum_build, 0)
    into v_user_min
  from public.app_update_settings s
  where s.edition = 'user';

  select count(*)::integer
    into v_total
  from public.profiles a
  where a.role = 'admin'
    and a.is_system_owner = false;

  select coalesce(jsonb_agg(item order by sort_rank, sort_created desc, sort_id desc), '[]'::jsonb)
    into v_items
  from (
    select
      case compliance_state
        when 'outdated' then 1
        when 'review' then 2
        when 'no_telemetry' then 3
        else 4
      end as sort_rank,
      created_at as sort_created,
      id as sort_id,
      jsonb_build_object(
        'id', id,
        'market_name', market_name,
        'admin_name', admin_name,
        'phone', phone,
        'active', active,
        'approved', approved,
        'minimum_build', v_user_min,
        'active_device_count_30d', active_device_count_30d,
        'known_build_device_count_30d', known_build_device_count_30d,
        'outdated_device_count_30d', outdated_device_count_30d,
        'unknown_build_device_count_30d', unknown_build_device_count_30d,
        'latest_build', latest_build,
        'oldest_build', oldest_build,
        'latest_seen_at', latest_seen_at,
        'compliance_state', compliance_state
      ) as item
    from (
      select
        a.id,
        a.created_at,
        coalesce(a.market_name, '') as market_name,
        coalesce(a.name, '') as admin_name,
        coalesce(a.phone, '') as phone,
        a.active,
        a.approved,
        coalesce(dev.active_device_count_30d, 0) as active_device_count_30d,
        coalesce(dev.known_build_device_count_30d, 0) as known_build_device_count_30d,
        coalesce(dev.outdated_device_count_30d, 0) as outdated_device_count_30d,
        coalesce(dev.unknown_build_device_count_30d, 0) as unknown_build_device_count_30d,
        dev.latest_build,
        dev.oldest_build,
        dev.latest_seen_at,
        case
          when coalesce(dev.active_device_count_30d, 0) = 0 then 'no_telemetry'
          when coalesce(dev.outdated_device_count_30d, 0) > 0 then 'outdated'
          when coalesce(dev.unknown_build_device_count_30d, 0) > 0 then 'review'
          else 'current'
        end as compliance_state
      from public.profiles a
      left join lateral (
        select
          count(*)::integer as active_device_count_30d,
          count(*) filter (where parsed_build is not null)::integer
            as known_build_device_count_30d,
          count(*) filter (
            where parsed_build is not null and parsed_build < v_user_min
          )::integer as outdated_device_count_30d,
          count(*) filter (where parsed_build is null)::integer
            as unknown_build_device_count_30d,
          max(parsed_build) as latest_build,
          min(parsed_build) as oldest_build,
          max(last_seen_at) as latest_seen_at
        from (
          select
            d.last_seen_at,
            case
              when d.app_version ~ '^[0-9]{1,9}$'
                then d.app_version::integer
              else null
            end as parsed_build
          from public.platform_admin_devices d
          where d.admin_id = a.id
            and d.status = 'approved'
            and d.last_seen_at >= now() - interval '30 days'
        ) parsed
      ) dev on true
      where a.role = 'admin'
        and a.is_system_owner = false
    ) tenant_rows
    order by
      case compliance_state
        when 'outdated' then 1
        when 'review' then 2
        when 'no_telemetry' then 3
        else 4
      end,
      created_at desc,
      id desc
    offset (v_page - 1) * v_per_page
    limit v_per_page
  ) rows;

  return jsonb_build_object(
    'items', v_items,
    'total_items', v_total,
    'total_pages', greatest(1, ceil(v_total::numeric / v_per_page)::integer),
    'page', v_page,
    'minimum_build', v_user_min
  );
end;
$$;

create or replace function public.set_system_owner_release_policy(
  p_edition text,
  p_mandatory boolean,
  p_notes text,
  p_rollout_percent integer,
  p_minimum_build integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_edition text := lower(trim(coalesce(p_edition, '')));
  v_notes text := left(trim(coalesce(p_notes, '')), 1000);
  v_rollout integer := coalesce(p_rollout_percent, 100);
  v_minimum integer := coalesce(p_minimum_build, 0);
  v_old_mandatory boolean := false;
  v_old_notes text := '';
  v_old_rollout integer := 100;
  v_old_minimum integer := 0;
  v_permission_keys jsonb := '[]'::jsonb;
begin
  v_uid := private.require_system_owner();

  if v_edition not in ('owner','user') then
    raise exception 'invalid_release_edition' using errcode = '22023';
  end if;
  if v_rollout < 0 or v_rollout > 100 then
    raise exception 'invalid_rollout_percent' using errcode = '22023';
  end if;
  if v_minimum < 0 or v_minimum > 99999999 then
    raise exception 'invalid_minimum_build' using errcode = '22023';
  end if;

  select
    coalesce(s.mandatory, false),
    coalesce(s.notes, ''),
    coalesce(s.rollout_percent, 100),
    coalesce(s.minimum_build, 0)
  into v_old_mandatory, v_old_notes, v_old_rollout, v_old_minimum
  from public.app_update_settings s
  where s.edition = v_edition;

  if not found then
    v_old_mandatory := false;
    v_old_notes := '';
    v_old_rollout := 100;
    v_old_minimum := 0;
  end if;

  if coalesce(p_mandatory, false) is distinct from v_old_mandatory then
    if coalesce(p_mandatory, false) then
      perform private.assert_system_owner_permission(
        'owner_force_app_update', 'platform', null
      );
      v_permission_keys := v_permission_keys || jsonb_build_array('owner_force_app_update');
    else
      perform private.assert_system_owner_permission(
        'owner_disable_forced_update', 'platform', null
      );
      v_permission_keys := v_permission_keys || jsonb_build_array('owner_disable_forced_update');
    end if;
  end if;

  if v_minimum is distinct from v_old_minimum then
    perform private.assert_system_owner_permission(
      'owner_set_minimum_app_version', 'platform', null
    );
    v_permission_keys := v_permission_keys || jsonb_build_array('owner_set_minimum_app_version');

    if v_minimum > v_old_minimum then
      perform private.assert_system_owner_permission(
        'owner_block_old_app_version', 'platform', null
      );
      v_permission_keys := v_permission_keys || jsonb_build_array('owner_block_old_app_version');
    else
      perform private.assert_system_owner_permission(
        'owner_allow_old_app_version', 'platform', null
      );
      v_permission_keys := v_permission_keys || jsonb_build_array('owner_allow_old_app_version');
    end if;
  end if;

  if v_notes is distinct from v_old_notes then
    perform private.assert_system_owner_permission(
      'owner_publish_update_message', 'platform', null
    );
    v_permission_keys := v_permission_keys || jsonb_build_array('owner_publish_update_message');
  end if;

  if v_rollout is distinct from v_old_rollout then
    perform private.assert_system_owner_permission(
      'owner_refresh_platform_config', 'platform', null
    );
    v_permission_keys := v_permission_keys || jsonb_build_array('owner_refresh_platform_config');
  end if;

  if jsonb_array_length(v_permission_keys) = 0 then
    perform private.assert_system_owner_permission(
      'owner_view_app_versions', 'platform', null
    );
    v_permission_keys := jsonb_build_array('owner_view_app_versions');
  end if;

  insert into public.app_update_settings (
    edition, mandatory, notes, rollout_percent, minimum_build, updated_at, updated_by
  ) values (
    v_edition, coalesce(p_mandatory, false), v_notes, v_rollout,
    v_minimum, now(), v_uid
  )
  on conflict (edition) do update
    set mandatory = excluded.mandatory,
        notes = excluded.notes,
        rollout_percent = excluded.rollout_percent,
        minimum_build = excluded.minimum_build,
        updated_at = now(),
        updated_by = v_uid;

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    v_uid,
    null,
    'release_policy_changed',
    jsonb_build_object(
      'permission_keys', v_permission_keys,
      'edition', v_edition,
      'mandatory', coalesce(p_mandatory, false),
      'previous_mandatory', v_old_mandatory,
      'rollout_percent', v_rollout,
      'previous_rollout_percent', v_old_rollout,
      'minimum_build', v_minimum,
      'previous_minimum_build', v_old_minimum
    )
  );

  return jsonb_build_object(
    'edition', v_edition,
    'mandatory', coalesce(p_mandatory, false),
    'notes', v_notes,
    'rollout_percent', v_rollout,
    'minimum_build', v_minimum,
    'permission_keys', v_permission_keys
  );
end;
$$;

revoke all on function public.set_system_owner_operations_state(
  text, boolean, text, timestamptz, timestamptz,
  boolean, text, text, text, timestamptz, timestamptz
) from public, anon;
revoke all on function public.get_system_owner_release_overview()
  from public, anon;
revoke all on function public.get_system_owner_release_compliance_page(integer, integer)
  from public, anon;
revoke all on function public.set_system_owner_release_policy(text, boolean, text, integer, integer)
  from public, anon;

grant execute on function public.set_system_owner_operations_state(
  text, boolean, text, timestamptz, timestamptz,
  boolean, text, text, text, timestamptz, timestamptz
) to authenticated;
grant execute on function public.get_system_owner_release_overview()
  to authenticated;
grant execute on function public.get_system_owner_release_compliance_page(integer, integer)
  to authenticated;
grant execute on function public.set_system_owner_release_policy(text, boolean, text, integer, integer)
  to authenticated;
