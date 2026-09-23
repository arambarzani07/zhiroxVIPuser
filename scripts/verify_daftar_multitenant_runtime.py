#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "supabase/migrations/20260923192046_harden_multitenant_daftar_runtime.sql"
assert path.exists(), "multi-tenant Daftar runtime migration missing"
sql = path.read_text(errors="ignore")
low = sql.lower()

required = (
    "private.daftar_source_fingerprint_aliases",
    "primary key (sync_source_id, source_fingerprint)",
    "private.prevent_daftar_sync_source_breakage",
    "private.reconcile_daftar_source",
    "private.dispatch_daftar_sync_sources",
    "private.reconcile_daftar_sync_sources",
    "private.run_daftar_tenant_backups",
    "private.guard_daftar_sync_sources",
    "private.current_admin_id()",
    "daftar-sync-multitenant-dispatch",
    "daftar-sync-multitenant-reconcile",
    "daftar-sync-multitenant-guardian",
    "daily-daftar-tenant-backup-all",
)
for marker in required:
    assert marker in sql, f"missing multi-tenant contract: {marker}"

assert "execute function private.prevent_daftar_sync_source_breakage()" in low
assert "execute function public.prevent_daftar_sync_source_breakage()" not in low

dispatch_start = sql.index("CREATE OR REPLACE FUNCTION private.dispatch_daftar_sync_sources")
dispatch_end = sql.index("CREATE OR REPLACE FUNCTION private.get_daftar_official_customer_totals")
dispatch = sql[dispatch_start:dispatch_end]
assert "legacy_user_id = 28" not in dispatch
assert "daftar-live-account-28-v1" not in dispatch

for legacy_job in (
    "daftar-live-sync-account-28",
    "daftar-outbound-sync-account-28",
    "daftar-sync-reconcile-account-28",
    "daily-tenant-backup-account-28",
    "daftar-sync-guardian-account-28",
):
    pattern = r"cron\.schedule\s*\(\s*['\"]" + re.escape(legacy_job) + r"['\"]"
    assert not re.search(pattern, sql, re.I), f"legacy cron rescheduled: {legacy_job}"

for signature in (
    "private.prevent_daftar_sync_source_breakage()",
    "private.run_daftar_sync_reconciliation(uuid)",
    "private.reconcile_daftar_source(uuid)",
    "private.dispatch_daftar_sync_sources()",
    "private.reconcile_daftar_sync_sources()",
    "private.run_daftar_tenant_backups()",
    "private.guard_daftar_sync_sources()",
):
    assert f"revoke execute on function {signature}" in low

print("Daftar generic multi-tenant runtime verified")
