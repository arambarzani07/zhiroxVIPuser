import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import { authorizeDaftarSyncRequest } from "../_shared/daftar_sync_auth.ts";
import { fixedDaftarUrl } from "../_shared/daftar_outbound/client.ts";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, x-client-info, apikey, content-type, x-daftar-sync-secret",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

function envJsonKey(name: string): string | null {
  const raw = Deno.env.get(name);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    const value = parsed.default ?? Object.values(parsed)[0];
    return typeof value === "string" ? value : null;
  } catch (_) {
    return raw;
  }
}

async function probeEndpoint(
  url: URL,
  method: "OPTIONS" | "POST" | "PATCH" | "DELETE" = "OPTIONS",
  probeBody?: Record<string, unknown>,
) {
  try {
    const response = await fetch(url, {
      method,
      redirect: "manual",
      signal: AbortSignal.timeout(8_000),
      headers: {
        accept: "application/json",
        ...((method === "PATCH" || method === "POST")
          ? { "content-type": "application/json" }
          : {}),
      },
      ...((method === "PATCH" || method === "POST")
        ? { body: JSON.stringify(probeBody ?? {}) }
        : {}),
    });
    const responseText = method === "OPTIONS"
      ? ""
      : (await response.text()).slice(0, 2000);
    return {
      url: url.toString(),
      method,
      status: response.status,
      allow: response.headers.get("allow"),
      cors_allow_methods: response.headers.get("access-control-allow-methods"),
      www_authenticate: response.headers.get("www-authenticate"),
      location: response.headers.get("location"),
      body: responseText,
    };
  } catch (error) {
    return {
      url: url.toString(),
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceCredential = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    envJsonKey("SUPABASE_SECRET_KEYS") ?? "";
  if (!url || !serviceCredential) return json({ error: "server_not_configured" }, 500);

  const admin = createClient(url, serviceCredential, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const body = await req.json().catch(() => ({}));
  const sourceId = String(body?.source_id ?? "").trim();
  const action = String(body?.action ?? "drain");
  if (!sourceId) return json({ error: "unauthorized" }, 401);

  const { data: source, error } = await admin.from("daftar_sync_sources")
    .select(
      "id, legacy_user_id, source_fingerprint, api_base_url, trigger_secret_hash, " +
        "sync_mode, outbound_sync_enabled, outbound_write_contract_status",
    )
    .eq("id", sourceId)
    .maybeSingle();

  if (error || !source) return json({ error: "sync_source_not_found" }, 404);
  if (
    Number(source.legacy_user_id) !== 28 ||
    source.source_fingerprint !== "daftar-live-account-28-v1"
  ) {
    return json({ error: "sync_source_not_allowed" }, 403);
  }

  const authorized = await authorizeDaftarSyncRequest({
    authorizationHeader: req.headers.get("authorization"),
    providedSecret: req.headers.get("x-daftar-sync-secret") ?? "",
    serviceCredential,
    expectedSecretHash: String(source.trigger_secret_hash ?? ""),
  });
  if (!authorized) return json({ error: "unauthorized" }, 401);

  if (action === "probe") {
    const base = String(source.api_base_url);
    const rootContacts = fixedDaftarUrl(base, "contacts");
    const rootTransactions = fixedDaftarUrl(base, "transactions");
    const missingContact = new URL(
      "contacts/0",
      base.endsWith("/") ? base : base + "/",
    );
    const missingTransaction = new URL(
      "transactions/0",
      base.endsWith("/") ? base : base + "/",
    );
    const results = await Promise.all([
      probeEndpoint(rootContacts),
      probeEndpoint(rootTransactions),
      probeEndpoint(missingContact),
      probeEndpoint(missingTransaction),
      probeEndpoint(missingContact, "PATCH"),
      probeEndpoint(missingContact, "DELETE"),
      probeEndpoint(missingTransaction, "PATCH"),
      probeEndpoint(missingTransaction, "DELETE"),
      probeEndpoint(rootContacts, "POST", {
        user_id: 28,
        name: { invalid: true },
        phone: { invalid: true },
      }),
      probeEndpoint(rootTransactions, "POST", {
        user_id: 28,
        contact_id: "invalid",
        transaction_type: "INVALID",
        amount: "invalid",
        currency: "IQD",
        transaction_date: "invalid",
        note: { invalid: true },
      }),
    ]);
    return json({
      ok: true,
      action: "probe",
      source_id: source.id,
      contract_status: source.outbound_write_contract_status,
      results,
    });
  }

  if (source.sync_mode !== "zhirox_primary") {
    return json({ error: "outbound_requires_zhirox_primary" }, 409);
  }
  if (source.outbound_sync_enabled !== true) {
    return json({ error: "outbound_sync_disabled" }, 409);
  }
  if (source.outbound_write_contract_status !== "verified") {
    return json({ error: "write_contract_unverified" }, 409);
  }

  return json({ error: "outbound_drain_not_enabled_yet" }, 409);
});
