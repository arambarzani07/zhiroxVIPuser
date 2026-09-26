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
types = (root / 'supabase/functions/_shared/daftar_live_read/types.ts').read_text(encoding='utf-8')
freshness = (root / 'supabase/functions/_shared/daftar_live_read/freshness.ts').read_text(encoding='utf-8')
event_statuses = (root / 'supabase/migrations/20260920171500_daftar_live_read_event_statuses.sql').read_text(encoding='utf-8')
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
assert 'SUPABASE_PUBLISHABLE_KEYS' in entrypoint
assert 'SUPABASE_SECRET_KEYS' in entrypoint
assert 'legacy_user_id' in entrypoint
assert 'live_read_mode' in entrypoint
assert '.eq("admin_id", tenantId)' in entrypoint
assert '.eq("enabled", true)' in entrypoint
assert 'return data;' in entrypoint
assert 'if (!source || source.enabled === false' in runtime
assert '"zhirox_primary"' in runtime
assert '.eq("legacy_user_id", 28)' not in entrypoint
assert '.eq("source_fingerprint", "daftar-live-account-28-v1")' not in entrypoint
assert '"zhirox_primary"' in types
assert 'syncMode === "zhirox_primary"' in runtime
assert 'resultSource: ReadSource' in runtime
assert 'responseSource?: ReadSource' in runtime
assert '"zhirox_primary"' in runtime
assert 'shadow_success' in event_statuses
assert 'shadow_failed' in event_statuses

for code in ('authentication', 'authorization', 'integrity', 'unsupported'):
    assert code in policy + types, f'missing non-fallback policy: {code}'

assert 'AbortSignal.timeout(4_000)' in freshness
assert 'attempt < 2' in freshness
assert 'sleep(50)' not in freshness, 'retry backoff can exceed the 8-second interactive deadline'

print('Daftar live-primary read security contract verified.')
