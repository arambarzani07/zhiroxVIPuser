import { createClient } from "npm:@supabase/supabase-js@2.116.0";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST,OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function env(name: string): string { return (Deno.env.get(name) ?? "").trim(); }
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
function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
async function sha256Hex(value: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
  return Array.from(digest).map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = env("SUPABASE_URL");
  const key = serviceKey();
  if (!url || !key) return json({ error: "server_not_configured" }, 500);

  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : "";
  if (!bearer) return json({ error: "authentication_required" }, 401);

  const admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await admin.auth.getUser(bearer);
  const user = authData.user;
  if (authError || !user) return json({ error: "authentication_required" }, 401);

  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("id, role, active, approved, market_name")
    .eq("id", user.id)
    .maybeSingle();
  if (profileError || !profile || profile.role !== "admin" || profile.active !== true || profile.approved !== true) {
    return json({ error: "admin_required" }, 403);
  }
  const marketId = user.id;

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch (_) { return json({ error: "invalid_json" }, 400); }
  const action = String(body.action ?? "status").trim();

  try {
    if (action === "status") {
      const [{ data: config, error: configError }, { data: statusRows, error: statusError }] = await Promise.all([
        admin.from("hikvision_market_config")
          .select("enabled,auto_capture,nvr_label,nvr_host,nvr_model,nvr_firmware,cashier_channel_id,pre_seconds,post_seconds,timezone,retention_days,updated_at")
          .eq("market_id", marketId)
          .maybeSingle(),
        admin.rpc("hikvision_gateway_status_service", { p_market_id: marketId }),
      ]);
      if (configError) throw configError;
      if (statusError) throw statusError;
      const gateway = Array.isArray(statusRows) && statusRows.length > 0 ? statusRows[0] : null;
      return json({ ok: true, market_name: profile.market_name, config, gateway });
    }

    if (action === "issue_gateway_token") {
      const random = new Uint8Array(32);
      crypto.getRandomValues(random);
      const token = `zg_${base64Url(random)}`;
      const hash = await sha256Hex(token);
      const { data, error } = await admin.rpc("hikvision_gateway_rotate_token_service", {
        p_market_id: marketId,
        p_token_sha256: hash,
      });
      if (error) throw error;
      const row = Array.isArray(data) && data.length > 0 ? data[0] : null;
      if (!row) return json({ error: "gateway_not_registered" }, 409);
      return json({
        ok: true,
        gateway_id: row.gateway_id,
        gateway_token: token,
        note: "Store this token only on the local market gateway. It is returned once and only its SHA-256 hash is stored in the cloud.",
      });
    }

    if (action === "update_config") {
      const channel = Math.trunc(Number(body.cashier_channel_id ?? 1));
      const pre = Math.trunc(Number(body.pre_seconds ?? 15));
      const post = Math.trunc(Number(body.post_seconds ?? 30));
      const retention = Math.trunc(Number(body.retention_days ?? 90));
      if (channel < 1 || channel > 256 || pre < 0 || pre > 300 || post < 1 || post > 600 || retention < 1 || retention > 3650) {
        return json({ error: "invalid_config" }, 400);
      }
      const update = {
        enabled: body.enabled !== false,
        auto_capture: body.auto_capture !== false,
        cashier_channel_id: channel,
        pre_seconds: pre,
        post_seconds: post,
        retention_days: retention,
        updated_at: new Date().toISOString(),
      };
      const { data, error } = await admin
        .from("hikvision_market_config")
        .update(update)
        .eq("market_id", marketId)
        .select("enabled,auto_capture,cashier_channel_id,pre_seconds,post_seconds,retention_days,updated_at")
        .single();
      if (error) throw error;
      return json({ ok: true, config: data });
    }

    if (action === "video_url") {
      const sourceType = String(body.source_type ?? "").trim();
      const sourceId = String(body.source_id ?? "").trim();
      if (!["debt", "payment", "general_payment"].includes(sourceType) || !/^[0-9a-f-]{36}$/i.test(sourceId)) {
        return json({ error: "invalid_transaction" }, 400);
      }
      const { data: evidence, error } = await admin
        .from("transaction_video_evidence")
        .select("status,object_path,channel_id,transaction_at,clip_start_at,clip_end_at,captured_at")
        .eq("market_id", marketId)
        .eq("source_type", sourceType)
        .eq("source_id", sourceId)
        .maybeSingle();
      if (error) throw error;
      if (!evidence) return json({ error: "video_not_found" }, 404);
      if (evidence.status !== "ready" || !evidence.object_path) {
        return json({ ok: true, ready: false, evidence });
      }
      const { data: signed, error: signedError } = await admin.storage
        .from("transaction-camera-clips")
        .createSignedUrl(evidence.object_path, 600);
      if (signedError || !signed?.signedUrl) throw signedError ?? new Error("signed_read_failed");
      return json({ ok: true, ready: true, signed_url: signed.signedUrl, expires_in: 600, evidence });
    }

    return json({ error: "unsupported_action" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("hikvision-admin", action, message.slice(0, 300));
    return json({ error: "hikvision_admin_failed" }, 500);
  }
});
