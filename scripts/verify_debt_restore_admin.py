#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
screen = (ROOT / 'lib/screens/admin/debt_restore_screen.dart').read_text(errors='ignore')
migration = (ROOT / 'supabase/migrations/20260919193000_direct_admin_debt_restore_rpc.sql').read_text(errors='ignore')

assert "PBService.client.rpc(" in screen, "restore screen must use direct authenticated Postgres RPC"
assert "'list_deleted_debts'" in screen, "restore screen must list deleted debts through list_deleted_debts RPC"
assert "'restore_deleted_debt'" in screen, "restore screen must restore debts through restore_deleted_debt RPC"
assert "'debt-restore-admin'" not in screen, "restore screen must not depend on the Edge Function gateway"
assert "grant execute on function public.list_deleted_debts(integer) to authenticated" in migration
assert "create or replace function public.restore_deleted_debt(p_debt_id uuid)" in migration
assert "security definer" in migration.lower()
assert "auth.uid()" in migration
assert "grant execute on function public.restore_deleted_debt(uuid) to authenticated" in migration

print("direct admin debt restore RPC verified")
