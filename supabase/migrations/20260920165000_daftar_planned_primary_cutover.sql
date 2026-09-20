-- Planned, guarded Daftar Qarz -> ZHIROX primary cutover.
-- This is intentionally separate from emergency failover. It is allowed only
-- while Daftar is healthy and the mirror/reconciliation/rehearsal gates pass.

create or replace function public.activate_zhirox_primary_planned(
  p_source_id uuid,
  p_confirmation text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source public.daftar_sync_sources%rowtype;
  v_live_job_id bigint;
begin
  if p_confirmation is distinct from 'PLANNED_ACTIVATE_ZHIROX_PRIMARY_ACCOUNT_28' then
    raise exception 'invalid_planned_cutover_confirmation'
      using errcode = '42501';
  end if;

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
    return jsonb_build_object(
      'activated', true,
      'already_primary', true,
      'activated_at', v_source.primary_activated_at
    );
  end if;

  if v_source.sync_mode <> 'mirror'
     or v_source.enabled is distinct from true then
    raise exception 'daftar_planned_cutover_requires_active_mirror'
      using errcode = '42501';
  end if;

  -- Planned cutover is for a healthy source. Emergency failover remains a
  -- separate path and still requires outage qualification.
  if v_source.health_status <> 'healthy'
     or v_source.consecutive_failures <> 0
     or v_source.outage_status <> 'healthy' then
    raise exception 'daftar_planned_cutover_requires_healthy_source'
      using errcode = '42501';
  end if;

  if v_source.last_success_at is null
     or v_source.last_success_at < now() - interval '5 minutes' then
    raise exception 'daftar_planned_cutover_source_not_fresh'
      using errcode = '42501';
  end if;

  -- Recompute financial safety immediately before changing source of truth.
  perform public.run_daftar_cutover_rehearsal(v_source.id);
  perform public.refresh_daftar_failover_readiness(v_source.id);

  select *
    into v_source
  from public.daftar_sync_sources
  where id = p_source_id
  for update;

  if not v_source.failover_ready
     or v_source.last_safe_cutover_at is null
     or v_source.reconciliation_status <> 'clean'
     or v_source.reconciliation_missing_contacts <> 0
     or v_source.reconciliation_missing_transactions <> 0
     or v_source.cutover_rehearsal_status <> 'pass'
     or v_source.cutover_rehearsal_mismatches <> 0 then
    raise exception 'daftar_planned_cutover_not_ready'
      using errcode = '42501';
  end if;

  -- Re-check source health/freshness after the rehearsal/readiness work.
  if v_source.health_status <> 'healthy'
     or v_source.consecutive_failures <> 0
     or v_source.outage_status <> 'healthy'
     or v_source.last_success_at is null
     or v_source.last_success_at < now() - interval '5 minutes' then
    raise exception 'daftar_planned_cutover_health_changed'
      using errcode = '42501';
  end if;

  perform set_config('zhirox.daftar_sync_unlock', 'on', true);

  update public.daftar_sync_sources
  set sync_mode = 'zhirox_primary',
      enabled = false,
      live_read_mode = 'off',
      primary_activated_at = now(),
      updated_at = now()
  where id = v_source.id;

  select jobid
    into v_live_job_id
  from cron.job
  where jobname = 'daftar-live-sync-account-28'
  limit 1;

  if v_live_job_id is not null then
    perform cron.alter_job(
      job_id => v_live_job_id,
      active => false
    );
  end if;

  insert into public.daftar_source_mode_events(
    sync_source_id,
    from_mode,
    to_mode,
    reason,
    snapshot
  ) values (
    v_source.id,
    'mirror',
    'zhirox_primary',
    'planned_primary_cutover_while_source_healthy',
    jsonb_build_object(
      'last_safe_cutover_at', v_source.last_safe_cutover_at,
      'last_safe_contact_id', v_source.last_safe_contact_id,
      'last_safe_transaction_id', v_source.last_safe_transaction_id,
      'last_safe_mirror_contacts', v_source.last_safe_mirror_contacts,
      'last_safe_mirror_transactions', v_source.last_safe_mirror_transactions,
      'health_status', v_source.health_status,
      'consecutive_failures', v_source.consecutive_failures,
      'outage_status', v_source.outage_status,
      'last_success_at', v_source.last_success_at,
      'reconciliation_status', v_source.reconciliation_status,
      'cutover_rehearsal_status', v_source.cutover_rehearsal_status,
      'cutover_rehearsal_mismatches', v_source.cutover_rehearsal_mismatches
    )
  );

  return jsonb_build_object(
    'activated', true,
    'already_primary', false,
    'previous_mode', 'mirror',
    'new_mode', 'zhirox_primary',
    'planned', true
  );
end;
$$;

revoke all on function public.activate_zhirox_primary_planned(uuid,text)
  from public, anon, authenticated;
grant execute on function public.activate_zhirox_primary_planned(uuid,text)
  to service_role;
