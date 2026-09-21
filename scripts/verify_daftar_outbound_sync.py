#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
migration = (
    ROOT / 'supabase/migrations/20260920182000_daftar_outbound_sync_scaffold.sql'
).read_text(errors='ignore')
activation = (
    ROOT / 'supabase/migrations/20260920183500_daftar_outbound_activation.sql'
).read_text(errors='ignore')
mutations = (
    ROOT / 'supabase/migrations/20260921103000_daftar_bidirectional_mutations.sql'
).read_text(errors='ignore')
worker = (ROOT / 'supabase/functions/daftar-outbound-sync/index.ts').read_text(errors='ignore')
client = (ROOT / 'supabase/functions/_shared/daftar_outbound/client.ts').read_text(errors='ignore')
config = (ROOT / 'supabase/config.toml').read_text(errors='ignore')
dart = '\n'.join(p.read_text(errors='ignore') for p in (ROOT / 'lib').rglob('*.dart'))

assert 'outbound_sync_enabled boolean not null default false' in migration
assert "outbound_write_contract_status text not null default 'unverified'" in migration
assert 'create table if not exists public.daftar_outbound_events' in migration
assert "entity_kind in ('customer','debt','payment')" in migration
assert 'idempotency_key text not null unique' in migration
assert "now() + interval '2 minutes'" in migration
assert 'legacy_import_links' in migration
assert 'outbound_sync_enabled=true' in migration

assert "operation in ('create', 'update', 'delete')" in mutations
assert 'payload_snapshot jsonb' in mutations
assert 'remote_id_snapshot text' in mutations
assert 'enqueue_daftar_outbound_mutation' in mutations
assert 'after insert or update or delete on public.profiles' in mutations
assert 'after insert or update or delete on public.debts' in mutations
assert 'after insert or update or delete on public.payments' in mutations
assert "current_setting('zhirox.daftar_inbound'" in mutations

assert 'guard_daftar_outbound_account_28' in activation
assert "'daftar-outbound-sync-account-28'" in activation
assert "outbound_write_contract_status = 'verified'" in activation
assert 'outbound_sync_enabled = true' in activation
assert "sync_mode = 'zhirox_primary'" in activation
assert 'inbound_sync_enabled = true' in activation
assert "reconciliation_status = 'clean'" in activation

assert 'source.outbound_sync_enabled !== true' in worker
assert 'source.outbound_write_contract_status !== "verified"' in worker
assert 'source.sync_mode !== "zhirox_primary"' in worker
assert 'ambiguous_remote_write' in worker
assert 'ambiguous_remote_http_' in worker
assert 'remote_rejected_' in worker
assert 'legacy_import_links' in worker
assert 'daftar_sync_seen' in worker
assert 'payment_allocation' in worker
assert 'customer_mapping_pending' in worker
assert 'ambiguous_remote_write_waiting_for_inbound_reconciliation' in worker
assert 'sent_with_blank_phone_fallback' not in worker
assert 'buildContactUpdate' in worker
assert 'buildTransactionUpdate' in worker
assert 'buildDaftarDelete' in worker
assert 'event.operation === "delete"' in worker
assert 'event.operation === "update"' in worker

assert 'path: "contacts"' in client
assert 'path: "transactions"' in client
assert 'method: "POST"' in client
assert 'api-daftar-qarz.kasbkar.net' in client
assert 'created_at' in client and 'updated_at' in client
assert 'transaction_type' in client
assert 'transaction_date' in client
assert 'method: "PUT"' in client
assert 'method: "DELETE"' in client

assert '[functions.daftar-outbound-sync]' in config
assert 'verify_jwt = false' in config
assert 'api-daftar-qarz.kasbkar.net' not in dart
assert 'daftar-outbound-sync' not in dart

print('Daftar guarded outbound create/update/delete sync verified')
