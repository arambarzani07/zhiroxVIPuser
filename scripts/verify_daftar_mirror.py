#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
worker = (ROOT / 'supabase/functions/daftar-sync/index.ts').read_text(errors='ignore')
gateway = (ROOT / 'supabase/functions/daftar-sync-gateway/index.ts').read_text(errors='ignore')
migration = (ROOT / 'supabase/migrations/20260919233000_daftar_raw_mirror.sql').read_text(errors='ignore')
workflow = (ROOT / '.github/workflows/ios-unsigned-ipa.yml').read_text(errors='ignore')

assert 'daftar_mirror_contacts' in migration
assert 'daftar_mirror_transactions' in migration
assert 'mirror_bootstrapped_at' in migration
assert "sync_mode text not null default 'mirror'" in migration
assert 'get_my_daftar_mirror_status' in migration
assert 'grant execute on function public.get_my_daftar_mirror_status()' in migration and 'to authenticated;' in migration

assert 'mirror_bootstrapped_at' in worker
assert 'mirrorRows(' in worker
assert '"daftar_mirror_contacts"' in worker
assert '"daftar_mirror_transactions"' in worker
assert 'source.mirror_bootstrapped_at' in worker
assert 'contactsFetch = await fetchRows<LegacyContact>' in worker
assert '.range(offset, offset + pageSize - 1)' in worker
assert 'resolveAbsentTransactionDeadLetters' in worker
assert 'source_transaction_absent_from_two_consecutive_full_snapshots' in worker
assert 'currentTransactionIds' in worker
assert 'daftar_inbound_missing_candidates' in worker
assert 'const missingCount = Number(existing?.missing_count ?? 0) + 1' in worker
assert 'if (missingCount < 2) continue' in worker

assert 'mirror_bootstrapped_at' in gateway
assert 'source.mirror_bootstrapped_at' in gateway
assert '!contactsProbe.changed' in gateway
assert '!transactionsProbe.changed' in gateway
assert 'mustRefreshOfficialTotals' in gateway
assert 'source.sync_mode === "zhirox_primary"' in gateway
assert 'source.inbound_sync_enabled === true' in gateway
assert 'source_not_modified' in gateway

assert 'Verify Daftar raw mirror' in workflow

print('Daftar raw mirror verified')