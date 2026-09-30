#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
EDGE = ROOT / 'supabase/functions/account-admin/index.ts'
BRIDGE = ROOT / 'supabase/migrations/20260930161629_owner_account_admin_service_authorization.sql'


def fail(message: str) -> None:
    print(f'OWNER_ACCOUNT_ADMIN_GOVERNANCE_FAILED: {message}', file=sys.stderr)
    raise SystemExit(1)


def require(text: str, token: str, label: str) -> None:
    if token not in text:
        fail(f'{label}: missing {token}')


def before(text: str, first: str, second: str, label: str) -> None:
    a = text.find(first)
    b = text.find(second)
    if a < 0 or b < 0 or a >= b:
        fail(f'{label}: expected {first!r} before {second!r}')


def main() -> None:
    if not EDGE.exists() or not BRIDGE.exists():
        fail('account-admin source or authorization bridge migration is missing')

    edge = EDGE.read_text(encoding='utf-8')
    bridge = BRIDGE.read_text(encoding='utf-8')

    edge_tokens = (
        'authorize_system_owner_account_admin_service',
        'owner_create_admin',
        'owner_create_market',
        'owner_create_subscription',
        'owner_view_all_admins',
        'owner_renew_subscription',
        'owner_extend_subscription_days',
        'owner_change_subscription_plan',
        'owner_tenant_member_management_forbidden',
        'admin_recovery_requires_dedicated_endpoint',
        'admin_account_created',
        'subscription_renewed_via_account_admin',
        'owner_audit_failed',
    )
    for token in edge_tokens:
        require(edge, token, 'edge')

    before(edge, '"owner_create_admin"', 'admin.auth.admin.createUser(', 'create-admin authorization')
    before(edge, '"owner_view_all_admins"', '.select(\n          "id,name,phone,role,market_name', 'list-admin authorization')
    before(edge, '"owner_renew_subscription"', '.update({\n          subscription_plan:', 'renew authorization')

    if edge.count('owner_tenant_member_management_forbidden') < 3:
        fail('Owner tenant-member privacy boundary must cover create/reset/delete paths')

    bridge_tokens = (
        'authorize_system_owner_account_admin_service',
        "auth.role() <> 'service_role'",
        'private.system_owner_has_permission',
        "when 'owner_view_all_admins'",
        "when 'owner_create_admin'",
        "when 'owner_create_market'",
        "when 'owner_create_subscription'",
        "when 'owner_renew_subscription'",
        "when 'owner_extend_subscription_days'",
        "when 'owner_change_subscription_plan'",
        'account_admin_permission_not_allowed',
        'from public, anon, authenticated;',
        'to service_role;',
    )
    for token in bridge_tokens:
        require(bridge, token, 'bridge')

    if 'to authenticated;' in bridge:
        fail('service authorization bridge must not be executable by authenticated clients')

    print('OWNER_ACCOUNT_ADMIN_GOVERNANCE_OK create=list=renew=guarded tenant_member_privacy=closed service_bridge=service_role_only')


if __name__ == '__main__':
    main()
