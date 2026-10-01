create or replace function private.refresh_all_customer_risks()
returns integer
language plpgsql
set search_path = ''
as $$
declare
  r record;
  v_count integer := 0;
begin
  for r in
    select p.id
    from public.profiles p
    join public.market_autopilot_settings s on s.market_id = p.admin_id
    where p.role = 'customer'
      and p.active = true
      and p.approved = true
      and s.enabled = true
      and s.mode <> 'manual'
      and s.risk_enabled = true
    order by p.id
  loop
    perform private.recalculate_customer_risk(r.id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create or replace function private.recover_stale_autopilot_processing()
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_jobs integer := 0;
  v_telegram integer := 0;
begin
  update private.autopilot_jobs j
  set status = case when j.attempt_count >= j.max_attempts then 'dead_letter' else 'retrying' end,
      run_after = case when j.attempt_count >= j.max_attempts then j.run_after else now() end,
      last_error = left(coalesce(j.last_error || ' | ', '') || 'watchdog_recovered_stale_processing', 1000),
      locked_at = null,
      updated_at = now()
  where j.status = 'processing'
    and j.locked_at < now() - interval '15 minutes';
  get diagnostics v_jobs = row_count;

  update private.telegram_autopilot_deliveries d
  set status = case when d.attempt_count >= d.max_attempts then 'failed' else 'retrying' end,
      next_attempt_at = case when d.attempt_count >= d.max_attempts then d.next_attempt_at else now() end,
      last_error = left(coalesce(d.last_error || ' | ', '') || 'watchdog_recovered_stale_processing', 500),
      locked_at = null,
      updated_at = now()
  where d.status = 'processing'
    and d.locked_at < now() - interval '15 minutes';
  get diagnostics v_telegram = row_count;

  return jsonb_build_object('autopilot_jobs', v_jobs, 'telegram_deliveries', v_telegram);
end;
$$;

revoke all on function private.refresh_all_customer_risks() from public, anon, authenticated;
revoke all on function private.recover_stale_autopilot_processing() from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from cron.job where jobname = 'zhirox-autopilot-daily-risk-refresh') then
    perform cron.schedule(
      'zhirox-autopilot-daily-risk-refresh',
      '15 2 * * *',
      'select private.refresh_all_customer_risks();'
    );
  end if;

  if not exists (select 1 from cron.job where jobname = 'zhirox-autopilot-watchdog') then
    perform cron.schedule(
      'zhirox-autopilot-watchdog',
      '*/5 * * * *',
      'select private.recover_stale_autopilot_processing();'
    );
  end if;
end;
$$;
