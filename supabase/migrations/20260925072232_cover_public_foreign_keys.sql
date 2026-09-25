-- Cover public-schema foreign keys with matching leading indexes.
-- Production contains a few owner/platform tables that are not present in a
-- fresh user-source database. Build indexes only for tables available in the
-- current deployment so this migration remains fresh-install safe.

do $fk_indexes$
declare
  r record;
begin
  for r in
    select *
    from (values
      ('public.customer_manual_push_campaigns', 'create index if not exists idx_customer_manual_push_campaigns_actor_id on public.customer_manual_push_campaigns (actor_id)'),
      ('public.customer_manual_push_campaigns', 'create index if not exists idx_customer_manual_push_campaigns_target_customer_id on public.customer_manual_push_campaigns (target_customer_id)'),
      ('public.customer_push_link_tokens', 'create index if not exists idx_customer_push_link_tokens_created_by on public.customer_push_link_tokens (created_by)'),
      ('public.customer_push_link_tokens', 'create index if not exists idx_customer_push_link_tokens_customer_id on public.customer_push_link_tokens (customer_id)'),
      ('public.customer_push_subscriptions', 'create index if not exists idx_customer_push_subscriptions_customer_id on public.customer_push_subscriptions (customer_id)'),
      ('public.daftar_customer_link_archive', 'create index if not exists idx_daftar_customer_link_archive_admin_id on public.daftar_customer_link_archive (admin_id)'),
      ('public.daftar_customer_link_archive', 'create index if not exists idx_daftar_customer_link_archive_sync_source_id on public.daftar_customer_link_archive (sync_source_id)'),
      ('public.daftar_customer_link_archive', 'create index if not exists idx_daftar_customer_link_archive_target_id on public.daftar_customer_link_archive (target_id)'),
      ('public.notification_outbox', 'create index if not exists idx_notification_outbox_customer_id on public.notification_outbox (customer_id)'),
      ('public.owner_backup_monitoring_policies', 'create index if not exists idx_owner_backup_monitoring_policies_updated_by on public.owner_backup_monitoring_policies (updated_by)'),
      ('public.owner_platform_audit', 'create index if not exists idx_owner_platform_audit_actor_id on public.owner_platform_audit (actor_id)'),
      ('public.owner_platform_audit', 'create index if not exists idx_owner_platform_audit_target_admin_id on public.owner_platform_audit (target_admin_id)'),
      ('public.owner_tenant_branding', 'create index if not exists idx_owner_tenant_branding_updated_by on public.owner_tenant_branding (updated_by)'),
      ('public.owner_tenant_controls', 'create index if not exists idx_owner_tenant_controls_updated_by on public.owner_tenant_controls (updated_by)'),
      ('public.owner_tenant_domains', 'create index if not exists idx_owner_tenant_domains_updated_by on public.owner_tenant_domains (updated_by)'),
      ('public.owner_tenant_entitlement_overrides', 'create index if not exists idx_owner_tenant_entitlement_overrides_feature_key on public.owner_tenant_entitlement_overrides (feature_key)'),
      ('public.owner_tenant_entitlement_overrides', 'create index if not exists idx_owner_tenant_entitlement_overrides_updated_by on public.owner_tenant_entitlement_overrides (updated_by)'),
      ('public.platform_account_recovery_events', 'create index if not exists idx_platform_account_recovery_events_actor_id on public.platform_account_recovery_events (actor_id)'),
      ('public.platform_admin_devices', 'create index if not exists idx_platform_admin_devices_approved_by on public.platform_admin_devices (approved_by)'),
      ('public.platform_admin_devices', 'create index if not exists idx_platform_admin_devices_revoked_by on public.platform_admin_devices (revoked_by)'),
      ('public.platform_incidents', 'create index if not exists idx_platform_incidents_created_by on public.platform_incidents (created_by)'),
      ('public.platform_incidents', 'create index if not exists idx_platform_incidents_updated_by on public.platform_incidents (updated_by)'),
      ('public.platform_operations_config', 'create index if not exists idx_platform_operations_config_updated_by on public.platform_operations_config (updated_by)'),
      ('public.platform_plan_entitlements', 'create index if not exists idx_platform_plan_entitlements_feature_key on public.platform_plan_entitlements (feature_key)'),
      ('public.platform_plan_entitlements', 'create index if not exists idx_platform_plan_entitlements_updated_by on public.platform_plan_entitlements (updated_by)'),
      ('public.platform_policy_acceptances', 'create index if not exists idx_platform_policy_acceptances_policy_key_version on public.platform_policy_acceptances (policy_key, version)'),
      ('public.platform_policy_documents', 'create index if not exists idx_platform_policy_documents_updated_by on public.platform_policy_documents (updated_by)'),
      ('public.platform_retention_policy', 'create index if not exists idx_platform_retention_policy_updated_by on public.platform_retention_policy (updated_by)')
    ) as candidates(table_name, ddl)
  loop
    if to_regclass(r.table_name) is not null then
      execute r.ddl;
    end if;
  end loop;
end
$fk_indexes$;
