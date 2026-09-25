-- Cover every public-schema foreign key with a matching leading index.
-- These indexes preserve semantics and improve FK validation, deletes, joins,
-- and owner/customer lookup paths as the dataset grows.

create index if not exists idx_customer_manual_push_campaigns_actor_id
  on public.customer_manual_push_campaigns (actor_id);
create index if not exists idx_customer_manual_push_campaigns_target_customer_id
  on public.customer_manual_push_campaigns (target_customer_id);
create index if not exists idx_customer_push_link_tokens_created_by
  on public.customer_push_link_tokens (created_by);
create index if not exists idx_customer_push_link_tokens_customer_id
  on public.customer_push_link_tokens (customer_id);
create index if not exists idx_customer_push_subscriptions_customer_id
  on public.customer_push_subscriptions (customer_id);
create index if not exists idx_daftar_customer_link_archive_admin_id
  on public.daftar_customer_link_archive (admin_id);
create index if not exists idx_daftar_customer_link_archive_sync_source_id
  on public.daftar_customer_link_archive (sync_source_id);
create index if not exists idx_daftar_customer_link_archive_target_id
  on public.daftar_customer_link_archive (target_id);
create index if not exists idx_notification_outbox_customer_id
  on public.notification_outbox (customer_id);
create index if not exists idx_owner_backup_monitoring_policies_updated_by
  on public.owner_backup_monitoring_policies (updated_by);
create index if not exists idx_owner_platform_audit_actor_id
  on public.owner_platform_audit (actor_id);
create index if not exists idx_owner_platform_audit_target_admin_id
  on public.owner_platform_audit (target_admin_id);
create index if not exists idx_owner_tenant_branding_updated_by
  on public.owner_tenant_branding (updated_by);
create index if not exists idx_owner_tenant_controls_updated_by
  on public.owner_tenant_controls (updated_by);
create index if not exists idx_owner_tenant_domains_updated_by
  on public.owner_tenant_domains (updated_by);
create index if not exists idx_owner_tenant_entitlement_overrides_feature_key
  on public.owner_tenant_entitlement_overrides (feature_key);
create index if not exists idx_owner_tenant_entitlement_overrides_updated_by
  on public.owner_tenant_entitlement_overrides (updated_by);
create index if not exists idx_platform_account_recovery_events_actor_id
  on public.platform_account_recovery_events (actor_id);
create index if not exists idx_platform_admin_devices_approved_by
  on public.platform_admin_devices (approved_by);
create index if not exists idx_platform_admin_devices_revoked_by
  on public.platform_admin_devices (revoked_by);
create index if not exists idx_platform_incidents_created_by
  on public.platform_incidents (created_by);
create index if not exists idx_platform_incidents_updated_by
  on public.platform_incidents (updated_by);
create index if not exists idx_platform_operations_config_updated_by
  on public.platform_operations_config (updated_by);
create index if not exists idx_platform_plan_entitlements_feature_key
  on public.platform_plan_entitlements (feature_key);
create index if not exists idx_platform_plan_entitlements_updated_by
  on public.platform_plan_entitlements (updated_by);
create index if not exists idx_platform_policy_acceptances_policy_key_version
  on public.platform_policy_acceptances (policy_key, version);
create index if not exists idx_platform_policy_documents_updated_by
  on public.platform_policy_documents (updated_by);
create index if not exists idx_platform_retention_policy_updated_by
  on public.platform_retention_policy (updated_by);
