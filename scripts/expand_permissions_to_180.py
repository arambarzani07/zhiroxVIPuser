#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "lib/permissions/additional_employee_permissions.dart"
PROFILE_SCREEN = ROOT / "lib/screens/shared/user_profile_screen.dart"
PROFILE_PERMS = ROOT / "lib/screens/shared/user_profile_employee_management.dart"
ADD_USER = ROOT / "lib/screens/shared/add_user_screen.dart"
PB_SERVICE = ROOT / "lib/services/pb_service.dart"
UPDATE_ACCOUNT = ROOT / "supabase/functions/update-account/index.ts"
EMPLOYEE_CREATE = ROOT / "supabase/functions/employee-create/index.ts"
CONTRACT = ROOT / "scripts/verify_employee_permissions_contract.py"
WORKFLOW = ROOT / ".github/workflows/employee-permissions-contract.yml"
MIGRATION = ROOT / "supabase/migrations/20260930104500_expand_employee_permissions_to_180.sql"

def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")

def write(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")
    print(f"updated {path.relative_to(ROOT)}")

registry_text = read(REGISTRY)
extra_keys = re.findall(r"AdditionalEmployeePermissionSpec\(key: '([^']+)'", registry_text)
if len(extra_keys) != 120 or len(set(extra_keys)) != 120:
    raise SystemExit(f"expected 120 unique additional permissions, got {len(extra_keys)}/{len(set(extra_keys))}")

profile_perm_text = read(PROFILE_PERMS)
base_keys = re.findall(r"_EmployeePermissionSpec\(key: '([^']+)'", profile_perm_text)
if len(base_keys) != 60 or len(set(base_keys)) != 60:
    raise SystemExit(f"expected 60 unique base permissions, got {len(base_keys)}/{len(set(base_keys))}")
if set(base_keys) & set(extra_keys):
    raise SystemExit("base/additional permission keys overlap")
all_keys = base_keys + extra_keys
if len(all_keys) != 180:
    raise SystemExit("permission registry must contain exactly 180 keys")

text = read(PROFILE_SCREEN)
imp = "import 'package:zhirox/permissions/additional_employee_permissions.dart';\n"
if imp not in text:
    anchor = "import 'package:zhirox/providers/auth_provider.dart';\n"
    if anchor not in text:
        raise SystemExit("user_profile_screen import anchor missing")
    text = text.replace(anchor, anchor + imp, 1)
    write(PROFILE_SCREEN, text)

text = read(PROFILE_PERMS)
if "additionalEmployeePermissionSpecs.map" not in text:
    text = text.replace(
        "const _employeePermissionSpecs = <_EmployeePermissionSpec>[",
        "final _employeePermissionSpecs = <_EmployeePermissionSpec>[",
        1,
    )
    marker = "\n];\n\nclass _EmployeePermissionsEditor"
    idx = text.find(marker, text.find("final _employeePermissionSpecs"))
    if idx < 0:
        raise SystemExit("employee permission list terminator not found")
    spread = """
  ...additionalEmployeePermissionSpecs.map(
    (spec) => _EmployeePermissionSpec(
      key: spec.key,
      title: spec.title,
      group: spec.group,
      icon: spec.icon,
    ),
  ),
"""
    text = text[:idx] + "\n" + spread + text[idx:]
text = text.replace("هەموو ٦٠ دەسەڵاتەکە نوێکرانەوە", "هەموو ١٨٠ دەسەڵاتەکە نوێکرانەوە")
text = text.replace("لە ٦٠ دەسەڵات چالاکە", "لە ١٨٠ دەسەڵات چالاکە")
text = text.replace("پاشەکەوتکردنی ٦٠ دەسەڵات", "پاشەکەوتکردنی ١٨٠ دەسەڵات")
write(PROFILE_PERMS, text)

text = read(ADD_USER)
imp = "import 'package:zhirox/permissions/additional_employee_permissions.dart';\n"
if imp not in text:
    anchor = "import 'package:zhirox/providers/auth_provider.dart';\n"
    if anchor not in text:
        raise SystemExit("add_user import anchor missing")
    text = text.replace(anchor, anchor + imp, 1)

state_anchor = "  bool _canManageSecuritySettings = false;\n"
state_line = (
    "  final Map<String, bool> _additionalPermissions = "
    "newAdditionalEmployeePermissionState();\n"
)
if state_line not in text:
    if state_anchor not in text:
        raise SystemExit("add_user state anchor missing")
    text = text.replace(state_anchor, state_anchor + state_line, 1)

if "extraPermissions:" not in text:
    call_anchor = "        debtLimit: debtLimit,\n"
    if call_anchor not in text:
        raise SystemExit("createUser call anchor missing")
    text = text.replace(
        call_anchor,
        "        extraPermissions: widget.role == 'employee'\n"
        "            ? _additionalPermissions\n"
        "            : const <String, bool>{},\n"
        + call_anchor,
        1,
    )

text = text.replace(
    "60 دەسەڵات بەردەستن؛ تەنها ئەوانە چالاک بکە کە پێویستی پێیان هەیە.",
    "180 دەسەڵات بەردەستن؛ تەنها ئەوانە چالاک بکە کە پێویستی پێیان هەیە.",
)

if "_buildAdditionalPermissionGroups" not in text:
    section_start = text.find("  Widget _buildPermissionSection(bool isDark) {")
    section_end = text.find("  Widget _sectionLabel(", section_start)
    if section_start < 0 or section_end < 0:
        raise SystemExit("permission section boundaries not found")
    segment = text[section_start:section_end]
    close_anchor = "      ],\n    );\n  }\n\n"
    pos = segment.rfind(close_anchor)
    if pos < 0:
        raise SystemExit("permission section close anchor missing")
    segment = (
        segment[:pos]
        + "        const SizedBox(height: 12),\n"
          "        ..._buildAdditionalPermissionGroups(isDark),\n"
        + segment[pos:]
    )
    helper = """  List<Widget> _buildAdditionalPermissionGroups(bool isDark) {
    final groups = <String, List<AdditionalEmployeePermissionSpec>>{};
    for (final spec in additionalEmployeePermissionSpecs) {
      groups.putIfAbsent(spec.group, () => <AdditionalEmployeePermissionSpec>[])
          .add(spec);
    }

    return groups.entries.map((entry) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isDark ? AppDarkColors.surface : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? AppDarkColors.cardBorder : const Color(0xFFE4E7EC),
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 7),
              child: Row(
                children: [
                  Icon(entry.value.first.icon, size: 17, color: AppColors.primary),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppDarkColors.textPrimary
                            : const Color(0xFF344054),
                      ),
                    ),
                  ),
                  Text(
                    '${entry.value.where((spec) => _additionalPermissions[spec.key] == true).length}/${entry.value.length}',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark
                          ? AppDarkColors.textSecondary
                          : const Color(0xFF667085),
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: isDark ? AppDarkColors.cardBorder : const Color(0xFFE4E7EC),
            ),
            ...List.generate(entry.value.length, (index) {
              final spec = entry.value[index];
              return _buildSwitch(
                spec.title,
                _additionalPermissions[spec.key] ?? false,
                (value) => setState(() => _additionalPermissions[spec.key] = value),
                isLast: index == entry.value.length - 1,
              );
            }),
          ],
        ),
      );
    }).toList(growable: false);
  }

"""
    text = text[:section_start] + segment + helper + text[section_end:]
write(ADD_USER, text)

text = read(PB_SERVICE)
start = text.find("  static Future<RecordModel> createUser({")
end = text.find("  static Future<void> updateUser(", start)
if start < 0 or end < 0:
    raise SystemExit("PBService createUser block not found")
block = text[start:end]
if "Map<String, bool> extraPermissions" not in block:
    anchor = "    double debtLimit = 0,\n"
    if anchor not in block:
        raise SystemExit("PBService createUser parameter anchor missing")
    block = block.replace(
        anchor,
        "    Map<String, bool> extraPermissions = const <String, bool>{},\n" + anchor,
        1,
    )
if "...extraPermissions," not in block:
    anchor = "      'debt_limit': debtLimit,\n"
    if anchor not in block:
        raise SystemExit("PBService createUser body anchor missing")
    block = block.replace(anchor, "      ...extraPermissions,\n" + anchor, 1)
text = text[:start] + block + text[end:]
write(PB_SERVICE, text)

text = read(UPDATE_ACCOUNT)
missing = [k for k in extra_keys if f'"{k}"' not in text]
if missing:
    anchor = '      "can_manage_security_settings",\n'
    if anchor not in text:
        raise SystemExit("update-account permission anchor missing")
    addition = "".join(f'      "{key}",\n' for key in missing)
    text = text.replace(anchor, anchor + addition, 1)
    write(UPDATE_ACCOUNT, text)

text = read(EMPLOYEE_CREATE)
missing = [k for k in extra_keys if f"  {k}:" not in text]
if missing:
    anchor = "  can_manage_security_settings: false,\n"
    if anchor not in text:
        raise SystemExit("employee-create permission anchor missing")
    addition = "".join(f"  {key}: false,\n" for key in missing)
    text = text.replace(anchor, anchor + addition, 1)
    write(EMPLOYEE_CREATE, text)

def sql_list(keys):
    return ",\n    ".join(f"'{k}'" for k in keys)

def sql_columns(keys, indent="  "):
    return ",\n".join(
        f"{indent}add column if not exists {k} boolean not null default false"
        for k in keys
    )

assign_profile = ",\n      ".join(f"{k} = new.{k}" for k in all_keys)
insert_cols = ",\n      ".join(all_keys)
insert_vals = ",\n      ".join(f"new.{k}" for k in all_keys)
conflict_updates = ",\n      ".join(f"{k} = excluded.{k}" for k in all_keys)

migration = f"""-- Expand employee authorization from 60 to 180 granular permissions.
-- All 120 new permissions default to false (least privilege).

alter table public.profiles
{sql_columns(extra_keys)};

alter table public.employee_permissions
{sql_columns(extra_keys)};

create or replace function public.set_employee_permissions_v2(
  p_employee_id uuid,
  p_permissions jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  requester public.profiles%rowtype;
  allowed_columns constant text[] := array[
    {sql_list(all_keys)}
  ];
  invalid_key text;
  invalid_type text;
  set_clause text;
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  select * into requester
  from public.profiles
  where id = auth.uid();

  if requester.id is null
     or requester.role <> 'admin'
     or requester.active is not true
     or requester.approved is not true then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = p_employee_id
      and p.role = 'employee'
      and p.admin_id = requester.id
  ) then
    raise exception 'employee_not_found_or_forbidden' using errcode = '42501';
  end if;

  if p_permissions is null or jsonb_typeof(p_permissions) <> 'object' then
    raise exception 'invalid_permissions_payload' using errcode = '22023';
  end if;

  select key into invalid_key
  from jsonb_object_keys(p_permissions) key
  where not (key = any(allowed_columns))
  limit 1;
  if invalid_key is not null then
    raise exception 'unknown_permission:%', invalid_key using errcode = '22023';
  end if;

  select e.key into invalid_type
  from jsonb_each(p_permissions) e
  where jsonb_typeof(e.value) <> 'boolean'
  limit 1;
  if invalid_type is not null then
    raise exception 'permission_must_be_boolean:%', invalid_type using errcode = '22023';
  end if;

  select string_agg(format('%I = %L::boolean', e.key, e.value #>> '{{}}'), ', ')
    into set_clause
  from jsonb_each(p_permissions) e;

  if set_clause is null or btrim(set_clause) = '' then return; end if;

  execute format(
    'update public.profiles set %s, updated_at = now() where id = $1',
    set_clause
  ) using p_employee_id;

  execute format(
    'update public.employee_permissions set %s, updated_at = now(), updated_by = $1 where employee_id = $2 and admin_id = $1',
    set_clause
  ) using requester.id, p_employee_id;
end;
$function$;

revoke all on function public.set_employee_permissions_v2(uuid, jsonb) from public, anon;
grant execute on function public.set_employee_permissions_v2(uuid, jsonb) to authenticated;

create or replace function private.sync_employee_permissions_to_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if pg_trigger_depth() > 1 then return new; end if;
  update public.profiles
  set {assign_profile},
      updated_at = now()
  where id = new.employee_id
    and role = 'employee'
    and admin_id = new.admin_id;
  return new;
end;
$function$;

create or replace function private.sync_profile_permissions_to_employee_permissions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if pg_trigger_depth() > 1 then return new; end if;

  if new.role = 'employee' and new.admin_id is not null then
    insert into public.employee_permissions (
      employee_id,
      admin_id,
      {insert_cols},
      updated_at,
      updated_by
    ) values (
      new.id,
      new.admin_id,
      {insert_vals},
      now(),
      auth.uid()
    )
    on conflict (employee_id) do update set
      admin_id = excluded.admin_id,
      {conflict_updates},
      updated_at = now(),
      updated_by = coalesce(auth.uid(), public.employee_permissions.updated_by);
  elsif tg_op = 'UPDATE' and old.role = 'employee' then
    delete from public.employee_permissions where employee_id = old.id;
  end if;

  return new;
end;
$function$;
"""
write(MIGRATION, migration)

contract = """#!/usr/bin/env python3
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

base_keys = set(re.findall(r"_EmployeePermissionSpec\\(key:\\s*'([^']+)'", base_text))
additional_keys = set(re.findall(r"AdditionalEmployeePermissionSpec\\(key:\\s*'([^']+)'", additional_text))
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
    r"allowed_columns\\s+constant\\s+text\\[\\]\\s*:=\\s*array\\[(.*?)\\];",
    migration_text,
    re.S,
)
if not allowed_match:
    fail("could not find 180-key set_employee_permissions_v2 allow-list")
allowed = set(re.findall(r"'(can_[a-z0-9_]+)'", allowed_match.group(1)))
compare("set_employee_permissions_v2", allowed, expected)

sync_to_profile = set(re.findall(
    r"^\\s*(?:set\\s+)?(can_[a-z0-9_]+)\\s*=\\s*new\\.\\1\\s*,?\\s*$",
    migration_text,
    re.M,
))
compare("employee_permissions -> profiles sync", sync_to_profile, expected)

edge_match = re.search(
    r"const\\s+tenantAdminFields\\s*=\\s*new\\s+Set\\(\\[(.*?)\\]\\);",
    update_text,
    re.S,
)
if not edge_match:
    fail("could not find update-account tenantAdminFields")
update_keys = set(re.findall(r'\"(can_[a-z0-9_]+)\"', edge_match.group(1)))
compare("update-account allow-list", update_keys, expected)

defaults_match = re.search(
    r"const\\s+permissionDefaults:\\s*Record<string,\\s*boolean>\\s*=\\s*\\{(.*?)\\n\\};",
    create_text,
    re.S,
)
if not defaults_match:
    fail("could not find employee-create permissionDefaults")
create_keys = set(re.findall(r"^\\s*(can_[a-z0-9_]+):\\s*(?:true|false),\\s*$", defaults_match.group(1), re.M))
compare("employee-create defaults", create_keys, expected)

if "left(permission_name, 4) = 'can_'" not in fix_prefix_text:
    fail("employee_has_permission must use literal can_ prefix matching")
if re.search(r"\\blike\\b.*\\bescape\\b", fix_prefix_text, re.I | re.S):
    fail("employee_has_permission must not use SQL ESCAPE parsing")

print(
    "employee-permissions-contract: OK "
    "(180/180 UI registry, create/update paths, schema, RPC, sync, and Edge Functions match)"
)
"""
write(CONTRACT, contract)

text = read(WORKFLOW)
paths_anchor = "      - 'lib/screens/shared/user_profile_employee_management.dart'\n"
extra_paths = (
    "      - 'lib/permissions/additional_employee_permissions.dart'\n"
    "      - 'lib/screens/shared/add_user_screen.dart'\n"
    "      - 'lib/services/pb_service.dart'\n"
    "      - 'supabase/functions/employee-create/index.ts'\n"
)
if "lib/permissions/additional_employee_permissions.dart" not in text:
    if paths_anchor not in text:
        raise SystemExit("contract workflow path anchor missing")
    text = text.replace(paths_anchor, paths_anchor + extra_paths, 1)
write(WORKFLOW, text)

print("expand_permissions_to_180: OK")
