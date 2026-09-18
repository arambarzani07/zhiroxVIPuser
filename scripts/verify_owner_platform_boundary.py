from pathlib import Path

dashboard = Path('lib/screens/auth/owner_dashboard.dart').read_text()
health = Path('lib/screens/auth/owner_health_center_screen.dart').read_text()
subscription = Path('lib/screens/auth/owner_subscription_center_screen.dart').read_text()
service = Path('lib/services/pb_service.dart').read_text()
health_migration = Path(
    'supabase/migrations/20260918135500_owner_health_audit_center.sql'
).read_text()
subscription_migration = Path(
    'supabase/migrations/20260918162000_owner_subscription_center.sql'
).read_text()

required = [
    'OwnerHealthCenterScreen',
    'OwnerSubscriptionCenterScreen',
    'getOwnerHealthOverview',
    'getOwnerPlatformAuditPage',
    'getOwnerSubscriptionOverview',
    'getOwnerSubscriptionsPage',
    'setOwnerSubscription',
    'get_system_owner_health_overview',
    'get_system_owner_platform_audit_page',
    'get_system_owner_subscription_overview',
    'get_system_owner_subscriptions_page',
    'set_system_owner_subscription',
    'system_owner_required',
]
blob = '\n'.join([
    dashboard,
    health,
    subscription,
    service,
    health_migration,
    subscription_migration,
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
for screen in (health, subscription):
    for token in forbidden:
        assert token not in screen, f'owner UI crosses privacy boundary: {token}'

for migration in (health_migration, subscription_migration):
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

print('Owner platform privacy boundary verified.')
