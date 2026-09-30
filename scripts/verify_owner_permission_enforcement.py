#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "lib/security/owner_permission_registry.dart"
BATCH_1 = ROOT / "supabase/migrations/20260930145254_owner_permission_enforcement_batch_1.sql"
BATCH_2 = ROOT / "supabase/migrations/20260930154013_owner_permission_enforcement_batch_2.sql"
BATCH_3 = ROOT / "supabase/migrations/20260930155118_owner_permission_enforcement_batch_3.sql"
BATCH_4 = ROOT / "supabase/migrations/20260930155931_owner_permission_enforcement_batch_4.sql"
BATCH_5A = ROOT / "supabase/migrations/20260930160656_owner_permission_enforcement_batch_5.sql"
BATCH_5B = ROOT / "supabase/migrations/20260930160738_owner_permission_enforcement_batch_5.sql"
RECOVERY_EDGE = ROOT / "supabase/functions/owner-account-recovery/index.ts"

BATCH_2_FUNCTION_KEYS = {
    "get_system_owner_subscription_overview": {"owner_view_subscription", "owner_view_billing_history"},
    "get_system_owner_subscriptions_page": {"owner_view_subscription", "owner_view_billing_history"},
    "set_system_owner_subscription": {"owner_change_subscription_plan", "owner_extend_subscription_days", "owner_view_subscription"},
    "get_system_owner_security_overview": {"owner_view_security_dashboard"},
    "get_system_owner_security_page": {"owner_view_security_dashboard", "owner_view_active_sessions", "owner_view_devices"},
    "revoke_system_owner_admin_sessions": {"owner_revoke_all_sessions"},
    "set_system_owner_admin_lock": {"owner_lock_suspicious_account", "owner_unlock_suspicious_account"},
    "get_system_owner_support_overview": {"owner_view_support_history"},
    "get_system_owner_support_tickets_page": {"owner_view_support_history"},
    "update_system_owner_support_ticket": {"owner_view_support_history", "owner_add_internal_support_note", "owner_open_support_case", "owner_close_support_case"},
}

BATCH_3_FUNCTION_KEYS = {
    "get_system_owner_recovery_device_overview": {"owner_view_admin_devices"},
    "get_system_owner_recovery_device_page": {"owner_view_admin_profile", "owner_view_admin_devices", "owner_view_admin_status"},
    "set_system_owner_admin_device_policy": {"owner_block_device", "owner_unblock_device"},
    "set_system_owner_admin_device_authorization": {"owner_block_device", "owner_unblock_device", "owner_revoke_admin_device"},
    "authorize_system_owner_admin_recovery_service": {"owner_reset_admin_password", "owner_revoke_admin_sessions", "owner_revoke_admin_device"},
    "complete_system_owner_admin_recovery_service": {"owner_reset_admin_password", "owner_revoke_admin_sessions", "owner_revoke_admin_device"},
    "get_system_owner_backup_resilience_overview": {"owner_view_backup_health"},
    "get_system_owner_backup_resilience_page": {"owner_view_backup_health", "owner_view_market_backups"},
    "set_system_owner_backup_monitoring_policy": {"owner_view_market_backups", "owner_verify_backup"},
}

BATCH_4_FUNCTION_KEYS = {
    "set_system_owner_operations_state": {
        "owner_refresh_platform_config",
        "owner_publish_update_message",
        "owner_view_platform_dashboard",
    },
    "get_system_owner_release_overview": {"owner_view_app_versions"},
    "get_system_owner_release_compliance_page": {
        "owner_view_app_versions",
        "owner_view_admin_profile",
        "owner_view_admin_devices",
        "owner_view_admin_status",
    },
    "set_system_owner_release_policy": {
        "owner_view_app_versions",
        "owner_force_app_update",
        "owner_disable_forced_update",
        "owner_set_minimum_app_version",
        "owner_block_old_app_version",
        "owner_allow_old_app_version",
        "owner_publish_update_message",
        "owner_refresh_platform_config",
    },
}

BATCH_5A_FUNCTION_KEYS = {
    "get_system_owner_health_overview": {
        "owner_view_platform_metrics",
        "owner_view_database_health",
        "owner_view_backup_health",
        "owner_view_billing_history",
        "owner_view_owner_audit",
    },
    "get_system_owner_platform_audit_page": {"owner_view_owner_audit"},
    "get_system_owner_infrastructure_overview": {"owner_view_backend_health", "owner_view_queue_health"},
    "get_system_owner_infrastructure_jobs_page": {"owner_view_backend_health", "owner_view_queue_health"},
    "get_system_owner_incident_overview": {"owner_view_platform_activity"},
    "get_system_owner_incidents_page": {"owner_view_platform_activity"},
    "create_system_owner_incident": {"owner_refresh_platform_config", "owner_publish_update_message"},
    "update_system_owner_incident": {"owner_refresh_platform_config", "owner_publish_update_message"},
}

BATCH_5B_FUNCTION_KEYS = {
    "get_system_owner_admins_page": "owner_view_all_admins",
    "get_system_owner_branding_overview": "owner_view_all_markets",
    "get_system_owner_branding_page": "owner_view_all_markets",
    "get_system_owner_domain_check_target": "owner_view_market_profile",
    "get_system_owner_domain_overview": "owner_view_all_markets",
    "get_system_owner_domain_page": "owner_view_all_markets",
    "get_system_owner_health_overview": "owner_view_platform_metrics",
    "get_system_owner_incident_overview": "owner_view_platform_activity",
    "get_system_owner_incidents_page": "owner_view_platform_activity",
    "get_system_owner_infrastructure_jobs_page": "owner_view_queue_health",
    "get_system_owner_infrastructure_overview": "owner_view_backend_health",
    "get_system_owner_platform_audit_page": "owner_view_owner_audit",
    "get_system_owner_policy_overview": "owner_view_platform_metrics",
    "get_system_owner_policy_page": "owner_view_platform_metrics",
    "get_system_owner_readiness_overview": "owner_view_all_markets",
    "get_system_owner_readiness_page": "owner_view_all_markets",
    "set_system_owner_retention_policy": "owner_refresh_platform_config",
    "set_system_owner_tenant_branding": "owner_set_market_metadata",
    "set_system_owner_tenant_domain": "owner_set_market_metadata",
    "update_system_owner_incident": "owner_refresh_platform_config",
}

BATCH_3_SERVICE_FUNCTIONS = {
    "authorize_system_owner_admin_recovery_service",
    "complete_system_owner_admin_recovery_service",
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
        fail(f"missing function definition: {name}")
    return match.group(1)


def verify_function_contract(sql: str, contract: dict[str, set[str]], *, service_functions: set[str] | None = None) -> None:
    service_functions = service_functions or set()
    for name, keys in contract.items():
        body = function_body(sql, name)
        if name in service_functions:
            if "private.system_owner_has_permission" not in body:
                fail(f"{name} is missing actor-aware service permission enforcement")
            if "service_role_required" not in body:
                fail(f"{name} must remain service-role only")
        elif "private.assert_system_owner_permission" not in body:
            fail(f"{name} is missing central permission enforcement")
        missing = sorted(key for key in keys if f"'{key}'" not in body)
        if missing:
            fail(f"{name} lost required permission keys: {missing}")


def verify_batch_5b(sql: str) -> None:
    if "owner_permission_injection_pattern_missing" not in sql:
        fail("batch 5B must fail closed when a legacy function cannot be patched")
    if "private.assert_system_owner_permission" not in sql:
        fail("batch 5B lost the central Owner permission guard")
    for name, key in BATCH_5B_FUNCTION_KEYS.items():
        if f"public.{name}" not in sql:
            fail(f"batch 5B lost protected function: {name}")
        if f"'{key}'" not in sql:
            fail(f"batch 5B lost permission key {key} for {name}")
    if "owner_access_console" not in sql or "get_system_owner_permission_catalog" not in sql:
        fail("Owner permission catalog must require owner_access_console")
    if "from public, anon;" not in sql or "to authenticated;" not in sql:
        fail("batch 5B catalog RPC grant/revoke contract changed")


def main() -> None:
    paths = (REGISTRY, BATCH_1, BATCH_2, BATCH_3, BATCH_4, BATCH_5A, BATCH_5B, RECOVERY_EDGE)
    for path in paths:
        if not path.exists():
            fail(f"missing contract file: {path.relative_to(ROOT)}")

    registry = REGISTRY.read_text(encoding="utf-8")
    batch_1 = BATCH_1.read_text(encoding="utf-8")
    batch_2 = BATCH_2.read_text(encoding="utf-8")
    batch_3 = BATCH_3.read_text(encoding="utf-8")
    batch_4 = BATCH_4.read_text(encoding="utf-8")
    batch_5a = BATCH_5A.read_text(encoding="utf-8")
    batch_5b = BATCH_5B.read_text(encoding="utf-8")
    recovery_edge = RECOVERY_EDGE.read_text(encoding="utf-8")

    all_expected_keys = set(BATCH_1_REQUIRED_KEYS)
    for contract in (BATCH_2_FUNCTION_KEYS, BATCH_3_FUNCTION_KEYS, BATCH_4_FUNCTION_KEYS, BATCH_5A_FUNCTION_KEYS):
        for keys in contract.values():
            all_expected_keys.update(keys)
    all_expected_keys.update(BATCH_5B_FUNCTION_KEYS.values())
    all_expected_keys.add("owner_access_console")

    missing_registry = sorted(key for key in all_expected_keys if f"'{key}'" not in registry)
    if missing_registry:
        fail(f"enforcement references keys absent from registry: {missing_registry}")

    if "private.assert_system_owner_permission" not in batch_1:
        fail("batch 1 no longer contains the central Owner permission guard")
    missing_batch_1 = sorted(key for key in BATCH_1_REQUIRED_KEYS if f"'{key}'" not in batch_1)
    if missing_batch_1:
        fail(f"batch 1 lost required permission keys: {missing_batch_1}")

    verify_function_contract(batch_2, BATCH_2_FUNCTION_KEYS)
    verify_function_contract(batch_3, BATCH_3_FUNCTION_KEYS, service_functions=BATCH_3_SERVICE_FUNCTIONS)
    verify_function_contract(batch_4, BATCH_4_FUNCTION_KEYS)
    verify_function_contract(batch_5a, BATCH_5A_FUNCTION_KEYS)
    verify_batch_5b(batch_5b)

    for name in (
        "set_system_owner_subscription",
        "revoke_system_owner_admin_sessions",
        "set_system_owner_admin_lock",
        "update_system_owner_support_ticket",
    ):
        if "private.require_system_owner()" not in function_body(batch_2, name):
            fail(f"{name} must authenticate the System Owner explicitly")

    for name in (
        "set_system_owner_admin_device_policy",
        "set_system_owner_admin_device_authorization",
        "set_system_owner_backup_monitoring_policy",
    ):
        if "private.require_system_owner()" not in function_body(batch_3, name):
            fail(f"{name} must authenticate the System Owner explicitly")

    for name in ("set_system_owner_operations_state", "set_system_owner_release_policy"):
        if "private.require_system_owner()" not in function_body(batch_4, name):
            fail(f"{name} must authenticate the System Owner explicitly")

    for name in ("create_system_owner_incident", "update_system_owner_incident"):
        if "private.require_system_owner()" not in function_body(batch_5a, name):
            fail(f"{name} must authenticate the System Owner explicitly")

    preflight = recovery_edge.find('"authorize_system_owner_admin_recovery_service"')
    password_update = recovery_edge.find("admin.auth.admin.updateUserById(")
    finalizer = recovery_edge.find('"complete_system_owner_admin_recovery_service"')
    if preflight < 0 or password_update < 0 or finalizer < 0:
        fail("recovery Edge Function lost preflight/password/finalizer stages")
    if not (preflight < password_update < finalizer):
        fail("recovery Edge Function must authorize before password update and finalize after it")
    if 'return json({ error: "owner_permission_denied" }, 403);' not in recovery_edge:
        fail("recovery Edge Function must fail closed on permission denial")

    if (
        "authorize_system_owner_admin_recovery_service(uuid,uuid)\n  from public, anon, authenticated;" not in batch_3
        or "complete_system_owner_admin_recovery_service(uuid,uuid,text)\n  from public, anon, authenticated;" not in batch_3
    ):
        fail("batch 3 recovery service RPC revoke contract changed")
    if (
        "authorize_system_owner_admin_recovery_service(uuid,uuid)\n  to service_role;" not in batch_3
        or "complete_system_owner_admin_recovery_service(uuid,uuid,text)\n  to service_role;" not in batch_3
    ):
        fail("batch 3 recovery service RPC grant contract changed")

    for sql, label in (
        (batch_2, "batch 2"),
        (batch_3, "batch 3"),
        (batch_4, "batch 4"),
        (batch_5a, "batch 5A"),
    ):
        if "from public, anon;" not in sql or "to authenticated;" not in sql:
            fail(f"{label} RPC grant/revoke contract changed")

    print(
        "OWNER_PERMISSION_ENFORCEMENT_OK "
        f"batch1_keys={len(BATCH_1_REQUIRED_KEYS)} "
        f"batch2_functions={len(BATCH_2_FUNCTION_KEYS)} "
        f"batch3_functions={len(BATCH_3_FUNCTION_KEYS)} "
        f"batch4_functions={len(BATCH_4_FUNCTION_KEYS)} "
        f"batch5a_functions={len(BATCH_5A_FUNCTION_KEYS)} "
        f"batch5b_functions={len(BATCH_5B_FUNCTION_KEYS) + 1} "
        f"protected_unique_keys={len(all_expected_keys)}"
    )


if __name__ == "__main__":
    main()
