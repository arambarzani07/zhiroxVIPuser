from pathlib import Path

root = Path(__file__).resolve().parents[1]
plan_migration = root / 'supabase/migrations/20260930175648_owner_plan_resource_limits_v1.sql'
enforce_migration = root / 'supabase/migrations/20260930175716_enforce_tenant_profile_plan_limits.sql'
service = root / 'lib/services/owner_plan_control_service.dart'
screen = root / 'lib/screens/auth/owner_plan_market_control_screen.dart'
matrix = root / 'lib/screens/auth/owner_market_permission_matrix_screen.dart'

for path in (plan_migration, enforce_migration, service, screen, matrix):
    if not path.exists():
        raise SystemExit(f'missing required file: {path.relative_to(root)}')

plan_sql = plan_migration.read_text()
for token in (
    'platform_limit_catalog',
    'platform_plan_limits',
    'owner_tenant_limit_overrides',
    'get_effective_tenant_limit',
    'service_get_tenant_limit',
    'get_system_owner_plan_limits',
    'set_system_owner_plan_limit',
    'get_system_owner_tenant_limits',
    'set_system_owner_tenant_limit_override',
    "('staff_limit'",
    "('customer_limit'",
    "('device_limit'",
    'register_platform_admin_device',
):
    if token not in plan_sql:
        raise SystemExit(f'plan limit contract missing: {token}')

trigger_sql = enforce_migration.read_text()
for token in (
    'enforce_tenant_profile_plan_limits',
    "new.role='employee'",
    "new.role='customer'",
    'tenant_staff_limit_reached',
    'tenant_customer_limit_reached',
    'before insert or update of role,admin_id,active',
):
    if token not in trigger_sql:
        raise SystemExit(f'limit enforcement contract missing: {token}')

service_text = service.read_text()
for rpc in (
    'get_system_owner_plan_limits',
    'set_system_owner_plan_limit',
    'get_system_owner_tenant_limits',
    'set_system_owner_tenant_limit_override',
    'set_system_owner_tenant_feature_plan',
):
    if rpc not in service_text:
        raise SystemExit(f'Owner plan service missing RPC: {rpc}')

screen_text = screen.read_text()
for token in ('پلانی مارکێت', 'کارمەند', 'کڕیار', 'ئامێر', 'override'):
    if token not in screen_text:
        raise SystemExit(f'Owner plan UI missing concept: {token}')

matrix_text = matrix.read_text()
if 'OwnerPlanMarketControlScreen' not in matrix_text:
    raise SystemExit('Market permission matrix is not linked to plan/limit controls')

print('Owner plan + market control contract verified')
