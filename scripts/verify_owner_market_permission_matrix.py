#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'supabase/migrations/20260930170152_owner_market_permission_matrix_v1.sql'
SERVICE = ROOT / 'lib/services/owner_permission_service.dart'
SCREEN = ROOT / 'lib/screens/auth/owner_market_permission_matrix_screen.dart'
CENTER = ROOT / 'lib/screens/auth/owner_permission_center_screen.dart'


def fail(message: str) -> None:
    print(f'OWNER_MARKET_PERMISSION_MATRIX_FAILED: {message}', file=sys.stderr)
    raise SystemExit(1)


for path in (MIGRATION, SERVICE, SCREEN, CENTER):
    if not path.exists():
        fail(f'missing file: {path.relative_to(ROOT)}')

sql = MIGRATION.read_text(encoding='utf-8')
service = SERVICE.read_text(encoding='utf-8')
screen = SCREEN.read_text(encoding='utf-8')
center = CENTER.read_text(encoding='utf-8')

for token in (
    'get_system_owner_market_permission_matrix',
    'set_system_owner_market_permission_matrix',
    "private.system_owner_has_permission('owner_access_console'",
    "'market' = any(c.scopes)",
    "'admin' = any(c.scopes)",
    "v_mode not in ('inherit','allow','deny')",
    'owner_permission_grants',
    'market_permission_matrix_updated',
    'jsonb_array_length(p_changes) > 200',
    'permission_change_reason_required',
):
    if token not in sql:
        fail(f'migration lost required contract: {token}')

if 'security definer' not in sql.lower():
    fail('matrix RPCs must stay SECURITY DEFINER with explicit owner checks')
if 'revoke all on function public.get_system_owner_market_permission_matrix(uuid) from public, anon;' not in sql:
    fail('matrix fetch public/anon revoke missing')
if 'revoke all on function public.set_system_owner_market_permission_matrix(uuid,jsonb,text) from public, anon;' not in sql:
    fail('matrix save public/anon revoke missing')
if 'grant execute on function public.get_system_owner_market_permission_matrix(uuid) to authenticated;' not in sql:
    fail('matrix fetch authenticated grant missing')
if 'grant execute on function public.set_system_owner_market_permission_matrix(uuid,jsonb,text) to authenticated;' not in sql:
    fail('matrix save authenticated grant missing')

for token in (
    'expectedPermissionCount = 200',
    "get_system_owner_market_permission_matrix",
    "set_system_owner_market_permission_matrix",
    'OwnerMarketPermissionMatrix',
    'fetchMarkets()',
    'saveMarketMatrix',
):
    if token not in service:
        fail(f'service lost required contract: {token}')

for token in (
    "'inherit'",
    "'allow'",
    "'deny'",
    'Allow هەموو',
    'Deny هەموو',
    'هەمووی Inherit',
    '_ReasonDialog',
    'matrix.editableCount',
):
    if token not in screen:
        fail(f'UI lost matrix control: {token}')

if 'OwnerMarketPermissionMatrixScreen' not in center:
    fail('Owner Permission Center no longer links to market matrix')

print('OWNER_MARKET_PERMISSION_MATRIX_OK total=200 modes=inherit/allow/deny audit=enabled')
