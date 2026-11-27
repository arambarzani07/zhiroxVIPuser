-- Read-only VIP cutover readiness smoke check.
-- Run on the intended target using an authorized database administrator.
-- Never run as a browser-facing RPC; no secret values or customer records returned.
-- All gates must pass before production release. This is necessary, not sufficient:
-- separately verify storage object manifest/bytes, source shutdown, Edge Function
-- delivery, signed iOS builds, on-device acceptance and external disaster recovery.
-- Vault presence does not prove provider authentication or actual notification delivery.
BEGIN TRANSACTION READ ONLY;
WITH gates AS (
 SELECT 'daftar_sync_healthy' AS gate, EXISTS(SELECT 1 FROM public.daftar_sync_sources WHERE enabled AND inbound_sync_enabled AND outbound_sync_enabled) AND NOT EXISTS(SELECT 1 FROM public.daftar_sync_sources WHERE enabled AND (last_status IS DISTINCT FROM 'success' OR health_status IS DISTINCT FROM 'healthy' OR last_success_at IS NULL OR last_success_at < now()-interval '10 minutes')) AS passed
 UNION ALL SELECT 'daftar_outbound_clear', NOT EXISTS(SELECT 1 FROM public.daftar_outbound_events WHERE status NOT IN ('sent','skipped'))
 UNION ALL SELECT 'tenant_backup_verified_recent', EXISTS(SELECT 1 FROM public.tenant_backups WHERE created_at>now()-interval '24 hours' AND verification->>'restorable'='true' AND payload_sha256=encode(extensions.digest(payload::text,'sha256'),'hex'))
 UNION ALL SELECT 'web_push_runtime_present', (SELECT count(DISTINCT name)=5 FROM vault.secrets WHERE name IN ('customer_push_worker_secret','customer_push_rate_limit_salt','customer_push_vapid_private','customer_push_vapid_public','customer_push_vapid_subject'))
 UNION ALL SELECT 'notification_credentials_present', (SELECT count(DISTINCT name)=3 FROM vault.secrets WHERE name IN ('onesignal_app_id','onesignal_rest_api_key','telegram_bot_token'))
 UNION ALL SELECT 'notification_queue_clear', NOT EXISTS(SELECT 1 FROM public.notification_outbox WHERE status IN ('pending','processing'))
 UNION ALL SELECT 'receipt_bucket_present_private', EXISTS(SELECT 1 FROM storage.buckets WHERE id='receipts' AND NOT public)
 UNION ALL SELECT 'financial_projection_migrations_present', (SELECT count(DISTINCT name)=3 FROM supabase_migrations.schema_migrations WHERE name IN ('reconcile_verified_historical_payment_projection','align_daftar_customer_risk_balance_projection','align_migrated_daftar_monthly_statement_projection'))
)
SELECT gate,passed FROM gates ORDER BY gate;
ROLLBACK;
