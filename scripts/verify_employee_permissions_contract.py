#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
BASE_UI = ROOT / "lib/screens/shared/user_profile_employee_management.dart"
ADDITIONAL = ROOT / "lib/permissions/additional_employee_permissions.dart"
MIGRATION = ROOT / "supabase/migrations/20260930104500_expand_employee_permissions_to_180.sql"
EDGE_REGISTRY = ROOT / "supabase/functions/_shared/employee-permission-keys.ts"
UPDATE_ACCOUNT = ROOT / "supabase/functions/update-account/index.ts"
EMPLOYEE_CREATE = ROOT / "supabase/functions/employee-create/index.ts"
PB_SERVICE = ROOT / "lib/services/pb_service.dart"
ADD_USER = ROOT / "lib/screens/shared/add_user_screen.dart"
AUTH_PROVIDER = ROOT / "lib/providers/auth_provider.dart"
FIX_PREFIX = ROOT / "supabase/migrations/20260930102700_fix_employee_permissions_prefix_detection.sql"


def fail(message: str) -> None:
    print(f"employee-permissions-contract: FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def compare(name: str, actual: set[str], expected: set[str]) -> None:
    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    if missing or extra:
        parts = []
        if missing:
            parts.append("missing=" + ",".join(missing))
        if extra:
            parts.append("extra=" + ",".join(extra))
        fail(f"{name}: {'; '.join(parts)}")


base_text = BASE_UI.read_text(encoding="utf-8")
additional_text = ADDITIONAL.read_text(encoding="utf-8")
migration_text = MIGRATION.read_text(encoding="utf-8")
edge_registry_text = EDGE_REGISTRY.read_text(encoding="utf-8")
update_text = UPDATE_ACCOUNT.read_text(encoding="utf-8")
create_text = EMPLOYEE_CREATE.read_text(encoding="utf-8")
pb_text = PB_SERVICE.read_text(encoding="utf-8")
add_user_text = ADD_USER.read_text(encoding="utf-8")
auth_text = AUTH_PROVIDER.read_text(encoding="utf-8")
fix_prefix_text = FIX_PREFIX.read_text(encoding="utf-8")

base_keys = set(re.findall(r"_EmployeePermissionSpec\(key:\s*'([^']+)'", base_text))
additional_keys = set(re.findall(r"AdditionalEmployeePermissionSpec\(key:\s*'([^']+)'", additional_text))
if len(base_keys) != 60:
    fail(f"base UI must contain exactly 60 keys, got {len(base_keys)}")
if len(additional_keys) != 120:
    fail(f"additional registry must contain exactly 120 keys, got {len(additional_keys)}")
if base_keys & additional_keys:
    fail("base and additional permission registries overlap")
expected = base_keys | additional_keys
if len(expected) != 180:
    fail(f"combined registry must contain 180 keys, got {len(expected)}")

if "additionalEmployeePermissionSpecs.map" not in base_text:
    fail("employee profile editor is not wired to the 120-key additional registry")
if "180 دەسەڵات" not in add_user_text:
    fail("employee creation UI does not advertise 180 permissions")
if "_additionalPermissions" not in add_user_text or "extraPermissions:" not in add_user_text:
    fail("employee creation UI does not submit additional permissions")
if "Map<String, bool> extraPermissions" not in pb_text or "...extraPermissions," not in pb_text:
    fail("PBService.createUser does not forward additional permissions atomically")

for key in additional_keys:
    marker = f"add column if not exists {key} boolean"
    if migration_text.count(marker) != 2:
        fail(f"180-permission migration must add {key} to profiles and employee_permissions")

allowed_match = re.search(
    r"allowed_columns\s+constant\s+text\[\]\s*:=\s*array\[(.*?)\];",
    migration_text,
    re.S,
)
if not allowed_match:
    fail("could not find 180-key set_employee_permissions_v2 allow-list")
allowed = set(re.findall(r"'(can_[a-z0-9_]+)'", allowed_match.group(1)))
compare("set_employee_permissions_v2", allowed, expected)

sync_to_profile = set(re.findall(
    r"^\s*(?:set\s+)?(can_[a-z0-9_]+)\s*=\s*new\.\1\s*,?\s*$",
    migration_text,
    re.M,
))
compare("employee_permissions -> profiles sync", sync_to_profile, expected)

registry_match = re.search(
    r"EMPLOYEE_PERMISSION_KEYS\s*=\s*\[(.*?)\]\s*as const;",
    edge_registry_text,
    re.S,
)
if not registry_match:
    fail("could not find shared Edge employee permission registry")
edge_keys = set(re.findall(r'"(can_[a-z0-9_]+)"', registry_match.group(1)))
compare("shared Edge registry", edge_keys, expected)

true_match = re.search(
    r"DEFAULT_TRUE_EMPLOYEE_PERMISSIONS\s*=\s*new Set<[^>]+>\(\[(.*?)\]\);",
    edge_registry_text,
    re.S,
)
if not true_match:
    fail("could not find historical default-true permission set")
default_true = set(re.findall(r'"(can_[a-z0-9_]+)"', true_match.group(1)))
expected_default_true = {
    "can_view_customers",
    "can_view_debts",
    "can_view_dashboard",
    "can_view_recent_activity",
    "can_view_market_rates",
}
compare("default-true employee permissions", default_true, expected_default_true)

if '../_shared/employee-permission-keys.ts' not in create_text:
    fail("employee-create does not import the shared 180-key registry")
if "for (const key of EMPLOYEE_PERMISSION_KEYS)" not in create_text:
    fail("employee-create does not initialize all 180 permissions")
if "DEFAULT_TRUE_EMPLOYEE_PERMISSIONS.has(key)" not in create_text:
    fail("employee-create does not preserve historical default permissions")

if '../_shared/employee-permission-keys.ts' not in update_text:
    fail("update-account does not import the shared 180-key registry")
if "EMPLOYEE_PERMISSION_KEY_SET.has(key)" not in update_text:
    fail("update-account does not enforce the shared 180-key allow-list")
if 'typeof value === "boolean"' not in update_text:
    fail("update-account permission values are not type-checked as booleans")

if "bool hasEmployeePermission(String field)" not in auth_text:
    fail("AuthProvider is missing the generic 180-permission runtime gate")
if "RegExp(r'^can_[a-z0-9_]+$').hasMatch(field)" not in auth_text:
    fail("AuthProvider runtime gate does not reject invalid permission names")
if "return _employeePermission(field);" not in auth_text:
    fail("AuthProvider runtime gate does not resolve the profile flag")

if "left(permission_name, 4) = 'can_'" not in fix_prefix_text:
    fail("employee_has_permission must use literal can_ prefix matching")
if re.search(r"\blike\b.*\bescape\b", fix_prefix_text, re.I | re.S):
    fail("employee_has_permission must not use SQL ESCAPE parsing")

print(
    "employee-permissions-contract: OK "
    "(180/180 UI, schema, RPC, sync, shared Edge registry, create/update, and runtime gate match)"
)
