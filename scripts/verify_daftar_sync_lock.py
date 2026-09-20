#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
worker = (ROOT / 'supabase/functions/daftar-sync/index.ts').read_text(errors='ignore')
worker_auth = (ROOT / 'supabase/functions/_shared/daftar_sync_auth.ts').read_text(errors='ignore')
gateway = (ROOT / 'supabase/functions/daftar-sync-gateway/index.ts').read_text(errors='ignore')
config = (ROOT / 'supabase/config.toml').read_text(errors='ignore')
migration_path = ROOT / 'supabase/migrations/20260919230000_lock_daftar_sync_connection.sql'
migration = migration_path.read_text(errors='ignore') if migration_path.exists() else ''
workflow = (ROOT / '.github/workflows/ios-unsigned-ipa.yml').read_text(errors='ignore')

for source in (worker + '\n' + worker_auth, gateway):
    assert 'x-daftar-sync-secret' in source, 'Daftar sync must require the dedicated sync secret'
    assert 'trigger_secret_hash' in source, 'Daftar sync must validate the stored trigger secret hash'
    assert 'constantTimeEqual' in source, 'Daftar sync secret comparison must stay constant-time'
    assert 'legacy_user_id' in source, 'Daftar sync must remain scoped to the legacy account'
    assert 'SUPABASE_SERVICE_ROLE_KEY' in source, 'Daftar sync server access must retain service-role support'

assert 'authorizeDaftarSyncRequest' in worker, 'worker must use the shared authorization helper'
assert 'serviceCredential' in worker_auth, 'shared auth must retain server-to-server service credential support'

assert '[functions.daftar-sync]\nverify_jwt = false' in config, 'worker deployment auth mode must be pinned'
assert '[functions.daftar-sync-gateway]\nverify_jwt = false' in config, 'gateway deployment auth mode must be pinned'

assert 'prevent_daftar_sync_account_28_breakage' in migration, 'account 28 source must have an immutable connection trigger'
assert "trigger_secret_hash = v_secret_hash" in migration, "guardian must re-bind the source to the Vault secret"
assert "cron.alter_job(" in migration, "guardian must repair the live cron definition"
assert 'guard_daftar_sync_account_28' in migration, 'Daftar sync must have a self-healing guardian'
assert 'daftar-sync-guardian-account-28' in migration, 'guardian cron must be installed'
assert "daftar-live-sync-account-28" in migration, 'live sync cron identity must be pinned'
assert "https://api-daftar-qarz.kasbkar.net/api/v1" in migration, 'legacy API endpoint must be pinned'
assert "daftar_sync_account_28_trigger" in migration, 'Vault secret name must be pinned'
assert "daftar-live-account-28-v1" in migration, 'source fingerprint must be pinned'

assert 'Verify Daftar Qarz connection lock' in workflow, 'every build must verify the Daftar connection lock'

migration_files = list((ROOT / 'supabase/migrations').glob('*.sql'))
destructive_sql = '\n'.join(
    path.read_text(errors='ignore').lower()
    for path in migration_files
    if path.name != '20260919230000_lock_daftar_sync_connection.sql'
)
for forbidden in (
    "cron.unschedule('daftar-live-sync-account-28'",
    'cron.unschedule("daftar-live-sync-account-28"',
    "delete from public.daftar_sync_sources",
    "drop table public.daftar_sync_sources",
    "drop function public.guard_daftar_sync_account_28",
):
    assert forbidden not in destructive_sql, f'forbidden Daftar connection mutation detected: {forbidden}'

print('Daftar Qarz connection lock verified')
