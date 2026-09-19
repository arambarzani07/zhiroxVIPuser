from pathlib import Path

dashboard = Path('lib/screens/auth/owner_dashboard.dart').read_text()
health = Path('lib/screens/auth/owner_health_center_screen.dart').read_text()
subscription = Path('lib/screens/auth/owner_subscription_center_screen.dart').read_text()
security = Path('lib/screens/auth/owner_security_center_screen.dart').read_text()
support = Path('lib/screens/auth/owner_support_center_screen.dart').read_text()
operations = Path('lib/screens/auth/owner_operations_center_screen.dart').read_text()
entitlements = Path('lib/screens/auth/owner_entitlements_center_screen.dart').read_text()
recovery_devices = Path('lib/screens/auth/owner_recovery_device_center_screen.dart').read_text()
backup_resilience = Path('lib/screens/auth/owner_backup_resilience_center_screen.dart').read_text()
readiness = Path('lib/screens/auth/owner_readiness_center_screen.dart').read_text()
release_center = Path('lib/screens/auth/update_control_screen.dart').read_text()
infrastructure = Path('lib/screens/auth/owner_infrastructure_center_screen.dart').read_text()
policy_compliance = Path('lib/screens/auth/owner_policy_compliance_center_screen.dart').read_text()
domain_center = Path('lib/screens/auth/owner_domain_center_screen.dart').read_text()
domain_function = Path('supabase/functions/owner-domain-check/index.ts').read_text()
recovery_function = Path('supabase/functions/owner-account-recovery/index.ts').read_text()
service = Path('lib/services/pb_service.dart').read_text()
auth_provider = Path('lib/providers/auth_provider.dart').read_text()
health_migration = Path(
    'supabase/migrations/20260918135500_owner_health_audit_center.sql'
).read_text()
subscription_migration = Path(
    'supabase/migrations/20260918162000_owner_subscription_center.sql'
).read_text()
security_migration = Path(
    'supabase/migrations/20260918170000_owner_security_center.sql'
).read_text()
support_migration = Path(
    'supabase/migrations/20260918180000_owner_support_center.sql'
).read_text()
operations_migration = Path(
    'supabase/migrations/20260918200000_owner_operations_center.sql'
).read_text()
entitlements_migration = Path(
    'supabase/migrations/20260918210000_owner_entitlements_center.sql'
).read_text()
recovery_device_migration = Path(
    'supabase/migrations/20260918213000_owner_recovery_device_center.sql'
).read_text()
backup_resilience_migration = Path(
    'supabase/migrations/20260918220000_owner_backup_resilience_center.sql'
).read_text()
readiness_migration = Path(
    'supabase/migrations/20260918223000_owner_readiness_center.sql'
).read_text()
release_migration = Path(
    'supabase/migrations/20260918230000_owner_release_compliance_center.sql'
).read_text()
infrastructure_migration = Path(
    'supabase/migrations/20260918233000_owner_infrastructure_center.sql'
).read_text()
policy_compliance_migration = Path(
    'supabase/migrations/20260918235000_owner_policy_compliance_center.sql'
).read_text()
domain_migration = Path(
    'supabase/migrations/20260919080000_owner_domain_center.sql'
).read_text()

required = [
    'OwnerHealthCenterScreen',
    'OwnerSubscriptionCenterScreen',
    'OwnerSecurityCenterScreen',
    'OwnerSupportCenterScreen',
    'OwnerOperationsCenterScreen',
    'OwnerEntitlementsCenterScreen',
    'OwnerRecoveryDeviceCenterScreen',
    'OwnerBackupResilienceCenterScreen',
    'OwnerReadinessCenterScreen',
    'UpdateControlScreen',
    'OwnerInfrastructureCenterScreen',
    'OwnerPolicyComplianceCenterScreen',
    'OwnerDomainCenterScreen',
    'getOwnerHealthOverview',
    'getOwnerPlatformAuditPage',
    'getOwnerSubscriptionOverview',
    'getOwnerSubscriptionsPage',
    'setOwnerSubscription',
    'getOwnerSecurityOverview',
    'getOwnerSecurityPage',
    'revokeOwnerAdminSessions',
    'setOwnerAdminLock',
    'getOwnerSupportOverview',
    'getOwnerSupportTicketsPage',
    'updateOwnerSupportTicket',
    'getPlatformOperationsState',
    'setOwnerOperationsState',
    'getOwnerEntitlementsOverview',
    'getOwnerRecoveryDeviceOverview',
    'getOwnerRecoveryDevicePage',
    'setOwnerAdminDevicePolicy',
    'setOwnerAdminDeviceAuthorization',
    'recoverOwnerAdminAccount',
    'registerPlatformAdminDevice',
    'getOwnerBackupResilienceOverview',
    'getOwnerBackupResiliencePage',
    'setOwnerBackupMonitoringPolicy',
    'getOwnerReadinessOverview',
    'getOwnerReadinessPage',
    'getOwnerReleaseOverview',
    'getOwnerReleaseCompliancePage',
    'setOwnerReleasePolicy',
    'getOwnerInfrastructureOverview',
    'getOwnerInfrastructureJobsPage',
    'getOwnerPolicyOverview',
    'getOwnerPolicyPage',
    'publishOwnerPolicyDocument',
    'setOwnerRetentionPolicy',
    'getOwnerDomainOverview',
    'getOwnerDomainPage',
    'setOwnerTenantDomain',
    'checkOwnerTenantDomain',
    '_enforceAdminDeviceAuthorization',
    '_startDeviceAuthorizationHeartbeat',
    'getOwnerEntitlementsPage',
    'setOwnerTenantFeaturePlan',
    'setOwnerPlanEntitlement',
    'setOwnerTenantEntitlement',
    'get_system_owner_health_overview',
    'get_system_owner_platform_audit_page',
    'get_system_owner_subscription_overview',
    'get_system_owner_subscriptions_page',
    'set_system_owner_subscription',
    'get_system_owner_security_overview',
    'get_system_owner_security_page',
    'revoke_system_owner_admin_sessions',
    'set_system_owner_admin_lock',
    'get_system_owner_support_overview',
    'get_system_owner_support_tickets_page',
    'update_system_owner_support_ticket',
    'create_platform_support_ticket',
    'get_platform_operations_state',
    'set_system_owner_operations_state',
    'get_system_owner_entitlements_overview',
    'get_system_owner_entitlements_page',
    'set_system_owner_tenant_feature_plan',
    'set_system_owner_plan_entitlement',
    'set_system_owner_tenant_entitlement',
    'get_platform_entitlements_state',
    'register_platform_admin_device',
    'get_system_owner_recovery_device_overview',
    'get_system_owner_recovery_device_page',
    'set_system_owner_admin_device_policy',
    'set_system_owner_admin_device_authorization',
    'complete_system_owner_admin_recovery_service',
    'get_system_owner_backup_resilience_overview',
    'get_system_owner_backup_resilience_page',
    'set_system_owner_backup_monitoring_policy',
    'get_system_owner_readiness_overview',
    'get_system_owner_readiness_page',
    'get_system_owner_release_overview',
    'get_system_owner_release_compliance_page',
    'set_system_owner_release_policy',
    'get_system_owner_infrastructure_overview',
    'get_system_owner_infrastructure_jobs_page',
    'get_system_owner_policy_overview',
    'get_system_owner_policy_page',
    'publish_system_owner_policy_document',
    'set_system_owner_retention_policy',
    'get_platform_policy_state',
    'accept_platform_policy',
    'get_system_owner_domain_overview',
    'get_system_owner_domain_page',
    'set_system_owner_tenant_domain',
    'get_system_owner_domain_check_target',
    'record_system_owner_domain_check',
    'system_owner_required',
]
blob = '\n'.join([
    dashboard,
    health,
    subscription,
    security,
    support,
    operations,
    entitlements,
    recovery_devices,
    backup_resilience,
    readiness,
    release_center,
    infrastructure,
    policy_compliance,
    domain_center,
    domain_function,
    recovery_function,
    service,
    auth_provider,
    health_migration,
    subscription_migration,
    security_migration,
    support_migration,
    operations_migration,
    entitlements_migration,
    recovery_device_migration,
    backup_resilience_migration,
    readiness_migration,
    release_migration,
    infrastructure_migration,
    policy_compliance_migration,
    domain_migration,
])
for marker in required:
    assert marker in blob, f'missing owner platform marker: {marker}'

# Owner UI/RPCs must stay on platform metadata only.
forbidden = [
    "from('debts')",
    'from("debts")',
    "from('payments')",
    'from("payments")',
    "from('notifications')",
    'from("notifications")',
    'get_tenant_export',
    'customer_id',
    'receipt_image',
    'financial_timeline',
]
for screen in (health, subscription, security, support, operations, entitlements, recovery_devices, backup_resilience, readiness, release_center, infrastructure, policy_compliance, domain_center):
    for token in forbidden:
        assert token not in screen, f'owner UI crosses privacy boundary: {token}'

for migration in (health_migration, subscription_migration, security_migration, support_migration, operations_migration, entitlements_migration, recovery_device_migration, backup_resilience_migration, readiness_migration, release_migration, infrastructure_migration, policy_compliance_migration, domain_migration):
    for token in (
        'public.debts',
        'public.payments',
        'public.notifications',
        'public.receipts',
        'public.customer_push_link_tokens',
    ):
        assert token not in migration, f'owner RPC crosses privacy boundary: {token}'

assert 'subscription_payments' in health_migration, 'platform billing health missing'
assert 'tenant_backups' in health_migration, 'backup health missing'
assert 'owner_platform_audit' in health_migration, 'owner audit source missing'
assert 'subscription_payments' in subscription_migration, 'subscription center billing metadata missing'
assert 'owner_platform_audit' in subscription_migration, 'subscription changes must be audited'
assert 'market_name' in subscription_migration, 'subscription center needs tenant identity metadata'
assert 'debt' not in subscription.lower(), 'subscription UI must not expose debt data'
assert 'payment-ledger' not in subscription.lower(), 'subscription UI must not expose market payment ledger'
assert 'auth.sessions' in security_migration, 'security center must use auth session metadata'
assert 'auth.users' in security_migration, 'security center must use auth login metadata'
assert 'count(distinct s.ip)' in security_migration.lower(), 'security center must derive IP-change risk without exposing raw IPs'
assert "'session_id'" not in security_migration, 'security center must not expose raw session identifiers'
assert 'user_agent' not in security.lower(), 'security UI must not expose raw user agents'
assert 'ip_address' not in security.lower(), 'security UI must not expose raw IP addresses'
assert 'platform_support_tickets' in support_migration, 'support center ticket storage missing'
assert 'response_due_at' in support_migration and 'resolution_due_at' in support_migration, 'support SLA deadlines missing'
assert 'support_tier' in support_migration, 'support SLA must be tier-aware'
assert 'owner_platform_audit' in support_migration, 'support owner actions must be audited'
assert 'public.debts' not in support_migration and 'public.payments' not in support_migration, 'support center must not query market finance content'
assert 'platform_operations_config' in operations_migration, 'platform operations config missing'
assert 'maintenance_enabled' in operations_migration, 'maintenance control missing'
assert 'announcement_enabled' in operations_migration, 'platform announcement control missing'
assert 'owner_platform_audit' in operations_migration, 'operations changes must be audited'
assert 'public.debts' not in operations_migration and 'public.payments' not in operations_migration, 'operations center must not query market finance content'
assert 'customer_id' not in operations.lower(), 'operations UI must not expose customer data'
assert 'platform_feature_catalog' in entitlements_migration, 'feature catalog missing'
assert 'platform_plan_entitlements' in entitlements_migration, 'plan entitlement matrix missing'
assert 'owner_tenant_entitlement_overrides' in entitlements_migration, 'tenant override storage missing'
assert 'owner_platform_audit' in entitlements_migration, 'entitlement changes must be audited'
assert 'public.debts' not in entitlements_migration and 'public.payments' not in entitlements_migration, 'entitlements must not read market finance content'
assert 'customer_id' not in entitlements.lower(), 'entitlements UI must not expose customer data'
assert 'debt' not in entitlements.lower(), 'entitlements UI must not expose debt data'
assert 'platform_admin_devices' in recovery_device_migration, 'admin device authorization storage missing'
assert 'platform_account_recovery_events' in recovery_device_migration, 'account recovery audit storage missing'
assert 'device_policy_mode' in recovery_device_migration, 'device approval policy missing'
assert 'owner_platform_audit' in recovery_device_migration, 'recovery/device actions must be audited'
assert 'auth.refresh_tokens' in recovery_device_migration and 'auth.sessions' in recovery_device_migration, 'recovery must revoke old sessions'
assert 'public.debts' not in recovery_device_migration and 'public.payments' not in recovery_device_migration, 'recovery/device center must not read market finance content'
assert 'customer_id' not in recovery_devices.lower(), 'recovery/device UI must not expose customer data'
assert 'new_password' in recovery_function, 'recovery function must rotate password'
assert 'complete_system_owner_admin_recovery_service' in recovery_function, 'recovery function must revoke sessions and audit'
assert 'password' not in recovery_device_migration.lower().replace('password_reset', ''), 'recovery migration must not store passwords'
assert 'owner_backup_monitoring_policies' in backup_resilience_migration, 'backup monitoring policy storage missing'
assert 'tenant_backups' in backup_resilience_migration, 'backup resilience metadata source missing'
assert 'last_verified_at' in backup_resilience_migration, 'backup verification freshness missing'
assert 'owner_platform_audit' in backup_resilience_migration, 'backup policy changes must be audited'
assert 'payload' not in backup_resilience_migration.lower(), 'owner backup center must not read backup payloads'
assert 'record_counts' not in backup_resilience_migration.lower(), 'owner backup center must not read tenant record counts'
assert 'payload' not in backup_resilience.lower(), 'owner backup UI must not expose backup payloads'
assert 'record_counts' not in backup_resilience.lower(), 'owner backup UI must not expose record counts'
assert 'platform_admin_devices' in readiness_migration, 'readiness must include device posture metadata'
assert 'owner_backup_monitoring_policies' in readiness_migration, 'readiness must respect backup policy metadata'
assert 'platform_support_tickets' in readiness_migration, 'readiness must include support SLA metadata'
assert 'subscription_end' in readiness_migration, 'readiness must include subscription state'
assert 'payload' not in readiness_migration.lower(), 'readiness must not read backup payloads'
assert 'record_counts' not in readiness_migration.lower(), 'readiness must not read tenant record counts'
assert 'customer_id' not in readiness.lower(), 'readiness UI must not expose customer data'
assert 'debt' not in readiness.lower(), 'readiness UI must not expose debt data'
assert 'app_update_settings' in release_migration, 'release policy source missing'
assert 'platform_admin_devices' in release_migration, 'release compliance telemetry missing'
assert 'minimum_build' in release_migration, 'minimum supported build missing'
assert 'owner_platform_audit' in release_migration, 'release policy changes must be audited'
assert 'public.debts' not in release_migration and 'public.payments' not in release_migration, 'release center must not read market finance content'
assert 'customer_id' not in release_center.lower(), 'release UI must not expose customer data'
assert 'debt' not in release_center.lower(), 'release UI must not expose debt data'
assert 'cron.job' in infrastructure_migration, 'infrastructure center must inspect scheduled jobs'
assert 'cron.job_run_details' in infrastructure_migration, 'infrastructure center must inspect recent job runs'
assert 'notification_outbox' in infrastructure_migration, 'infrastructure center must aggregate push queue health'
assert 'notification_deliveries' in infrastructure_migration, 'infrastructure center must aggregate delivery health'
assert 'customer_push_subscriptions' in infrastructure_migration, 'infrastructure center must aggregate active push devices'
for sensitive in ('customer_id', 'market_id', 'payload', 'endpoint', 'user_agent', 'last_error', 'return_message', 'command'):
    assert sensitive not in infrastructure_migration.lower(), f'infrastructure RPC exposes sensitive detail: {sensitive}'
assert 'customer_id' not in infrastructure.lower(), 'infrastructure UI must not expose customer data'
assert 'market_id' not in infrastructure.lower(), 'infrastructure UI must not expose tenant delivery detail'
assert 'payload' not in infrastructure.lower(), 'infrastructure UI must not expose notification payloads'

assert 'platform_policy_documents' in policy_compliance_migration, 'policy document storage missing'
assert 'platform_policy_acceptances' in policy_compliance_migration, 'policy acceptance storage missing'
assert 'platform_retention_policy' in policy_compliance_migration, 'retention policy storage missing'
assert 'requires_reacceptance' in policy_compliance_migration, 'policy re-acceptance control missing'
assert 'owner_platform_audit' in policy_compliance_migration, 'policy changes must be audited'
assert 'public.debts' not in policy_compliance_migration and 'public.payments' not in policy_compliance_migration, 'policy center must not read market finance content'
assert 'customer_id' not in policy_compliance.lower(), 'policy UI must not expose customer data'
assert 'debt' not in policy_compliance.lower(), 'policy UI must not expose debt data'
assert 'body_markdown' in policy_compliance_migration, 'policy text body missing'
assert 'technical_log_days' in policy_compliance_migration, 'technical log retention control missing'
assert 'audit_log_days' in policy_compliance_migration, 'audit log retention control missing'

assert 'owner_tenant_domains' in domain_migration, 'tenant domain metadata storage missing'
assert 'dns_status' in domain_migration and 'https_status' in domain_migration, 'domain verification states missing'
assert 'owner_platform_audit' in domain_migration, 'domain configuration changes must be audited'
assert 'public.debts' not in domain_migration and 'public.payments' not in domain_migration, 'domain center must not read market finance content'
assert 'customer_id' not in domain_center.lower(), 'domain UI must not expose customer data'
assert 'debt' not in domain_center.lower(), 'domain UI must not expose debt data'
assert 'dns.google' in domain_function, 'domain checker must verify DNS'
assert 'https://' in domain_function, 'domain checker must verify HTTPS reachability'
assert 'system_owner_required' in domain_function, 'domain checker must enforce system owner authorization'
assert 'service_role' not in domain_center.lower(), 'domain UI must never expose service credentials'

assert "_overview['blocked_tenants']" in readiness, 'readiness internal blocked_tenants key must remain stable'
assert "item['device_policy_mode']" in readiness, 'readiness internal device policy key must remain stable'
assert "'blocked' => Colors.red" in readiness, 'readiness raw status values must remain stable'
assert "'high' => 'بەرز'" in support, 'support priority raw status values must remain stable'
assert "item['phone']" in support, 'support internal phone field must remain stable'

print('Owner platform privacy boundary verified.')

# Owner-facing UI must remain Kurdish-first. Internal RPC/status keys may stay
# English, but visible titles/actions below must not regress to English.
owner_ui_files = [
    Path('lib/screens/auth/owner_dashboard.dart'),
    Path('lib/screens/auth/owner_backup_resilience_center_screen.dart'),
    Path('lib/screens/auth/owner_entitlements_center_screen.dart'),
    Path('lib/screens/auth/owner_health_center_screen.dart'),
    Path('lib/screens/auth/owner_infrastructure_center_screen.dart'),
    Path('lib/screens/auth/owner_operations_center_screen.dart'),
    Path('lib/screens/auth/owner_platform_center_screen.dart'),
    Path('lib/screens/auth/owner_policy_compliance_center_screen.dart'),
    Path('lib/screens/auth/owner_readiness_center_screen.dart'),
    Path('lib/screens/auth/owner_recovery_device_center_screen.dart'),
    Path('lib/screens/auth/owner_security_center_screen.dart'),
    Path('lib/screens/auth/owner_subscription_center_screen.dart'),
    Path('lib/screens/auth/owner_support_center_screen.dart'),
    Path('lib/screens/auth/owner_domain_center_screen.dart'),
    Path('lib/screens/auth/update_control_screen.dart'),
    Path('lib/screens/auth/import_permission_screen.dart'),
]
owner_ui_blob = '\n'.join(path.read_text(errors='ignore') for path in owner_ui_files)
for forbidden_ui in (
    "'Infrastructure Health'",
    "'Policy & Compliance'",
    "'Tenant Readiness'",
    "'Platform Operations'",
    "'Feature Entitlements'",
    "'Support Center'",
    "'Recovery & Device Authorization'",
    "'Backup & Resilience'",
    "'Revoke Sessions'",
    "'Account Recovery'",
    "'Device Policy'",
    "'Release & Auto Update Center'",
    "'Domain & HTTPS'",
    "'Import کراوە",
):
    assert forbidden_ui not in owner_ui_blob, f'English owner UI regressed: {forbidden_ui}'

