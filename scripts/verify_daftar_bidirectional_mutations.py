#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
migration = (
    ROOT / 'supabase/migrations/20260921103000_daftar_bidirectional_mutations.sql'
).read_text(errors='ignore')
inbound = (ROOT / 'supabase/functions/daftar-sync/index.ts').read_text(errors='ignore')
outbound = (
    ROOT / 'supabase/functions/daftar-outbound-sync/index.ts'
).read_text(errors='ignore')
client = (
    ROOT / 'supabase/functions/_shared/daftar_outbound/client.ts'
).read_text(errors='ignore')

for marker in (
    "operation in ('create', 'update', 'delete')",
    'payload_snapshot jsonb',
    'remote_id_snapshot text',
    'daftar_inbound_missing_candidates',
    'enqueue_daftar_outbound_mutation',
    "current_setting('zhirox.daftar_inbound'",
    'apply_daftar_inbound_customer_update',
    'apply_daftar_inbound_debt_update',
    'remove_daftar_inbound_payment',
    'delete_daftar_inbound_debt',
    'delete_daftar_inbound_customer',
):
    assert marker in migration, marker

for table in ('profiles', 'debts', 'payments'):
    assert f'after insert or update or delete on public.{table}' in migration

for marker in (
    'confirmMissingSourceIds',
    'pruneMirrorRows',
    'updated_customers',
    'updated_debts',
    'updated_payments',
    'deleted_customers',
    'deleted_debts',
    'deleted_payments',
    'apply_daftar_inbound_customer_update',
    'apply_daftar_inbound_debt_update',
    'remove_daftar_inbound_payment',
    'delete_daftar_inbound_debt',
    'delete_daftar_inbound_customer',
    'forceFullSnapshot',
):
    assert marker in inbound, marker

for marker in (
    'buildContactUpdate',
    'buildTransactionUpdate',
    'buildDaftarDelete',
    'payload_snapshot',
    'remote_id_snapshot',
    'event.operation === "update"',
    'event.operation === "delete"',
):
    assert marker in outbound, marker

for marker in (
    'export function buildContactUpdate',
    'export function buildTransactionUpdate',
    'export function buildDaftarDelete',
    'method: "PUT"',
    'method: "DELETE"',
):
    assert marker in client, marker

assert "set_config('zhirox.daftar_inbound', 'on', true)" in migration
assert 'if (count >= 2) confirmed.push(sourceId)' in inbound
assert 'request.method === "DELETE" && response.status === 404' in outbound
assert 'customer_auth_sync_skipped' in inbound
assert 'customer_auth_lookup_failed' not in inbound
assert 'existingHash !== undefined && existingHash !== hash' in inbound
assert '.slice(0, 5)' in inbound
assert 'const hasMoreTransactions = deltaById.size > delta.length' in inbound
assert 'transactions_etag: hasMoreTransactions' in inbound
assert 'const reappearedTransactions: LegacyTransaction[] = []' in inbound
assert '.eq("payload_hash", "__deleted__")' in inbound
assert 'const transactionMirrorCandidates = mirrorBootstrap' in inbound
assert 'changedAt >= lastSuccessMs - 120_000' in inbound
assert 'transactionCandidateIds.slice(offset, offset + 200)' in inbound
assert 'const deletedTransactionIds = [...deletedMarkerIds]' in inbound

print('Daftar bidirectional create/update/delete sync verified')
