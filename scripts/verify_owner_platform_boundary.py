from pathlib import Path

dashboard = Path('lib/screens/auth/owner_dashboard.dart').read_text()
health = Path('lib/screens/auth/owner_health_center_screen.dart').read_text()
service = Path('lib/services/pb_service.dart').read_text()
migration = Path(
    'supabase/migrations/20260918135500_owner_health_audit_center.sql'
).read_text()

required = [
    'OwnerHealthCenterScreen',
    'getOwnerHealthOverview',
    'getOwnerPlatformAuditPage',
    'get_system_owner_health_overview',
    'get_system_owner_platform_audit_page',
    'system_owner_required',
]
blob = '\n'.join([dashboard, health, service, migration])
for marker in required:
    assert marker in blob, f'missing owner platform health marker: {marker}'

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
for token in forbidden:
    assert token not in health, f'owner health UI crosses privacy boundary: {token}'

for token in (
    'public.debts',
    'public.payments',
    'public.notifications',
    'public.receipts',
    'public.customer_push_link_tokens',
):
    assert token not in migration, f'owner health RPC crosses privacy boundary: {token}'

assert 'subscription_payments' in migration, 'platform billing health missing'
assert 'tenant_backups' in migration, 'backup health missing'
assert 'owner_platform_audit' in migration, 'owner audit source missing'

print('Owner platform privacy boundary verified.')
