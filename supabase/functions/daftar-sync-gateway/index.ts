import { createClient } from "npm:@supabase/supabase-js@2.116.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-daftar-sync-secret",
};

type SyncSource = {
  id: string;
  legacy_user_id: number;
  api_base_url: string;
  trigger_secret_hash: string;
  contacts_etag?: string | null;
  transactions_etag?: string | null;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function envJsonKey(name: string): string | null {
  const raw = Deno.env.get(name);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    return parsed.default ?? Object.values(parsed)[0] ?? null;
  } catch (_) {
    return raw;
  }
}

function isTransientDatabaseError(error: { message?: string; code?: string } | null): boolean {
  if (!error) return false;
  const message = String(error.message ?? "").toLowerCase();
  return message.includes("timeout") ||
    message.includes("gateway") ||
    message.includes("temporarily unavailable") ||
    String(error.code ?? "").startsWith("5");
}

function isTransientHttpStatus(status: number): boolean {
  return status === 408 || status === 425 || status === 429 || status >= 500;
}

async function delay(ms: number) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

async function loadSyncSource(admin: any, sourceId: string): Promise<SyncSource | null> {
  let lastError: any = null;
  for (let attempt = 1; attempt <= 4; attempt++) {
    const { data, error } = await admin
      .from("daftar_sync_sources")
      .select("id, legacy_user_id, api_base_url, trigger_secret_hash, contacts_etag, transactions_etag")
      .eq("id", sourceId)
      .eq("enabled", true)
      .maybeSingle();
    if (!error) return data as SyncSource | null;
    lastError = error;
    if (!isTransientDatabaseError(error) || attempt === 4) break;
    await delay(attempt * 500);
  }
  throw lastError ?? new Error("sync_source_lookup_failed");
}

type ProbeResult = {
  changed: boolean;
  etag: string | null;
  status: number;
};

async function probeEndpoint(
  url: string,
  legacyUserId: number,
  etag: string | null | undefined,
): Promise<ProbeResult> {
  if (!etag) return { changed: true, etag: null, status: 0 };

  const endpoint = new URL(url);
  endpoint.searchParams.set("user_id", String(legacyUserId));
  let lastError: unknown = null;

  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const response = await fetch(endpoint, {
        headers: {
          Accept: "application/json",
          "If-None-Match": etag,
        },
        signal: AbortSignal.timeout(15_000),
      });

      if (response.status === 304) {
        return {
          changed: false,
          etag: response.headers.get("etag") ?? etag,
          status: response.status,
        };
      }

      if (response.ok) {
        try {
          await response.body?.cancel();
        } catch (_) {}
        return {
          changed: true,
          etag: response.headers.get("etag"),
          status: response.status,
        };
      }

      if (!isTransientHttpStatus(response.status)) {
        throw new Error(`source_http_${response.status}`);
      }
      lastError = new Error(`source_http_${response.status}`);
    } catch (error) {
      lastError = error;
      if (error instanceof Error && error.message.startsWith("source_http_") &&
          !isTransientHttpStatus(Number(error.message.split("_").pop()))) {
        throw error;
      }
    }

    if (attempt < 3) await delay(attempt * 750);
  }

  throw lastError instanceof Error ? lastError : new Error("source_probe_failed");
}

async function markUpToDate(admin: any, sourceId: string) {
  const startedAt = Date.now();
  const finishedAt = new Date().toISOString();
  let lastError: any = null;
  for (let attempt = 1; attempt <= 4; attempt++) {
    const { error } = await admin
      .from("daftar_sync_sources")
      .update({
        lease_until: null,
        last_started_at: finishedAt,
        last_success_at: finishedAt,
        last_status: "success",
        last_error: null,
        consecutive_failures: 0,
        next_retry_at: null,
        circuit_open_until: null,
        last_heartbeat_at: finishedAt,
        last_duration_ms: Date.now() - startedAt,
        health_status: "healthy",
        last_result: {
          gateway: true,
          up_to_date: true,
          fetched_contacts: 0,
          fetched_transactions: 0,
        },
        updated_at: finishedAt,
      })
      .eq("id", sourceId);
    if (!error) {
      await admin.from("daftar_sync_runs").insert({
        sync_source_id: sourceId,
        status: "skipped",
        started_at: finishedAt,
        completed_at: finishedAt,
      });
      return;
    }
    lastError = error;
    if (!isTransientDatabaseError(error) || attempt === 4) break;
    await delay(attempt * 500);
  }
  throw lastError ?? new Error("sync_health_update_failed");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? envJsonKey("SUPABASE_SECRET_KEYS");
  if (!supabaseUrl || !secret) return json({ error: "server_not_configured" }, 500);

  const admin = createClient(supabaseUrl, secret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let sourceId = "";
  try {
    const body = await req.json().catch(() => ({}));
    sourceId = String(body?.source_id ?? "").trim();
    const providedSecret = req.headers.get("x-daftar-sync-secret") ?? "";
    if (!sourceId || !providedSecret) return json({ error: "unauthorized" }, 401);

    const source = await loadSyncSource(admin, sourceId);
    if (!source) return json({ error: "sync_source_not_found" }, 404);

    const providedHash = await sha256Hex(providedSecret);
    if (!constantTimeEqual(providedHash, source.trigger_secret_hash)) {
      return json({ error: "unauthorized" }, 401);
    }

    const [contactsProbe, transactionsProbe] = await Promise.all([
      probeEndpoint(
        `${source.api_base_url}/contacts`,
        source.legacy_user_id,
        source.contacts_etag,
      ),
      probeEndpoint(
        `${source.api_base_url}/transactions`,
        source.legacy_user_id,
        source.transactions_etag,
      ),
    ]);

    if (!contactsProbe.changed && !transactionsProbe.changed) {
      await markUpToDate(admin, source.id);
      return json({
        ok: true,
        skipped: true,
        reason: "source_not_modified",
        contacts_status: contactsProbe.status,
        transactions_status: transactionsProbe.status,
      });
    }

    let response: Response | null = null;
    let lastError: unknown = null;
    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        response = await fetch(`${supabaseUrl}/functions/v1/daftar-sync`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-daftar-sync-secret": providedSecret,
          },
          body: JSON.stringify({ source_id: source.id }),
          signal: AbortSignal.timeout(120_000),
        });
        if (response.ok || !isTransientHttpStatus(response.status)) break;
        lastError = new Error(`worker_http_${response.status}`);
      } catch (error) {
        lastError = error;
      }
      if (attempt < 3) await delay(attempt * attempt * 750 + Math.floor(Math.random() * 250));
    }
    if (!response) throw lastError instanceof Error ? lastError : new Error("worker_unreachable");

    const responseText = await response.text();
    return new Response(responseText, {
      status: response.status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error(error);
    const message = error instanceof Error
      ? error.message
      : String((error as { message?: unknown } | null)?.message ?? "internal_error");
    if (sourceId) {
      const { error: failureError } = await admin.rpc("record_daftar_sync_failure", {
        p_source_id: sourceId,
        p_error_code: message.split(":")[0] || "gateway_failed",
        p_error_detail: message,
        p_entity_kind: "gateway",
        p_entity_source_id: null,
        p_payload: { gateway: true },
      });
      if (failureError) console.error("gateway_failure_record_failed", failureError);
    }
    return json({ error: message }, 500);
  }
});
