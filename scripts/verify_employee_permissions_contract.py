#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
UI = ROOT / "lib/screens/shared/user_profile_employee_management.dart"
EXPAND = ROOT / "supabase/migrations/20260930072700_expand_employee_permissions_to_60.sql"
SYNC = ROOT / "supabase/migrations/20260930075000_sync_all_60_employee_permissions.sql"
FIX_PREFIX = ROOT / "supabase/migrations/20260930102700_fix_employee_permissions_prefix_detection.sql"
UPDATE_ACCOUNT = ROOT / "supabase/functions/update-account/index.ts"

EXPECTED = {
    "can_view_customers", "can_add_customers", "can_edit_customers", "can_delete_customers",
    "can_view_debts", "can_add_debts", "can_edit_debts", "can_delete_debts",
    "can_record_payments", "can_view_financial_reports", "can_export_data", "can_send_notifications",
    "can_set_debt_limit", "can_set_due_date", "can_import_data", "can_refund_payments",
    "can_restore_debts", "can_manage_receipts", "can_manage_notifications", "can_approve_customers",
    "can_manage_employees", "can_view_audit_log", "can_manage_backup", "can_manage_daftar_sync",
    "can_manage_subscription", "can_view_dashboard", "can_view_recent_activity", "can_view_transactions",
    "can_edit_payments", "can_delete_payments", "can_create_statements", "can_manage_customer_links",
    "can_pin_customers", "can_manage_vip_customers", "can_merge_customer_identities",
    "can_view_market_rates", "can_view_intelligence", "can_manage_collections", "can_view_expiry",
    "can_manage_expiry", "can_manage_settings", "can_view_customer_phone", "can_view_customer_notes",
    "can_edit_customer_notes", "can_view_customer_balances", "can_view_payment_history",
    "can_create_receipts", "can_edit_receipts", "can_delete_receipts", "can_export_receipts",
    "can_view_report_summary", "can_export_reports", "can_view_sync_logs", "can_retry_failed_sync",
    "can_run_manual_backup", "can_restore_backup", "can_manage_notification_templates",
    "can_send_bulk_notifications", "can_manage_market_rate_refresh", "can_manage_security_settings",
}


def fail(message: str) -> None:
    print(f"employee-permissions-contract: FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def compare(name: str, actual: set[str]) -> None:
    missing = sorted(EXPECTED - actual)
    extra = sorted(actual - EXPECTED)
    if missing or extra:
        parts = []
        if missing:
            parts.append("missing=" + ",".join(missing))
        if extra:
            parts.append("extra=" + ",".join(extra))
        fail(f"{name}: {'; '.join(parts)}")


if len(EXPECTED) != 60:
    fail(f"expected permission registry must contain 60 keys, got {len(EXPECTED)}")

ui_text = UI.read_text(encoding="utf-8")
expand_text = EXPAND.read_text(encoding="utf-8")
sync_text = SYNC.read_text(encoding="utf-8")
fix_prefix_text = FIX_PREFIX.read_text(encoding="utf-8")
update_account_text = UPDATE_ACCOUNT.read_text(encoding="utf-8")

ui_keys = re.findall(r"_EmployeePermissionSpec\(key:\s*'([^']+)'", ui_text)
if len(ui_keys) != len(set(ui_keys)):
    duplicates = sorted({key for key in ui_keys if ui_keys.count(key) > 1})
    fail("UI contains duplicate permission specs: " + ",".join(duplicates))
compare("UI", set(ui_keys))

allowed_match = re.search(
    r"allowed_columns\s+constant\s+text\[\]\s*:=\s*array\[(.*?)\];",
    expand_text,
    re.S,
)
if not allowed_match:
    fail("could not find set_employee_permissions_v2 allowed_columns")
allowed_keys = set(re.findall(r"'(can_[a-z0-9_]+)'", allowed_match.group(1)))
compare("set_employee_permissions_v2", allowed_keys)

sync_keys = set(
    re.findall(
        r"^\s*(?:set\s+)?(can_[a-z0-9_]+)\s*=\s*new\.\1\s*,?\s*$",
        sync_text,
        re.M,
    )
)
compare("profile sync trigger", sync_keys)

edge_match = re.search(
    r"const\s+tenantAdminFields\s*=\s*new\s+Set\(\[(.*?)\]\);",
    update_account_text,
    re.S,
)
if not edge_match:
    fail("could not find update-account tenantAdminFields")
edge_keys = set(re.findall(r'"(can_[a-z0-9_]+)"', edge_match.group(1)))
compare("update-account tenant admin allow-list", edge_keys)

if "left(permission_name, 4) = 'can_'" not in fix_prefix_text:
    fail("employee_has_permission prefix detection must use literal can_ prefix matching")
if re.search(r"\blike\b.*\bescape\b", fix_prefix_text, re.I | re.S):
    fail("employee_has_permission prefix detection must not use SQL ESCAPE parsing")

for key in EXPECTED:
    profile_marker = f"add column if not exists {key} boolean"
    if profile_marker not in expand_text:
        # The first 41 permissions come from earlier migrations. Their presence
        # is enforced by the RPC, edge-function, and sync-trigger checks above.
        if key in {
            "can_view_customer_phone", "can_view_customer_notes", "can_edit_customer_notes",
            "can_view_customer_balances", "can_view_payment_history", "can_create_receipts",
            "can_edit_receipts", "can_delete_receipts", "can_export_receipts",
            "can_view_report_summary", "can_export_reports", "can_view_sync_logs",
            "can_retry_failed_sync", "can_run_manual_backup", "can_restore_backup",
            "can_manage_notification_templates", "can_send_bulk_notifications",
            "can_manage_market_rate_refresh", "can_manage_security_settings",
        }:
            fail(f"60-permission migration is missing column {key}")

print(
    "employee-permissions-contract: OK "
    "(60/60 UI, RPC allow-list, update-account allow-list, sync trigger keys, and permission helper prefix parsing match)"
)
