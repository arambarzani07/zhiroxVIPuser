#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
BASE_UI = ROOT / "lib/screens/shared/user_profile_employee_management.dart"
ADDITIONAL = ROOT / "lib/permissions/additional_employee_permissions.dart"
MIGRATION = ROOT / "supabase/migrations/20260930104500_expand_employee_permissions_to_180.sql"
UPDATE_ACCOUNT = ROOT / "supabase/functions/update-account/index.ts"
EMPLOYEE_CREATE = ROOT / "supabase/functions/employee-create/index.ts"
PB_SERVICE = ROOT / "lib/services/pb_service.dart"
ADD_USER = ROOT / "lib/screens/shared/add_user_screen.dart"
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
update_text = UPDATE_ACCOUNT.read_text(encoding="utf-8")
create_text = EMPLOYEE_CREATE.read_text(encoding="utf-8")
pb_text = PB_SERVICE.read_text(encoding="utf-8")
add_user_text = ADD_USER.read_text(encoding="utf-8")
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

edge_match = re.search(
    r"const\s+tenantAdminFields\s*=\s*new\s+Set\(\[(.*?)\]\);",
    update_text,
    re.S,
)
if not edge_match:
    fail("could not find update-account tenantAdminFields")
update_keys = set(re.findall(r'"(can_[a-z0-9_]+)"', edge_match.group(1)))
compare("update-account allow-list", update_keys, expected)

defaults_match = re.search(
    r"const\s+permissionDefaults:\s*Record<string,\s*boolean>\s*=\s*\{(.*?)\n\};",
    create_text,
    re.S,
)
if not defaults_match:
    fail("could not find employee-create permissionDefaults")
create_keys = set(re.findall(r"^\s*(can_[a-z0-9_]+):\s*(?:true|false),\s*$", defaults_match.group(1), re.M))
compare("employee-create defaults", create_keys, expected)

if "left(permission_name, 4) = 'can_'" not in fix_prefix_text:
    fail("employee_has_permission must use literal can_ prefix matching")
if re.search(r"\blike\b.*\bescape\b", fix_prefix_text, re.I | re.S):
    fail("employee_has_permission must not use SQL ESCAPE parsing")

print(
    "employee-permissions-contract: OK "
    "(180/180 UI registry, create/update paths, schema, RPC, sync, and Edge Functions match)"
)
