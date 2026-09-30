#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "lib/security/owner_permission_registry.dart"
MIGRATION = ROOT / "supabase/migrations/20260930130637_owner_permission_governance_v1.sql"

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
SQL_ENTRY_RE = re.compile(
    r"\('(?P<key>owner_[a-z0-9_]+)',\s*'(?P<label>[^']+)',\s*"
    r"'(?P<group>[a-z0-9_]+)',\s*'(?P<group_label>[^']+)',\s*"
    r"(?P<risk>[1-4]),\s*ARRAY\[(?P<scopes>[^]]+)\]::text\[\],\s*"
    r"(?P<reason>true|false),\s*(?P<reauth>true|false),\s*"
    r"(?P<typed>true|false),\s*(?P<two_person>true|false),\s*true\)"
)


def fail(message: str) -> None:
    print(f"OWNER_PERMISSION_CONTRACT_FAILED: {message}", file=sys.stderr)
    raise SystemExit(1)


def _dart_scopes(raw: str) -> tuple[str, ...]:
    return tuple(sorted(
        scope
        for scope in ("platform", "market", "admin")
        if f"OwnerPermissionScope.{scope}" in raw
    ))


def _sql_scopes(raw: str) -> tuple[str, ...]:
    return tuple(sorted(re.findall(r"'([^']+)'", raw)))


def verify_migration(dart_entries: list[re.Match[str]]) -> None:
    if not MIGRATION.exists():
        fail(f"missing migration: {MIGRATION.relative_to(ROOT)}")

    sql = MIGRATION.read_text(encoding="utf-8")
    sql_entries = list(SQL_ENTRY_RE.finditer(sql))
    if len(sql_entries) != EXPECTED_COUNT:
        fail(f"expected {EXPECTED_COUNT} SQL entries, found {len(sql_entries)}")

    dart_by_key = {m.group("key"): m for m in dart_entries}
    sql_by_key = {m.group("key"): m for m in sql_entries}
    if set(dart_by_key) != set(sql_by_key):
        fail(
            "registry/migration key drift: "
            f"missing_in_sql={sorted(set(dart_by_key) - set(sql_by_key))} "
            f"extra_in_sql={sorted(set(sql_by_key) - set(dart_by_key))}"
        )

    for key, m in dart_by_key.items():
        s = sql_by_key[key]
        flags = m.group("flags")
        dart_shape = (
            m.group("label"),
            m.group("group"),
            m.group("group_label"),
            int(m.group("risk")),
            _dart_scopes(m.group("scopes")),
            (
                "requiresReason: true" in flags,
                "requiresReauth: true" in flags,
                "requiresTypedConfirmation: true" in flags,
                "requiresTwoPersonApproval: true" in flags,
            ),
        )
        sql_shape = (
            s.group("label"),
            s.group("group"),
            s.group("group_label"),
            int(s.group("risk")),
            _sql_scopes(s.group("scopes")),
            (
                s.group("reason") == "true",
                s.group("reauth") == "true",
                s.group("typed") == "true",
                s.group("two_person") == "true",
            ),
        )
        if dart_shape != sql_shape:
            fail(f"Dart/SQL metadata drift for {key}: {dart_shape!r} != {sql_shape!r}")

    required_security_fragments = (
        "create schema if not exists private;",
        "create table if not exists private.owner_permission_catalog",
        "create table if not exists private.owner_permission_principals",
        "create table if not exists private.owner_permission_grants",
        "create table if not exists private.owner_permission_audit",
        "alter table private.owner_permission_catalog enable row level security;",
        "alter table private.owner_permission_principals enable row level security;",
        "alter table private.owner_permission_grants enable row level security;",
        "alter table private.owner_permission_audit enable row level security;",
        "revoke all on table private.owner_permission_catalog from public, anon, authenticated;",
        "revoke all on table private.owner_permission_grants from public, anon, authenticated;",
        "create or replace function private.system_owner_has_permission",
        "create or replace function private.assert_system_owner_permission",
        "create or replace function public.get_system_owner_permission_catalog",
        "security invoker",
        "set search_path = ''",
    )
    for fragment in required_security_fragments:
        if fragment not in sql:
            fail(f"migration security contract missing: {fragment}")


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
        fail(
            f"group mismatch: missing={sorted(EXPECTED_GROUPS - groups)} "
            f"extra={sorted(groups - EXPECTED_GROUPS)}"
        )

    for m in entries:
        key = m.group("key")
        risk = int(m.group("risk"))
        scopes = m.group("scopes")
        flags = m.group("flags")

        if not _dart_scopes(scopes):
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

    verify_migration(entries)

    risk_counts = Counter(int(m.group("risk")) for m in entries)
    group_counts = Counter(m.group("group") for m in entries)
    print(
        "OWNER_PERMISSION_CONTRACT_OK "
        f"count={len(entries)} groups={len(group_counts)} "
        f"risk={dict(sorted(risk_counts.items()))} dart_sql=matched"
    )
    for group in sorted(group_counts):
        print(f"  {group}: {group_counts[group]}")


if __name__ == "__main__":
    main()
