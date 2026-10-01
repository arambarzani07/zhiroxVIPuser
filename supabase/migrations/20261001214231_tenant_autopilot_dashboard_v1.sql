create or replace function public.get_my_autopilot_dashboard()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_market_id uuid;
  v_enabled boolean := false;
  v_mode text := 'manual';
  v_risk_enabled boolean := true;
  v_max_retry integer := 5;
  v_linked integer := 0;
  v_tg_pending integer := 0;
  v_tg_processing integer := 0;
  v_tg_retrying integer := 0;
  v_tg_failed integer := 0;
  v_tg_dead integer := 0;
  v_tg_sent_24h integer := 0;
  v_receipt_queued integer := 0;
  v_receipt_processing integer := 0;
  v_receipt_retrying integer := 0;
  v_receipt_failed integer := 0;
  v_receipt_dead integer := 0;
  v_receipt_sent_24h integer := 0;
  v_statement_queued integer := 0;
  v_statement_processing integer := 0;
  v_statement_retrying integer := 0;
  v_statement_failed integer := 0;
  v_statement_dead integer := 0;
  v_statement_done_30d integer := 0;
  v_notif_pending integer := 0;
  v_notif_processing integer := 0;
  v_notif_failed integer := 0;
  v_notif_completed_24h integer := 0;
  v_risk_total integer := 0;
  v_risk_low integer := 0;
  v_risk_medium integer := 0;
  v_risk_high integer := 0;
  v_risk_critical integer := 0;
  v_risk_updated timestamptz;
  v_recent_issues jsonb := '[]'::jsonb;
  v_active_queue integer := 0;
  v_retry_total integer := 0;
  v_failed_total integer := 0;
  v_dead_total integer := 0;
  v_health text := 'healthy';
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  select p.id
    into v_market_id
  from public.profiles p
  where p.id = v_uid
    and p.role = 'admin'
    and p.active = true
    and p.approved = true
  limit 1;

  if v_market_id is null then
    raise exception 'admin_required' using errcode='42501';
  end if;

  select coalesce(s.enabled,false), coalesce(s.mode,'manual'), coalesce(s.risk_enabled,true), coalesce(s.max_retry_attempts,5)
    into v_enabled, v_mode, v_risk_enabled, v_max_retry
  from public.market_autopilot_settings s
  where s.market_id = v_market_id;

  select count(*)::integer
    into v_linked
  from private.telegram_credentials tc
  join public.profiles c on c.id = tc.user_id
  where c.admin_id = v_market_id
    and c.role = 'customer'
    and c.active = true
    and c.approved = true
    and nullif(btrim(coalesce(tc.chat_id,'')),'') is not null;

  select
    count(*) filter (where d.status='pending')::integer,
    count(*) filter (where d.status='processing')::integer,
    count(*) filter (where d.status='retrying')::integer,
    count(*) filter (where d.status='failed')::integer,
    count(*) filter (where d.status='dead_letter')::integer,
    count(*) filter (where d.status='sent' and d.sent_at >= now()-interval '24 hours')::integer
  into v_tg_pending,v_tg_processing,v_tg_retrying,v_tg_failed,v_tg_dead,v_tg_sent_24h
  from private.telegram_autopilot_deliveries d
  where d.market_id = v_market_id;

  select
    count(*) filter (where j.status='queued')::integer,
    count(*) filter (where j.status='processing')::integer,
    count(*) filter (where j.status='retrying')::integer,
    count(*) filter (where j.status='failed')::integer,
    count(*) filter (where j.status='dead_letter')::integer,
    count(*) filter (where j.status='succeeded' and j.completed_at >= now()-interval '24 hours')::integer
  into v_receipt_queued,v_receipt_processing,v_receipt_retrying,v_receipt_failed,v_receipt_dead,v_receipt_sent_24h
  from private.telegram_auto_receipt_jobs j
  where j.market_id = v_market_id;

  select
    count(*) filter (where j.status='queued')::integer,
    count(*) filter (where j.status='processing')::integer,
    count(*) filter (where j.status='retrying')::integer,
    count(*) filter (where j.status='failed')::integer,
    count(*) filter (where j.status='dead_letter')::integer,
    count(*) filter (where j.status='succeeded' and j.completed_at >= now()-interval '30 days')::integer
  into v_statement_queued,v_statement_processing,v_statement_retrying,v_statement_failed,v_statement_dead,v_statement_done_30d
  from private.telegram_full_statement_jobs j
  where j.market_id = v_market_id;

  select
    count(*) filter (where o.status='pending')::integer,
    count(*) filter (where o.status='processing')::integer,
    count(*) filter (where o.status='failed')::integer,
    count(*) filter (where o.status='completed' and o.completed_at >= now()-interval '24 hours')::integer
  into v_notif_pending,v_notif_processing,v_notif_failed,v_notif_completed_24h
  from public.notification_outbox o
  where o.market_id = v_market_id;

  select
    count(*)::integer,
    count(*) filter (where r.level='low')::integer,
    count(*) filter (where r.level='medium')::integer,
    count(*) filter (where r.level='high')::integer,
    count(*) filter (where r.level='critical')::integer,
    max(r.calculated_at)
  into v_risk_total,v_risk_low,v_risk_medium,v_risk_high,v_risk_critical,v_risk_updated
  from public.customer_risk_scores r
  where r.market_id = v_market_id;

  select coalesce(jsonb_agg(jsonb_build_object(
      'source', q.source,
      'status', q.status,
      'customer_id', q.customer_id,
      'error', q.error,
      'created_at', q.created_at
    ) order by q.created_at desc), '[]'::jsonb)
  into v_recent_issues
  from (
    select 'telegram'::text as source, d.status, d.customer_id, d.last_error as error, d.updated_at as created_at
    from private.telegram_autopilot_deliveries d
    where d.market_id=v_market_id and d.status in ('retrying','failed','dead_letter')
    union all
    select 'receipt', j.status, j.customer_id, j.last_error, j.updated_at
    from private.telegram_auto_receipt_jobs j
    where j.market_id=v_market_id and j.status in ('retrying','failed','dead_letter')
    union all
    select 'statement', j.status, j.customer_id, j.last_error, j.updated_at
    from private.telegram_full_statement_jobs j
    where j.market_id=v_market_id and j.status in ('retrying','failed','dead_letter')
    order by created_at desc
    limit 8
  ) q;

  v_active_queue := v_tg_pending + v_tg_processing + v_tg_retrying
                  + v_receipt_queued + v_receipt_processing + v_receipt_retrying
                  + v_statement_queued + v_statement_processing + v_statement_retrying
                  + v_notif_pending + v_notif_processing;
  v_retry_total := v_tg_retrying + v_receipt_retrying + v_statement_retrying;
  v_failed_total := v_tg_failed + v_receipt_failed + v_statement_failed + v_notif_failed;
  v_dead_total := v_tg_dead + v_receipt_dead + v_statement_dead;

  v_health := case
    when v_dead_total > 0 then 'attention'
    when v_failed_total > 0 or v_retry_total > 0 then 'degraded'
    else 'healthy'
  end;

  return jsonb_build_object(
    'generated_at', now(),
    'market_id', v_market_id,
    'autopilot', jsonb_build_object(
      'enabled', v_enabled,
      'mode', v_mode,
      'risk_enabled', v_risk_enabled,
      'max_retry_attempts', v_max_retry
    ),
    'health', jsonb_build_object(
      'status', v_health,
      'active_queue', v_active_queue,
      'retrying', v_retry_total,
      'failed', v_failed_total,
      'dead_letter', v_dead_total
    ),
    'telegram', jsonb_build_object(
      'linked_customers', v_linked,
      'sent_24h', v_tg_sent_24h,
      'queued', v_tg_pending,
      'processing', v_tg_processing,
      'retrying', v_tg_retrying,
      'failed', v_tg_failed,
      'dead_letter', v_tg_dead
    ),
    'receipts', jsonb_build_object(
      'sent_24h', v_receipt_sent_24h,
      'queued', v_receipt_queued,
      'processing', v_receipt_processing,
      'retrying', v_receipt_retrying,
      'failed', v_receipt_failed,
      'dead_letter', v_receipt_dead
    ),
    'statements', jsonb_build_object(
      'completed_30d', v_statement_done_30d,
      'queued', v_statement_queued,
      'processing', v_statement_processing,
      'retrying', v_statement_retrying,
      'failed', v_statement_failed,
      'dead_letter', v_statement_dead
    ),
    'notifications', jsonb_build_object(
      'completed_24h', v_notif_completed_24h,
      'pending', v_notif_pending,
      'processing', v_notif_processing,
      'failed', v_notif_failed
    ),
    'risk', jsonb_build_object(
      'total', v_risk_total,
      'low', v_risk_low,
      'medium', v_risk_medium,
      'high', v_risk_high,
      'critical', v_risk_critical,
      'updated_at', v_risk_updated
    ),
    'recent_issues', v_recent_issues
  );
end;
$$;

revoke all on function public.get_my_autopilot_dashboard() from public, anon;
grant execute on function public.get_my_autopilot_dashboard() to authenticated;
