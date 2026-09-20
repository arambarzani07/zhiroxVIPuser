#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
migration = (
    ROOT / 'supabase/migrations/20260920174000_daftar_primary_inbound_sync.sql'
).read_text(errors='ignore')
worker = (ROOT / 'supabase/functions/daftar-sync/index.ts').read_text(errors='ignore')
gateway = (ROOT / 'supabase/functions/daftar-sync-gateway/index.ts').read_text(errors='ignore')
workflow = (ROOT / '.github/workflows/ios-unsigned-ipa.yml').read_text(errors='ignore')

assert 'inbound_sync_enabled boolean not null default false' in migration
assert "sync_mode = 'zhirox_primary'" in migration
assert 'inbound_sync_enabled = true' in migration
assert 'enabled = true' in migration
assert "active => true" in migration
assert "daftar-live-sync-account-28" in migration
assert "inbound_sync_enabled = true" in migration
assert "or inbound_sync_enabled = true" in migration.lower()
assert 'reconcile_daftar_account_28' in worker
assert 'run_daftar_cutover_rehearsal' in worker

assert 'inbound_sync_enabled' in worker
assert 'sync_mode' in worker
assert 'allowInboundSync' in worker
assert 'refresh_daftar_failover_readiness' in worker

assert 'inbound_sync_enabled' in gateway
assert 'sync_mode' in gateway

assert 'Verify Daftar primary inbound sync' in workflow

print('Daftar primary inbound one-way sync verified')
