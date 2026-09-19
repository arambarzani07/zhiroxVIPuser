#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
edge = (ROOT / 'supabase/functions/debt-restore-admin/index.ts').read_text(errors='ignore')
config = (ROOT / 'supabase/config.toml').read_text(errors='ignore')

service = 'Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")'
bundle = 'envJsonKey("SUPABASE_SECRET_KEYS")'
assert service in edge and bundle in edge, "debt restore admin must support both secret-key generations"
assert edge.index(bundle) < edge.index(service), (
    "debt restore admin must prefer SUPABASE_SECRET_KEYS default for projects using new API keys"
)
assert 'const token = authHeader.startsWith("Bearer ")' in edge, "restore gateway must validate caller bearer token itself"
assert "admin.auth.getUser(token)" in edge, "restore gateway must authenticate the caller inside the handler"
assert "profile.role !== 'admin'" in edge, "restore gateway must remain admin-only"
assert ".eq('is_deleted', true)" in edge, "restore list must fetch only soft-deleted debts"
assert "restore_debt_service" in edge, "restore action must remain server-side"

section = "[functions.debt-restore-admin]\nverify_jwt = false"
assert section in config, (
    "debt restore admin must disable the platform JWT gate because it performs authenticated user validation internally"
)

print("debt restore admin configuration verified")
