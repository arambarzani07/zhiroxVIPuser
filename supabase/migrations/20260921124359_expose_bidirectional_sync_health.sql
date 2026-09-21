-- Give the tenant admin one safe, tenant-scoped view of inbound and outbound
-- synchronization, and make the existing manual refresh drain both sides.

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
      'last_transaction_id', s.last_transaction_id,
      'sync_mode', s.sync_mode,
      'inbound_sync_enabled', s.inbound_sync_enabled,
      'outbound_sync_enabled', s.outbound_sync_enabled,
      'outbound_write_contract_status', s.outbound_write_contract_status,
      'reconciliation_status', s.reconciliation_status,
      'reconciliation_missing_contacts', s.reconciliation_missing_contacts,
      'reconciliation_missing_transactions', s.reconciliation_missing_transactions,
      'last_reconciled_at', s.last_reconciled_at
    ),
    'bidirectional_ready', (
      s.sync_mode = 'zhirox_primary'
      and coalesce(s.inbound_sync_enabled, false)
      and coalesce(s.outbound_sync_enabled, false)
      and s.outbound_write_contract_status = 'verified'
      and s.health_status = 'healthy'
      and s.last_success_at is not null
      and s.last_success_at >= now() - interval '5 minutes'
      and s.reconciliation_status = 'clean'
      and coalesce(s.reconciliation_missing_contacts, 0) = 0
      and coalesce(s.reconciliation_missing_transactions, 0) = 0
      and not exists (
        select 1
        from public.daftar_outbound_events o
        where o.sync_source_id = s.id
          and o.status in ('failed', 'blocked')
      )
    ),
    'outbound_queue', jsonb_build_object(
      'pending', (
        select count(*) from public.daftar_outbound_events o
        where o.sync_source_id = s.id and o.status = 'pending'
      ),
      'processing', (
        select count(*) from public.daftar_outbound_events o
        where o.sync_source_id = s.id and o.status = 'processing'
      ),
      'failed', (
        select count(*) from public.daftar_outbound_events o
        where o.sync_source_id = s.id and o.status = 'failed'
      ),
      'blocked', (
        select count(*) from public.daftar_outbound_events o
        where o.sync_source_id = s.id and o.status = 'blocked'
      ),
      'oldest_waiting_at', (
        select min(o.created_at) from public.daftar_outbound_events o
        where o.sync_source_id = s.id
          and o.status in ('pending', 'processing', 'failed', 'blocked')
      ),
      'last_sent_at', (
        select max(o.sent_at) from public.daftar_outbound_events o
        where o.sync_source_id = s.id and o.status = 'sent'
      )
    ),
    'inbound_missing_candidates', (
      select count(*)
      from public.daftar_inbound_missing_candidates i
      where i.sync_source_id = s.id
    ),
    'recent_runs', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.started_at desc), '[]'::jsonb)
      from (
        select r.status, r.fetched_contacts, r.fetched_transactions,
          r.new_customers, r.new_debts, r.new_payment_allocations,
          r.reused_records, r.error_message, r.started_at, r.completed_at,
          r.updated_customers, r.updated_debts, r.updated_payments,
          r.deleted_customers, r.deleted_debts, r.deleted_payments
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

revoke all on function public.get_my_daftar_sync_dashboard()
  from public, anon;
grant execute on function public.get_my_daftar_sync_dashboard()
  to authenticated;

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
  v_inbound_request_id bigint;
  v_outbound_request_id bigint;
  v_outbound_enabled boolean := false;
begin
  if v_uid is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  select s.id, coalesce(s.outbound_sync_enabled, false)
    into v_source_id, v_outbound_enabled
  from public.daftar_sync_sources s
  where s.admin_id = v_uid
    and s.legacy_user_id = 28
    and s.enabled = true
  limit 1;

  if v_source_id is null then
    raise exception 'sync_source_not_available' using errcode = '42501';
  end if;

  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'daftar_sync_account_28_trigger'
  limit 1;

  if v_secret is null then
    raise exception 'sync_secret_not_configured';
  end if;

  select net.http_post(
    url := 'https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/daftar-sync-gateway',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-daftar-sync-secret', v_secret
    ),
    body := jsonb_build_object('source_id', v_source_id),
    timeout_milliseconds := 120000
  ) into v_inbound_request_id;

  if v_outbound_enabled then
    select net.http_post(
      url := 'https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/daftar-outbound-sync',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-daftar-sync-secret', v_secret
      ),
      body := jsonb_build_object(
        'source_id', v_source_id,
        'action', 'drain'
      ),
      timeout_milliseconds := 120000
    ) into v_outbound_request_id;
  end if;

  return jsonb_build_object(
    'accepted', true,
    'inbound_request_id', v_inbound_request_id,
    'outbound_request_id', v_outbound_request_id
  );
end;
$$;

revoke all on function public.request_my_daftar_sync()
  from public, anon;
grant execute on function public.request_my_daftar_sync()
  to authenticated;
