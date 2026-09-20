#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
migration = (ROOT / 'supabase/migrations/20260920183000_daftar_exact_projection.sql').read_text(errors='ignore')
worker = (ROOT / 'supabase/functions/daftar-sync/index.ts').read_text(errors='ignore')
workflow = (ROOT / '.github/workflows/ios-unsigned-ipa.yml').read_text(errors='ignore')

for marker in (
    'daftar_official_contact_totals',
    'official_total_customers',
    'official_total_loan_iqd',
    'official_total_payment_iqd',
    'official_balance_iqd',
    'replace_daftar_official_totals',
    'get_admin_dashboard_snapshot',
    'get_customer_directory_page',
    'get_customer_finance_snapshot',
):
    assert marker in migration, f'missing exact projection marker: {marker}'

assert '/contacts/totals-by-currency' in worker
assert '/transactions/totals-by-currency' in worker
assert 'replace_daftar_official_totals' in worker
assert 'officialTotalsFetch' in worker
assert 'officialContactTotalsFetch' in worker

assert 'Verify Daftar exact projection' in workflow
print('Daftar exact projection verified')
