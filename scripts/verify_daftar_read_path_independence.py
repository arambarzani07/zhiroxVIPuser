#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
lib_root = ROOT / 'lib'

forbidden = (
    'api-daftar-qarz.kasbkar.net',
    '/functions/v1/daftar-sync-gateway',
    "functions.invoke(\n      'daftar-sync'",
    "functions.invoke('daftar-sync'",
    "functions.invoke(\n      'daftar-sync-gateway'",
    "functions.invoke('daftar-sync-gateway'",
)

violations = []
for path in lib_root.rglob('*.dart'):
    text = path.read_text(errors='ignore')
    for needle in forbidden:
        if needle in text:
            violations.append(f'{path.relative_to(ROOT)} -> {needle}')

assert not violations, (
    'ZHIROX client must never read Daftar Qarz directly; '
    'all user-facing reads must come from ZHIROX/Supabase. '
    + '; '.join(violations)
)

dashboard = (ROOT / 'lib/screens/admin/daftar_sync_dashboard_screen.dart').read_text(errors='ignore')
assert "PBService.client.rpc('get_my_daftar_sync_dashboard')" in dashboard
assert "PBService.client.rpc('request_my_daftar_sync')" in dashboard

print('Daftar read-path independence verified')
