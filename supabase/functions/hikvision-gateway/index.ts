import { createClient } from "npm:@supabase/supabase-js@2.116.0";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-zhirox-gateway-token, x-gateway-version, x-gateway-platform",
  "Access-Control-Allow-Methods": "POST,OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function env(name: string): string {
  return (Deno.env.get(name) ?? "").trim();
}

function serviceKey(): string {
  const modern = env("SUPABASE_SECRET_KEYS");
  if (modern) {
    try {
      const parsed = JSON.parse(modern) as Record<string, string>;
      const value = parsed.default ?? Object.values(parsed)[0];
      if (value) return String(value).trim();
    } catch (_) {}
  }
  return env("SUPABASE_SERVICE_ROLE_KEY");
}

async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return Array.from(digest).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function safeId(value: unknown): string {
  const text = String(value ?? "").trim();
  return /^[0-9a-f-]{36}$/i.test(text) ? text : "";
}

function supportsAttemptFencing(version: string): boolean {
  const match = version.trim().match(/^(\d+)\.(\d+)(?:\.(\d+))?/);
  if (!match) return false;
  const major = Number(match[1]);
  const minor = Number(match[2]);
  return major > 1 || (major === 1 && minor >= 1);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = env("SUPABASE_URL");
  const key = serviceKey();
  if (!url || !key) return json({ error: "server_not_configured" }, 500);

  const token = (req.headers.get("x-zhirox-gateway-token") ?? "").trim();
  if (token.length < 32 || token.length > 256) return json({ error: "unauthorized" }, 401);

  const admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const tokenHash = await sha256Hex(token);
  const { data: authRows, error: authError } = await admin.rpc("hikvision_gateway_auth_service", {
    p_token_sha256: tokenHash,
  });
  const gateway = Array.isArray(authRows) ? authRows[0] : null;
  if (authError || !gateway?.gateway_id || !gateway?.market_id) return json({ error: "unauthorized" }, 401);

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch (_) { return json({ error: "invalid_json" }, 400); }

  const action = String(body.action ?? "ping").trim();
  const gatewayId = String(gateway.gateway_id);
  const marketId = String(gateway.market_id);
  const gatewayVersion = (req.headers.get("x-gateway-version") ?? "").slice(0, 120);
  const platform = (req.headers.get("x-gateway-platform") ?? "").slice(0, 120);
  const forwarded = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim().slice(0, 120);
  const v2Gateway = supportsAttemptFencing(gatewayVersion);

  try {
    if (action === "ping") {
      await admin.rpc("hikvision_gateway_heartbeat_service", {
        p_gateway_id: gatewayId,
        p_gateway_version: gatewayVersion,
        p_platform: platform,
        p_ip: forwarded || null,
      });
      return json({
        ok: true,
        gateway_id: gatewayId,
        market_id: marketId,
        server_time: new Date().toISOString(),
        capabilities: { attempt_fencing: v2Gateway },
      });
    }

    if (action === "claim") {
      await admin.rpc("hikvision_gateway_heartbeat_service", {
        p_gateway_id: gatewayId,
        p_gateway_version: gatewayVersion,
        p_platform: platform,
        p_ip: forwarded || null,
      });
      const rpc = v2Gateway ? "hikvision_gateway_claim_v2_service" : "hikvision_gateway_claim_service";
      const { data, error } = await admin.rpc(rpc, { p_gateway_id: gatewayId });
      if (error) throw error;
      const job = Array.isArray(data) && data.length > 0 ? data[0] : null;
      return json({ ok: true, job, protocol: v2Gateway ? 2 : 1 });
    }

    if (action === "heartbeat_job") {
      const jobId = safeId(body.job_id);
      const attemptToken = safeId(body.attempt_token);
      if (!jobId || !attemptToken) return json({ error: "invalid_attempt" }, 400);
      const { data, error } = await admin.rpc("hikvision_gateway_job_heartbeat_v2_service", {
        p_gateway_id: gatewayId,
        p_job_id: jobId,
        p_attempt_token: attemptToken,
      });
      if (error) throw error;
      if (data !== true) return json({ error: "stale_or_invalid_attempt" }, 409);
      return json({ ok: true });
    }

    if (action === "prepare_upload") {
      const jobId = safeId(body.job_id);
      const attemptToken = safeId(body.attempt_token);
      if (!jobId) return json({ error: "invalid_job_id" }, 400);

      const rpc = attemptToken
        ? "hikvision_gateway_prepare_upload_v2_service"
        : "hikvision_gateway_prepare_upload_service";
      const args = attemptToken
        ? { p_gateway_id: gatewayId, p_job_id: jobId, p_attempt_token: attemptToken }
        : { p_gateway_id: gatewayId, p_job_id: jobId };
      const { data, error } = await admin.rpc(rpc, args);
      if (error) throw error;
      const row = Array.isArray(data) && data.length > 0 ? data[0] : null;
      if (!row) return json({ error: "stale_or_invalid_attempt" }, 409);

      const at = new Date(row.transaction_at);
      const yyyy = String(at.getUTCFullYear());
      const mm = String(at.getUTCMonth() + 1).padStart(2, "0");
      const dd = String(at.getUTCDate()).padStart(2, "0");
      const attemptSuffix = attemptToken ? `-a${Number(row.attempt_generation ?? 0)}` : "";
      const path = `${marketId}/${yyyy}/${mm}/${dd}/${row.source_type}/${row.source_id}-${jobId}${attemptSuffix}.mp4`;
      const { data: signed, error: signedError } = await admin.storage
        .from("transaction-camera-clips")
        .createSignedUploadUrl(path);
      if (signedError || !signed?.signedUrl) throw signedError ?? new Error("signed_upload_failed");
      return json({
        ok: true,
        job_id: jobId,
        attempt_generation: row.attempt_generation ?? null,
        object_path: path,
        signed_upload_url: signed.signedUrl,
        upload_token: signed.token ?? null,
      });
    }

    if (action === "complete") {
      const jobId = safeId(body.job_id);
      const attemptToken = safeId(body.attempt_token);
      const objectPath = String(body.object_path ?? "").trim();
      if (!jobId || !objectPath.startsWith(`${marketId}/`) || objectPath.length > 1024) {
        return json({ error: "invalid_completion" }, 400);
      }
      const sha = String(body.content_sha256 ?? "").trim().toLowerCase();
      if (sha && !/^[0-9a-f]{64}$/.test(sha)) return json({ error: "invalid_sha256" }, 400);
      const byteSize = body.byte_size == null ? null : Number(body.byte_size);
      const duration = body.duration_seconds == null ? null : Number(body.duration_seconds);
      const metadata = body.playback_metadata && typeof body.playback_metadata === "object"
        ? body.playback_metadata
        : {};

      const rpc = attemptToken
        ? "hikvision_gateway_complete_v2_service"
        : "hikvision_gateway_complete_service";
      const args: Record<string, unknown> = {
        p_gateway_id: gatewayId,
        p_job_id: jobId,
        p_object_path: objectPath,
        p_thumbnail_path: null,
        p_content_sha256: sha || null,
        p_byte_size: Number.isFinite(byteSize) ? Math.max(0, Math.trunc(byteSize as number)) : null,
        p_duration_seconds: Number.isFinite(duration) ? Math.max(0, Math.trunc(duration as number)) : null,
        p_playback_metadata: metadata,
      };
      if (attemptToken) args.p_attempt_token = attemptToken;

      const { data, error } = await admin.rpc(rpc, args);
      if (error) throw error;
      if (data !== true) return json({ error: "stale_or_invalid_attempt" }, 409);
      return json({ ok: true, status: "ready" });
    }

    if (action === "fail") {
      const jobId = safeId(body.job_id);
      const attemptToken = safeId(body.attempt_token);
      if (!jobId) return json({ error: "invalid_job_id" }, 400);
      const reason = String(body.error ?? "gateway_failed").slice(0, 1000);
      const missing = body.missing === true;

      const rpc = attemptToken
        ? "hikvision_gateway_fail_v2_service"
        : "hikvision_gateway_fail_service";
      const args: Record<string, unknown> = {
        p_gateway_id: gatewayId,
        p_job_id: jobId,
        p_error: reason,
        p_missing: missing,
      };
      if (attemptToken) args.p_attempt_token = attemptToken;

      const { data, error } = await admin.rpc(rpc, args);
      if (error) throw error;
      if (data !== true) return json({ error: "stale_or_invalid_attempt" }, 409);
      return json({ ok: true, status: missing ? "missing" : "recorded" });
    }

    return json({ error: "unsupported_action" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("hikvision-gateway", action, message.slice(0, 300));
    return json({ error: "gateway_request_failed" }, 500);
  }
});