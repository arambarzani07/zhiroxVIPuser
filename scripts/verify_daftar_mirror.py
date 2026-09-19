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
assert 'grant execute on function public.get_my_daftar_mirror_status() to authenticated' in migration

assert 'mirror_bootstrapped_at' in worker
assert 'mirrorRows(' in worker
assert '"daftar_mirror_contacts"' in worker
assert '"daftar_mirror_transactions"' in worker
assert 'source.mirror_bootstrapped_at' in worker
assert 'contactsFetch = await fetchRows<LegacyContact>' in worker

assert 'mirror_bootstrapped_at' in gateway
assert '!source.mirror_bootstrapped_at' in gateway
assert 'source_not_modified' in gateway

assert 'Verify Daftar raw mirror' in workflow

print('Daftar raw mirror verified')
