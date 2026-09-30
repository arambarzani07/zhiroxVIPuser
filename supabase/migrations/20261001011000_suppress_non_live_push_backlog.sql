-- Historical Daftar/legacy rows are data migration, not new customer activity.
-- Suppress any queued financial notifications for those linked rows before the
-- worker is invoked, then keep the worker scheduled for genuine live events.

create or replace function public.invoke_customer_push_worker_service()
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_config jsonb;
  v_secret text;
  v_request_id bigint;
begin
  update public.notification_outbox o
  set status = 'completed',
      completed_at = coalesce(o.completed_at, now()),
      next_attempt_at = now(),
      fanout_at = coalesce(o.fanout_at, now()),
      last_error = 'suppressed_non_live_source'
  where o.status in ('pending', 'processing')
    and o.event_type in ('debt_created', 'payment_created')
    and (
      exists (
        select 1
        from public.legacy_import_links l
        where l.target_id = o.event_record_id
          and l.entity_kind = case
            when o.event_type = 'debt_created' then 'debt'
            else 'payment'
          end
      )
      or exists (
        select 1
        from public.daftar_sync_seen s
        where s.target_id = o.event_record_id
          and s.entity_kind = case
            when o.event_type = 'debt_created' then 'debt'
            else 'payment'
          end
      )
    );

  v_config := public.get_customer_push_runtime_config_service();
  v_secret := nullif(v_config->>'customer_push_worker_secret', '');

  if v_secret is null then
    raise exception 'customer_push_worker_secret_missing';
  end if;

  select net.http_post(
    url := 'https://madoflmbretqghqbqaak.supabase.co/functions/v1/customer-push-worker',
    body := '{}'::jsonb,
    params := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-zhirox-push-worker', v_secret
    ),
    timeout_milliseconds := 10000
  )
  into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function public.invoke_customer_push_worker_service() from public;
revoke all on function public.invoke_customer_push_worker_service() from anon;
revoke all on function public.invoke_customer_push_worker_service() from authenticated;
grant execute on function public.invoke_customer_push_worker_service() to service_role;

do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid
    from cron.job
    where jobname = 'zhirox-customer-push-worker'
  loop
    perform cron.unschedule(v_job_id);
  end loop;

  perform cron.schedule(
    'zhirox-customer-push-worker',
    '* * * * *',
    'select public.invoke_customer_push_worker_service();'
  );
end;
$$;
