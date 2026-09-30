#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "lib/security/owner_permission_registry.dart"

EXPECTED_COUNT = 200
EXPECTED_GROUPS = {
    "core",
    "admin_accounts",
    "market_identity",
    "market_lifecycle",
    "subscription",
    "resource_limits",
    "feature_entitlements",
    "security",
    "support",
    "backup_recovery",
    "sync_integration",
    "app_version",
    "platform_health",
    "audit",
}

# System Owner is a platform operator. Direct market-business content must stay
# outside the normal Owner permission registry. Any future emergency support
# access must use a separate, time-bound break-glass flow.
FORBIDDEN_DIRECT_CONTENT_TOKENS = {
    "customer_debt",
    "customer_payment",
    "customer_receipt",
    "customer_private_note",
    "view_debts",
    "view_payments",
    "view_receipts",
    "edit_debt",
    "edit_payment",
    "delete_debt",
    "delete_payment",
}

ENTRY_RE = re.compile(
    r"OwnerPermissionDefinition\(" 
    r"'(?P<key>owner_[a-z0-9_]+)',\s*"
    r"'(?P<label>[^']+)',\s*"
    r"'(?P<group>[a-z0-9_]+)',\s*"
    r"'(?P<group_label>[^']+)',\s*"
    r"(?P<risk>[1-4]),\s*"
    r"<OwnerPermissionScope>\{(?P<scopes>[^}]*)\}"
    r"(?P<flags>[^)]*)\),"
)


def fail(message: str) -> None:
    print(f"OWNER_PERMISSION_CONTRACT_FAILED: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    text = REGISTRY.read_text(encoding="utf-8")
    entries = list(ENTRY_RE.finditer(text))
    if len(entries) != EXPECTED_COUNT:
        fail(f"expected {EXPECTED_COUNT} entries, found {len(entries)}")

    declared_count = re.search(r"const ownerPermissionCount\s*=\s*(\d+)\s*;", text)
    if not declared_count or int(declared_count.group(1)) != EXPECTED_COUNT:
        fail("ownerPermissionCount must remain exactly 200")

    keys = [m.group("key") for m in entries]
    duplicates = [k for k, count in Counter(keys).items() if count > 1]
    if duplicates:
        fail(f"duplicate permission keys: {duplicates}")

    groups = {m.group("group") for m in entries}
    if groups != EXPECTED_GROUPS:
        fail(f"group mismatch: missing={sorted(EXPECTED_GROUPS - groups)} extra={sorted(groups - EXPECTED_GROUPS)}")

    for m in entries:
        key = m.group("key")
        risk = int(m.group("risk"))
        scopes = m.group("scopes")
        flags = m.group("flags")

        if not any(
            scope in scopes
            for scope in (
                "OwnerPermissionScope.platform",
                "OwnerPermissionScope.market",
                "OwnerPermissionScope.admin",
            )
        ):
            fail(f"{key} has no scope")

        if risk >= 3:
            if "requiresReason: true" not in flags:
                fail(f"{key} risk {risk} must require a reason")
            if "requiresReauth: true" not in flags:
                fail(f"{key} risk {risk} must require re-authentication")

        if risk == 4:
            if "requiresTypedConfirmation: true" not in flags:
                fail(f"{key} risk 4 must require typed confirmation")
            if "requiresTwoPersonApproval: true" not in flags:
                fail(f"{key} risk 4 must be marked for two-person approval")

        if any(token in key for token in FORBIDDEN_DIRECT_CONTENT_TOKENS):
            fail(f"{key} violates the Owner/market-content privacy boundary")

    risk_counts = Counter(int(m.group("risk")) for m in entries)
    group_counts = Counter(m.group("group") for m in entries)
    print(
        "OWNER_PERMISSION_CONTRACT_OK "
        f"count={len(entries)} groups={len(group_counts)} "
        f"risk={dict(sorted(risk_counts.items()))}"
    )
    for group in sorted(group_counts):
        print(f"  {group}: {group_counts[group]}")


if __name__ == "__main__":
    main()
