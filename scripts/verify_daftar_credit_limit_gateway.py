#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
fn = (root / 'supabase/functions/daftar-credit-gateway/index.ts').read_text()
migration = (root / 'supabase/migrations/20260920222500_daftar_credit_limit_gateway.sql').read_text()
config = (root / 'supabase/config.toml').read_text()

required_fn = [
    "const LEGACY_USER_ID = 28",
    "const SOURCE_FINGERPRINT = 'daftar-live-account-28-v1'",
    "credit_limit_exceeded",
    "current_balance_unavailable",
    "legacy_import_links",
    "debt_limit",
    "transaction_type",
    "PAYMENT",
    "LOAN",
]
for marker in required_fn:
    assert marker in fn, marker

assert "if (txType === 'LOAN' || txType === 'DEBT')" in fn
assert "projectedBalance > debtLimit" in fn
assert "OLD_BASE + path" in fn
assert "delete from public.profiles" not in fn.lower()
assert "delete from public.debts" not in fn.lower()
assert "delete from public.payments" not in fn.lower()

for marker in [
    'daftar_credit_limit_gateway_events',
    'enable row level security',
    'revoke all on table public.daftar_credit_limit_gateway_events from public, anon, authenticated',
]:
    assert marker in migration.lower(), marker

assert '[functions.daftar-credit-gateway]' in config
assert 'verify_jwt = false' in config
print('Daftar credit-limit gateway guard verified.')
