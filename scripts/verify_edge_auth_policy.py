#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
config = (ROOT / "supabase/config.toml").read_text(encoding="utf-8")

sections = {}
current = None
for line in config.splitlines():
    m = re.match(r"\[functions\.([^\]]+)\]", line.strip())
    if m:
        current = m.group(1)
        sections[current] = []
        continue
    if current is not None:
        sections[current].append(line)

false_jwt = {
    name
    for name, body in sections.items()
    if re.search(r"^\s*verify_jwt\s*=\s*false\s*$", "\n".join(body), re.M)
}

contracts = {
    "fib-subscription-payment": ("auth.getUser(token)",),
    "customer-read-link": ("auth.getUser(", "p_token_hash"),
    "customer-push": ("sha256Hex", "deviceSecretHash", "consumeRateLimit"),
    "customer-push-manifest": ("manifestResponse", "application/manifest+json"),
    "customer-push-worker": ('x-zhirox-push-worker', "workerSecret"),
    "debt-restore-admin": ("auth.getUser(token)", "admin_required"),
    "daftar-sync": ("authorizeDaftarSyncRequest", "x-daftar-sync-secret"),
    "daftar-sync-gateway": ("x-daftar-sync-secret", "constantTimeEqual"),
    "daftar-live-read": ("auth.getUser(", "authentication_required"),
    "daftar-outbound-sync": ("authorizeDaftarSyncRequest", "x-daftar-sync-secret"),
    "daftar-credit-gateway": (
        "authorizeLegacyMutation",
        "if (['POST','PUT','PATCH','DELETE'].includes(req.method))",
        "authentication_required",
        "AbortSignal.timeout(10_000)",
    ),
    # The Windows Hikvision gateway is a machine client, not a Supabase user.
    # It authenticates with a high-entropy one-time-issued gateway token. Only
    # the SHA-256 digest is sent to the service-role-only lookup RPC; the raw
    # token is never persisted in Supabase.
    "hikvision-gateway": (
        "x-zhirox-gateway-token",
        "sha256Hex(token)",
        "hikvision_gateway_auth_service",
        'if (token.length < 32 || token.length > 256)',
    ),
    # The Hik-Connect cloud worker is a cron/machine client. It authenticates
    # with a high-entropy worker secret held in Vault. The request secret is
    # hashed before the service-role-only auth RPC compares it with the stored
    # SHA-256 digest; no ordinary Supabase user can invoke worker RPCs directly.
    "hikvision-cloud-worker": (
        "x-zhirox-hikvision-cloud-worker",
        "sha256Hex(secret)",
        "hikvision_cloud_worker_auth_service",
        'if (secret.length < 32 || secret.length > 256)',
    ),
}

unknown = sorted(false_jwt - set(contracts))
missing = sorted(set(contracts) - false_jwt)

errors = []
if unknown:
    errors.append("verify_jwt=false functions without an auth contract: " + ", ".join(unknown))
if missing:
    errors.append("auth contract mapping no longer matches config: " + ", ".join(missing))

for name in sorted(false_jwt & set(contracts)):
    path = ROOT / "supabase/functions" / name / "index.ts"
    if not path.exists():
        errors.append(f"{name}: source file missing")
        continue
    source = path.read_text(encoding="utf-8")
    for marker in contracts[name]:
        if marker not in source:
            errors.append(f"{name}: missing auth marker: {marker}")

for name in ("netlify-upload-dq", "netlify-manual-deploy-dq"):
    path = ROOT / "supabase/functions" / name / "index.ts"
    if not path.exists():
        errors.append(f"{name}: retired helper stub missing")
        continue
    source = path.read_text(encoding="utf-8")
    if "Legacy Netlify deployment helper is retired." not in source:
        errors.append(f"{name}: retired helper must stay disabled")
    for forbidden in ("netlify-mcp.netlify.app/proxy/", "siteId=", "SUPABASE_SERVICE_ROLE_KEY"):
        if forbidden in source:
            errors.append(f"{name}: retired helper leaked active deployment capability: {forbidden}")

if errors:
    print("EDGE AUTH POLICY FAILED")
    for error in errors:
        print(" - " + error)
    sys.exit(1)

print("Edge auth policy verified")
