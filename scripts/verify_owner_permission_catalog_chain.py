#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260930165128_fix_owner_permission_catalog_invoker_chain.sql"


def fail(message: str) -> None:
    print(f"OWNER_PERMISSION_CATALOG_CHAIN_FAILED: {message}", file=sys.stderr)
    raise SystemExit(1)


if not MIGRATION.exists():
    fail(f"missing migration: {MIGRATION.relative_to(ROOT)}")

sql = MIGRATION.read_text(encoding="utf-8")

if "create or replace function private.get_system_owner_permission_catalog_internal()" not in sql:
    fail("missing private catalog implementation")
if "private.system_owner_has_permission(" not in sql or "'owner_access_console'" not in sql:
    fail("private implementation must enforce owner_access_console")
if "security definer" not in sql.lower():
    fail("private implementation must remain SECURITY DEFINER")
if "set search_path = ''" not in sql:
    fail("catalog functions must pin search_path")

match = re.search(
    r"create\s+or\s+replace\s+function\s+public\.get_system_owner_permission_catalog\(\)"
    r".*?\bas\s+\$\$(.*?)\$\$;",
    sql,
    flags=re.IGNORECASE | re.DOTALL,
)
if not match:
    fail("missing public catalog wrapper")

wrapper = match.group(1)
if "private.assert_system_owner_permission" in wrapper:
    fail("public SECURITY INVOKER wrapper must not directly execute the private guard")
if "private.get_system_owner_permission_catalog_internal()" not in wrapper:
    fail("public wrapper must delegate to the private implementation")

if "revoke all on function public.get_system_owner_permission_catalog() from public, anon;" not in sql:
    fail("public/anon revoke contract changed")
if "grant execute on function public.get_system_owner_permission_catalog() to authenticated;" not in sql:
    fail("authenticated execute grant missing")

print("OWNER_PERMISSION_CATALOG_CHAIN_OK invoker_wrapper=clean internal_guard=owner_access_console")
