#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
edge = (ROOT / 'supabase/functions/debt-restore-admin/index.ts').read_text(errors='ignore')

service = 'Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")'
bundle = 'envJsonKey("SUPABASE_SECRET_KEYS")'
assert service in edge and bundle in edge, "debt restore admin must support both service-role secret sources"
assert edge.index(service) < edge.index(bundle), (
    "debt restore admin must prefer SUPABASE_SERVICE_ROLE_KEY so soft-deleted rows "
    "are always queried with service-role privileges"
)
assert ".eq('is_deleted', true)" in edge, "restore list must fetch only soft-deleted debts"
assert "restore_debt_service" in edge, "restore action must remain server-side"

print("debt restore admin configuration verified")
