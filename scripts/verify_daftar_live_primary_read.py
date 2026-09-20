#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
dart = '\n'.join(
    p.read_text(encoding='utf-8', errors='ignore')
    for p in (root / 'lib').rglob('*.dart')
)
runtime = (root / 'supabase/functions/_shared/daftar_live_read/runtime.ts').read_text(encoding='utf-8')
entrypoint = (root / 'supabase/functions/daftar-live-read/index.ts').read_text(encoding='utf-8')
policy = (root / 'supabase/functions/_shared/daftar_live_read/policy.ts').read_text(encoding='utf-8')
config = (root / 'supabase/config.toml').read_text(encoding='utf-8')

assert 'api-daftar-qarz.kasbkar.net' not in dart
assert 'x-daftar-sync-secret' not in dart
assert 'SUPABASE_SERVICE_ROLE_KEY' not in dart
assert "'daftar-live-read'" in dart

assert 'isFallbackEligible' in runtime
for operation in (
    'customer_directory',
    'customer_finance_snapshot',
    'admin_dashboard',
    'admin_all_debts',
    'employee_stats',
):
    assert operation in runtime, f'missing runtime operation: {operation}'

assert '[functions.daftar-live-read]\nverify_jwt = false' in config
assert 'admin.auth.getUser' in entrypoint
assert 'legacy_user_id' in entrypoint
assert 'live_read_mode' in entrypoint

for code in ('authentication', 'authorization', 'integrity', 'unsupported'):
    assert code in policy, f'missing non-fallback policy: {code}'

print('Daftar live-primary read security contract verified.')
