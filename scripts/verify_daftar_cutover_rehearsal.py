#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
migration = (ROOT / 'supabase/migrations/20260920003000_daftar_cutover_rehearsal.sql').read_text(errors='ignore')
worker = (ROOT / 'supabase/functions/daftar-sync/index.ts').read_text(errors='ignore')
workflow = (ROOT / '.github/workflows/ios-unsigned-ipa.yml').read_text(errors='ignore')

assert 'legacy_import_links_admin_kind_source_idx' in migration
assert 'legacy_import_links_payment_base_idx' in migration
assert 'daftar_cutover_rehearsal_runs' in migration
assert 'run_daftar_cutover_rehearsal' in migration
assert 'cutover_rehearsal_status' in migration
assert 'cutover_rehearsal_mismatches' in migration
assert 'loan_amount_mismatches' in migration
assert 'loan_currency_mismatches' in migration
assert 'payment_amount_mismatches' in migration
assert 'payment_currency_mismatches' in migration
assert 'zero_event_mismatches' in migration
assert "case when v_total_mismatches = 0 then 'pass' else 'fail' end" in migration
assert "s.cutover_rehearsal_status = 'pass'" in migration
assert "s.cutover_rehearsal_mismatches = 0" in migration

assert 'run_daftar_cutover_rehearsal' in worker
assert 'cutover_rehearsal_failed' in worker
assert 'Verify Daftar cutover rehearsal' in workflow

print('Daftar cutover rehearsal verified')
