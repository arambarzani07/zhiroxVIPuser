from pathlib import Path

dashboard = Path('lib/screens/auth/owner_dashboard.dart').read_text()
health = Path('lib/screens/auth/owner_health_center_screen.dart').read_text()
subscription = Path('lib/screens/auth/owner_subscription_center_screen.dart').read_text()
security = Path('lib/screens/auth/owner_security_center_screen.dart').read_text()
support = Path('lib/screens/auth/owner_support_center_screen.dart').read_text()
operations = Path('lib/screens/auth/owner_operations_center_screen.dart').read_text()
entitlements = Path('lib/screens/auth/owner_entitlements_center_screen.dart').read_text()
service = Path('lib/services/pb_service.dart').read_text()
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

required = [
    'OwnerHealthCenterScreen',
    'OwnerSubscriptionCenterScreen',
    'OwnerSecurityCenterScreen',
    'OwnerSupportCenterScreen',
    'OwnerOperationsCenterScreen',
    'OwnerEntitlementsCenterScreen',
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
    'getOwnerEntitlementsPage',
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
    'set_system_owner_plan_entitlement',
    'set_system_owner_tenant_entitlement',
    'get_platform_entitlements_state',
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
    service,
    health_migration,
    subscription_migration,
    security_migration,
    support_migration,
    operations_migration,
    entitlements_migration,
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
for screen in (health, subscription, security, support, operations, entitlements):
    for token in forbidden:
        assert token not in screen, f'owner UI crosses privacy boundary: {token}'

for migration in (health_migration, subscription_migration, security_migration, support_migration, operations_migration, entitlements_migration):
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

print('Owner platform privacy boundary verified.')
