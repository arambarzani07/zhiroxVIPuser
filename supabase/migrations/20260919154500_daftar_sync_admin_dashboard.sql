-- Tenant-scoped monitoring and manual refresh for the Daftar sync dashboard.

create or replace function public.get_my_daftar_sync_dashboard()
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select coalesce(jsonb_build_object(
    'source', jsonb_build_object(
      'source_name', s.source_name,
      'enabled', s.enabled,
      'health_status', s.health_status,
      'last_status', s.last_status,
      'last_started_at', s.last_started_at,
      'last_success_at', s.last_success_at,
      'last_heartbeat_at', s.last_heartbeat_at,
      'last_duration_ms', s.last_duration_ms,
      'consecutive_failures', s.consecutive_failures,
      'total_failures', s.total_failures,
      'next_retry_at', s.next_retry_at,
      'circuit_open_until', s.circuit_open_until,
      'last_error', s.last_error,
      'last_result', s.last_result,
      'last_contact_id', s.last_contact_id,
      'last_transaction_id', s.last_transaction_id
    ),
    'recent_runs', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.started_at desc), '[]'::jsonb)
      from (
        select r.status, r.fetched_contacts, r.fetched_transactions,
          r.new_customers, r.new_debts, r.new_payment_allocations,
          r.reused_records, r.error_message, r.started_at, r.completed_at
        from public.daftar_sync_runs r
        where r.sync_source_id = s.id
        order by r.started_at desc limit 20
      ) x
    ),
    'open_dead_letters', (
      select count(*) from public.daftar_sync_dead_letters d
      where d.sync_source_id = s.id and d.resolved_at is null
    ),
    'recent_errors', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.last_seen_at desc), '[]'::jsonb)
      from (
        select d.entity_kind, d.source_id, d.error_code, d.error_detail,
          d.attempts, d.first_seen_at, d.last_seen_at
        from public.daftar_sync_dead_letters d
        where d.sync_source_id = s.id and d.resolved_at is null
        order by d.last_seen_at desc limit 20
      ) x
    )
  ), '{}'::jsonb)
  from public.daftar_sync_sources s
  where (select auth.uid()) is not null
    and s.admin_id = (select auth.uid())
    and s.enabled = true
  order by s.created_at
  limit 1;
$$;

revoke all on function public.get_my_daftar_sync_dashboard() from public, anon;
grant execute on function public.get_my_daftar_sync_dashboard() to authenticated;

create or replace function public.request_my_daftar_sync()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_source_id uuid;
  v_secret text;
  v_request_id bigint;
begin
  if v_uid is null then raise exception 'authentication_required' using errcode = '42501'; end if;

  select s.id into v_source_id
  from public.daftar_sync_sources s
  where s.admin_id = v_uid and s.legacy_user_id = 28 and s.enabled = true
  limit 1;
  if v_source_id is null then raise exception 'sync_source_not_available' using errcode = '42501'; end if;

  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'daftar_sync_account_28_trigger'
  limit 1;
  if v_secret is null then raise exception 'sync_secret_not_configured'; end if;

  select net.http_post(
    url := 'https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/daftar-sync-gateway',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-daftar-sync-secret', v_secret
    ),
    body := jsonb_build_object('source_id', v_source_id),
    timeout_milliseconds := 120000
  ) into v_request_id;

  return jsonb_build_object('accepted', true, 'request_id', v_request_id);
end;
$$;

revoke all on function public.request_my_daftar_sync() from public, anon;
grant execute on function public.request_my_daftar_sync() to authenticated;

