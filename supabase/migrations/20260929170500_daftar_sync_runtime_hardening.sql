-- Keep the 30-second Daftar path lightweight. Full reconciliation/cutover
-- is owned by the hourly database job so growing mirror tables cannot turn a
-- normal delta sync into a request-timeout failure.

create or replace function private.reconcile_daftar_sync_sources()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  r record;
  v_projection jsonb;
  v_integrity jsonb;
  v_cutover jsonb;
  v_deadletter jsonb;
  v_clean integer := 0;
  v_gap integer := 0;
  v_errors integer := 0;
  v_skipped_busy integer := 0;
begin
  for r in
    select id, lease_until
    from public.daftar_sync_sources
    where enabled=true
       or inbound_sync_enabled=true
       or outbound_sync_enabled=true
    order by created_at
  loop
    if r.lease_until is not null and r.lease_until > now() then
      v_skipped_busy := v_skipped_busy + 1;
      continue;
    end if;

    begin
      v_projection := private.reconcile_daftar_source(r.id);
      v_integrity := private.run_daftar_sync_reconciliation(r.id);

      if v_projection->>'status'='clean'
         and v_integrity->>'status'='healthy' then
        v_cutover := public.run_daftar_cutover_rehearsal(r.id);
        v_deadletter := public.resolve_daftar_recovered_dead_letters(r.id);

        if coalesce(v_cutover->>'status','fail')='pass' then
          v_clean := v_clean + 1;
        else
          v_gap := v_gap + 1;
          update public.daftar_sync_sources
          set reconciliation_status='gap',
              updated_at=now()
          where id=r.id;
        end if;
      else
        v_gap := v_gap + 1;
        update public.daftar_sync_sources
        set reconciliation_status='gap',
            updated_at=now()
        where id=r.id;
      end if;
    exception when others then
      v_errors := v_errors + 1;
      update public.daftar_sync_sources
      set reconciliation_status='gap',
          updated_at=now()
      where id=r.id;
    end;
  end loop;

  return jsonb_build_object(
    'clean_sources',v_clean,
    'gap_sources',v_gap,
    'error_sources',v_errors,
    'skipped_busy_sources',v_skipped_busy
  );
end;
$function$;

revoke all on function private.reconcile_daftar_sync_sources() from public, anon, authenticated;
grant execute on function private.reconcile_daftar_sync_sources() to service_role;

-- Defense in depth for the one authenticated SECURITY DEFINER reader that did
-- not previously assert a signed-in identity in its body.
create or replace function public.get_platform_operations_state()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_row public.platform_operations_config%rowtype;
  v_maintenance_effective boolean := false;
  v_announcement_effective boolean := false;
begin
  if v_uid is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

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
$function$;

revoke all on function public.get_platform_operations_state() from public, anon;
grant execute on function public.get_platform_operations_state() to authenticated, service_role;
