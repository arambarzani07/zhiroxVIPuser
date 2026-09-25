#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
migration = (ROOT / 'supabase/migrations/20260919235500_daftar_shadow_reconciliation.sql').read_text(errors='ignore')
worker = (ROOT / 'supabase/functions/daftar-sync/index.ts').read_text(errors='ignore')
workflow = (ROOT / '.github/workflows/ios-unsigned-ipa.yml').read_text(errors='ignore')

assert 'daftar_reconciliation_runs' in migration
assert 'reconcile_daftar_account_28' in migration
assert 'reconciliation_missing_contacts' in migration
assert 'reconciliation_missing_transactions' in migration
assert 'reconciliation_status' in migration
assert "event_type" in migration and "debt_created" in migration and "payment_created" in migration
assert "legacy_zero_amount" in migration
assert "daftar_live_sync_reconcile" in migration
assert "entity_kind, source_id" in migration
assert "cutover_ready" in migration
assert "reconciliation_missing_contacts = 0" in migration
assert "reconciliation_missing_transactions = 0" in migration

assert "reconcile_daftar_account_28" in worker
assert "p_source_id: source.id" in worker
assert "reconciliation_failed" in worker
assert "resolve_daftar_recovered_dead_letters" in worker
assert "dead_letter_recovery" in worker

assert 'Verify Daftar shadow reconciliation' in workflow

print('Daftar shadow reconciliation verified')