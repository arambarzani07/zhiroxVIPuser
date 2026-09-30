#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "lib/security/owner_permission_registry.dart"
BATCH_1 = ROOT / "supabase/migrations/20260930145254_owner_permission_enforcement_batch_1.sql"
BATCH_2 = ROOT / "supabase/migrations/20260930154013_owner_permission_enforcement_batch_2.sql"

BATCH_2_FUNCTION_KEYS = {
    "get_system_owner_subscription_overview": {
        "owner_view_subscription",
        "owner_view_billing_history",
    },
    "get_system_owner_subscriptions_page": {
        "owner_view_subscription",
        "owner_view_billing_history",
    },
    "set_system_owner_subscription": {
        "owner_change_subscription_plan",
        "owner_extend_subscription_days",
        "owner_view_subscription",
    },
    "get_system_owner_security_overview": {
        "owner_view_security_dashboard",
    },
    "get_system_owner_security_page": {
        "owner_view_security_dashboard",
        "owner_view_active_sessions",
        "owner_view_devices",
    },
    "revoke_system_owner_admin_sessions": {
        "owner_revoke_all_sessions",
    },
    "set_system_owner_admin_lock": {
        "owner_lock_suspicious_account",
        "owner_unlock_suspicious_account",
    },
    "get_system_owner_support_overview": {
        "owner_view_support_history",
    },
    "get_system_owner_support_tickets_page": {
        "owner_view_support_history",
    },
    "update_system_owner_support_ticket": {
        "owner_view_support_history",
        "owner_add_internal_support_note",
        "owner_open_support_case",
        "owner_close_support_case",
    },
}

BATCH_1_REQUIRED_KEYS = {
    "owner_view_platform_dashboard",
    "owner_view_all_markets",
    "owner_set_market_trial",
    "owner_activate_market",
    "owner_set_market_grace",
    "owner_suspend_market",
    "owner_archive_market",
    "owner_set_device_limit",
    "owner_set_employee_limit",
    "owner_set_support_standard",
    "owner_set_support_priority",
    "owner_set_support_vip",
    "owner_view_feature_catalog",
}


def fail(message: str) -> None:
    print(f"OWNER_PERMISSION_ENFORCEMENT_FAILED: {message}", file=sys.stderr)
    raise SystemExit(1)


def function_body(sql: str, name: str) -> str:
    pattern = re.compile(
        rf"create\s+or\s+replace\s+function\s+public\.{re.escape(name)}\s*\(.*?\)"
        rf".*?\bas\s+\$\$(.*?)\$\$;",
        re.IGNORECASE | re.DOTALL,
    )
    match = pattern.search(sql)
    if not match:
        fail(f"missing function definition in batch 2: {name}")
    return match.group(1)


def main() -> None:
    for path in (REGISTRY, BATCH_1, BATCH_2):
        if not path.exists():
            fail(f"missing contract file: {path.relative_to(ROOT)}")

    registry = REGISTRY.read_text(encoding="utf-8")
    batch_1 = BATCH_1.read_text(encoding="utf-8")
    batch_2 = BATCH_2.read_text(encoding="utf-8")

    all_expected_keys = set(BATCH_1_REQUIRED_KEYS)
    for keys in BATCH_2_FUNCTION_KEYS.values():
        all_expected_keys.update(keys)

    missing_registry = sorted(
        key for key in all_expected_keys if f"'{key}'" not in registry
    )
    if missing_registry:
        fail(f"enforcement references keys absent from registry: {missing_registry}")

    if "private.assert_system_owner_permission" not in batch_1:
        fail("batch 1 no longer contains the central Owner permission guard")
    missing_batch_1 = sorted(
        key for key in BATCH_1_REQUIRED_KEYS if f"'{key}'" not in batch_1
    )
    if missing_batch_1:
        fail(f"batch 1 lost required permission keys: {missing_batch_1}")

    for name, keys in BATCH_2_FUNCTION_KEYS.items():
        body = function_body(batch_2, name)
        if "private.assert_system_owner_permission" not in body:
            fail(f"{name} is missing central permission enforcement")
        missing = sorted(key for key in keys if f"'{key}'" not in body)
        if missing:
            fail(f"{name} lost required permission keys: {missing}")

    # Mutations must authenticate the Owner explicitly before changing state.
    for name in (
        "set_system_owner_subscription",
        "revoke_system_owner_admin_sessions",
        "set_system_owner_admin_lock",
        "update_system_owner_support_ticket",
    ):
        body = function_body(batch_2, name)
        if "private.require_system_owner()" not in body:
            fail(f"{name} must authenticate the System Owner explicitly")

    # The migration must keep the RPCs unavailable to anon/public while
    # retaining authenticated invocation (the function itself authorizes).
    for name in BATCH_2_FUNCTION_KEYS:
        if f"function public.{name}" not in batch_2:
            fail(f"missing RPC grant/revoke surface for {name}")
    if "from public, anon;" not in batch_2 or "to authenticated;" not in batch_2:
        fail("batch 2 RPC grant/revoke contract changed")

    print(
        "OWNER_PERMISSION_ENFORCEMENT_OK "
        f"batch1_keys={len(BATCH_1_REQUIRED_KEYS)} "
        f"batch2_functions={len(BATCH_2_FUNCTION_KEYS)} "
        f"batch2_unique_keys={len(set().union(*BATCH_2_FUNCTION_KEYS.values()))}"
    )


if __name__ == "__main__":
    main()
