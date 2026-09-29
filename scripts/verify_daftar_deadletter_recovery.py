#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

migration = ROOT / "supabase/migrations/20260925071439_daftar_deadletter_auto_recovery.sql"
sync_edge = ROOT / "supabase/functions/daftar-sync/index.ts"
runtime_hardening = ROOT / "supabase/migrations/20260929170500_daftar_sync_runtime_hardening.sql"

assert migration.exists(), "Daftar dead-letter auto-recovery migration missing"
assert sync_edge.exists(), "Daftar sync Edge Function missing"
assert runtime_hardening.exists(), "Daftar runtime hardening migration missing"

sql = migration.read_text(errors="ignore")
edge = sync_edge.read_text(errors="ignore")
runtime = runtime_hardening.read_text(errors="ignore")

required_sql = (
    "public.resolve_daftar_recovered_dead_letters",
    "resolved_after_clean_reconciliation",
    "resolved_after_passing_cutover_rehearsal",
    "reconciliation_failed",
    "cutover_rehearsal_failed",
    "to service_role",
)
for marker in required_sql:
    assert marker in sql, f"missing dead-letter recovery SQL contract: {marker}"

assert (
    "grant execute on function public.resolve_daftar_recovered_dead_letters(uuid)"
    in sql.lower()
)
assert "to authenticated" not in sql.lower().split(
    "grant execute on function public.resolve_daftar_recovered_dead_letters(uuid)",
    1,
)[1].split(";", 1)[0]

required_edge = (
    "resolveAbsentTransactionDeadLetters",
    "daftar_inbound_missing_candidates",
    "missingCount < 2",
    "source_transaction_absent_from_two_consecutive_full_snapshots",
)
for marker in required_edge:
    assert marker in edge, f"missing dead-letter Edge contract: {marker}"

assert "source_transaction_absent_from_current_full_snapshot" not in edge, (
    "single-snapshot financial dead-letter resolution must stay forbidden"
)

# Full reconciliation/cutover/dead-letter recovery now belongs to the durable
# database runtime-hardening job, not the latency-sensitive sync Edge request.
required_runtime = (
    "private.reconcile_daftar_source",
    "private.run_daftar_sync_reconciliation",
    "public.run_daftar_cutover_rehearsal",
    "public.resolve_daftar_recovered_dead_letters",
)
for marker in required_runtime:
    assert marker in runtime, f"missing runtime hardening contract: {marker}"

projection_call = runtime.index("private.reconcile_daftar_source")
integrity_call = runtime.index("private.run_daftar_sync_reconciliation")
cutover_call = runtime.index("public.run_daftar_cutover_rehearsal")
resolve_call = runtime.index("public.resolve_daftar_recovered_dead_letters")
assert projection_call < cutover_call
assert integrity_call < cutover_call < resolve_call

absent_fn = edge.index("async function resolveAbsentTransactionDeadLetters")
two_snapshot_note = edge.index(
    "source_transaction_absent_from_two_consecutive_full_snapshots",
    absent_fn,
)
assert absent_fn < two_snapshot_note

print("Daftar dead-letter recovery safety verified")
