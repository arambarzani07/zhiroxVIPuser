-- Preserve planned-cutover semantics after ZHIROX becomes primary.
-- 1) Read telemetry can identify ZHIROX-primary reads.
-- 2) Planned cutover does not falsely report an upstream outage.

do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'daftar_live_read_events_result_source_check'
      and conrelid = 'public.daftar_live_read_events'::regclass
  ) then
    alter table public.daftar_live_read_events
      drop constraint daftar_live_read_events_result_source_check;
  end if;

  alter table public.daftar_live_read_events
    add constraint daftar_live_read_events_result_source_check
    check (result_source in ('live', 'mirror', 'zhirox_primary', 'error'));
end;
$$;

create or replace function public.qualify_daftar_outage(p_source_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source public.daftar_sync_sources%rowtype;
  v_status text;
  v_suspected_at timestamptz;
  v_confirmed_at timestamptz;
  v_primary_reason text;
begin
  select *
    into v_source
  from public.daftar_sync_sources
  where id = p_source_id
    and legacy_user_id = 28
    and source_fingerprint = 'daftar-live-account-28-v1'
  for update;

  if v_source.id is null then
    raise exception 'daftar_source_not_available' using errcode = '42501';
  end if;

  if v_source.sync_mode = 'zhirox_primary' then
    select e.reason
      into v_primary_reason
    from public.daftar_source_mode_events e
    where e.sync_source_id = v_source.id
      and e.to_mode = 'zhirox_primary'
    order by e.created_at desc
    limit 1;

    if v_primary_reason = 'planned_primary_cutover_while_source_healthy' then
      v_status := 'healthy';
      v_suspected_at := null;
      v_confirmed_at := null;
    else
      v_status := 'confirmed';
      v_suspected_at := coalesce(
        v_source.outage_suspected_at,
        v_source.primary_activated_at,
        now()
      );
      v_confirmed_at := coalesce(
        v_source.outage_confirmed_at,
        v_source.primary_activated_at,
        now()
      );
    end if;
  elsif v_source.health_status = 'healthy'
        and v_source.consecutive_failures = 0 then
    v_status := 'healthy';
    v_suspected_at := null;
    v_confirmed_at := null;
  elsif v_source.outage_status = 'confirmed' then
    v_status := 'confirmed';
    v_suspected_at := coalesce(v_source.outage_suspected_at, now());
    v_confirmed_at := coalesce(v_source.outage_confirmed_at, now());
  elsif v_source.consecutive_failures >= 7
        and v_source.circuit_open_until is not null
        and v_source.circuit_open_until > now()
        and (
          v_source.last_success_at is null
          or v_source.last_success_at <= now() - interval '15 minutes'
        ) then
    v_status := 'confirmed';
    v_suspected_at := coalesce(v_source.outage_suspected_at, now());
    v_confirmed_at := coalesce(v_source.outage_confirmed_at, now());
  else
    v_status := 'suspected';
    v_suspected_at := coalesce(v_source.outage_suspected_at, now());
    v_confirmed_at := null;
  end if;

  update public.daftar_sync_sources
  set outage_status = v_status,
      outage_suspected_at = v_suspected_at,
      outage_confirmed_at = v_confirmed_at,
      updated_at = now()
  where id = v_source.id;

  return jsonb_build_object(
    'outage_status', v_status,
    'consecutive_failures', v_source.consecutive_failures,
    'last_success_at', v_source.last_success_at,
    'circuit_open_until', v_source.circuit_open_until,
    'outage_suspected_at', v_suspected_at,
    'outage_confirmed_at', v_confirmed_at,
    'primary_reason', v_primary_reason
  );
end;
$$;

revoke all on function public.qualify_daftar_outage(uuid)
  from public, anon, authenticated;
grant execute on function public.qualify_daftar_outage(uuid)
  to service_role;
