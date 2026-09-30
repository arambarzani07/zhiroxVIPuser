-- Keep customer notification outbox moving without exposing the worker secret
-- in the pg_cron command itself. The worker retains its custom secret auth.

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

-- Make this migration safe to replay: replace only our named job.
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
