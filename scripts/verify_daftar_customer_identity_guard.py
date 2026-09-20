#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
migration = (
    ROOT
    / 'supabase/migrations/20260920213938_daftar_customer_link_integrity_guard.sql'
).read_text(errors='ignore')
sync = (
    ROOT / 'supabase/functions/daftar-sync/index.ts'
).read_text(errors='ignore')

for marker in (
    'daftar_customer_link_archive',
    'reconcile_daftar_customer_identity_links',
    'legacy_import_links_customer_target_unique',
    'daftar_sync_seen_customer_target_unique',
    'official_total_customers',
    'source_contact_absent_from_current_daftar_snapshot',
    'removed_stale_seen_rows',
    'removed_stale_mirror_rows',
):
    assert marker in migration, f'missing customer identity integrity marker: {marker}'

assert 'enable row level security' in migration.lower()
assert (
    'revoke all on table public.daftar_customer_link_archive '
    'from public, anon, authenticated'
) in migration
assert (
    'revoke all on function '
    'public.reconcile_daftar_customer_identity_links(uuid,text[],integer)'
) in migration
assert 'grant execute on function public.reconcile_daftar_customer_identity_links' in migration
assert 'to service_role' in migration

for forbidden in (
    'delete from public.profiles',
    'delete from public.debts',
    'delete from public.payments',
):
    assert forbidden not in migration.lower(), (
        f'customer identity cleanup must not delete business data: {forbidden}'
    )

assert '.eq("source_fingerprint", source.source_fingerprint)' in sync
assert 'reconcile_daftar_customer_identity_links' in sync
assert 'p_current_contact_ids: currentContactIds' in sync
assert 'p_expected_count: officialContactTotals.length' in sync
assert (
    'customer_identity_reconciliation: customerIdentityReconciliation'
) in sync

print('Daftar customer identity integrity guard verified')
