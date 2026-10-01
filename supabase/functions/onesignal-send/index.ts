import { createClient } from "npm:@supabase/supabase-js@2.116.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
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

function requireUuid(value: unknown, field: string): string {
  const normalized = String(value ?? "").trim();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(normalized)) {
    throw new Error(`invalid_${field}`);
  }
  return normalized;
}

function requireText(value: unknown, field: string, maxLength: number): string {
  const normalized = String(value ?? "").trim();
  if (!normalized || normalized.length > maxLength) throw new Error(`invalid_${field}`);
  return normalized;
}

function sanitizeData(value: unknown): Record<string, unknown> {
  if (value == null) return {};
  if (typeof value !== "object" || Array.isArray(value)) throw new Error("invalid_data");
  const data = value as Record<string, unknown>;
  if (JSON.stringify(data).length > 4096) throw new Error("data_too_large");
  return data;
}

function tenantId(profile: Record<string, unknown>): string {
  const role = String(profile.role ?? "");
  return role === "admin" ? String(profile.id ?? "") : String(profile.admin_id ?? "");
}

async function loadOneSignalRuntime(admin: any): Promise<{ appId: string; apiKey: string }> {
  let appId = env("ONESIGNAL_APP_ID");
  let apiKey = env("ONESIGNAL_REST_API_KEY");
  if (appId && apiKey) return { appId, apiKey };
  const { data, error } = await admin.rpc("get_onesignal_runtime_config_service");
  if (!error) {
    const row = Array.isArray(data) ? data[0] : data;
    appId ||= String(row?.app_id ?? "").trim();
    apiKey ||= String(row?.rest_api_key ?? "").trim();
  }
  return { appId, apiKey };
}

async function queueRealtimeFallback(
  admin: any,
  targetUserId: string,
  marketId: string,
  title: string,
  message: string,
  data: Record<string, unknown>,
): Promise<boolean> {
  const eventType = String(data.event_type ?? data.type ?? "manual").trim().slice(0, 80) || "manual";
  const { error } = await admin.from("app_realtime_notifications").insert({
    recipient_user_id: targetUserId,
    market_id: marketId || null,
    title,
    body: message,
    event_type: eventType,
    data: { ...data, zhirox_target_user_id: targetUserId, delivery_fallback: "supabase_realtime" },
    expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
  });
  if (error) {
    console.error("Realtime notification fallback insert failed", error.message);
    return false;
  }
  return true;
}

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const supabaseUrl = env("SUPABASE_URL");
  const secret = serviceKey();
  if (!supabaseUrl || !secret) return json({ error: "server_not_configured" }, 500);

  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : "";
  if (!bearer) return json({ error: "authentication_required" }, 401);

  const admin = createClient(supabaseUrl, secret, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await admin.auth.getUser(bearer);
  if (authError || !authData.user) return json({ error: "authentication_required" }, 401);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch (_) { return json({ error: "invalid_json" }, 400); }

  try {
    const targetUserId = requireUuid(body.target_user_id, "target_user_id");
    const title = requireText(body.title, "title", 120);
    const message = requireText(body.body, "body", 1000);
    const data = sanitizeData(body.data);

    const { data: actor, error: actorError } = await admin.from("profiles")
      .select("id,role,admin_id,active,is_system_owner").eq("id", authData.user.id).maybeSingle();
    if (actorError || !actor || actor.active !== true) return json({ error: "forbidden" }, 403);

    const actorRole = String(actor.role ?? "");
    let allowed = actorRole === "admin";
    if (actorRole === "employee") {
      const { data: permission, error: permissionError } = await admin.from("employee_permissions")
        .select("can_send_push_notifications,can_send_notifications").eq("employee_id", actor.id).maybeSingle();
      if (permissionError) throw permissionError;
      allowed = permission?.can_send_push_notifications === true || permission?.can_send_notifications === true;
    }
    if (!allowed) return json({ error: "forbidden" }, 403);

    const { data: target, error: targetError } = await admin.from("profiles")
      .select("id,role,admin_id,active").eq("id", targetUserId).maybeSingle();
    if (targetError) throw targetError;
    if (!target || target.active !== true) return json({ error: "target_not_found" }, 404);

    const actorTenant = tenantId(actor as Record<string, unknown>);
    const targetTenant = tenantId(target as Record<string, unknown>);
    if (!actorTenant || actorTenant !== targetTenant) return json({ error: "cross_tenant_forbidden" }, 403);

    const { appId, apiKey } = await loadOneSignalRuntime(admin);
    if (!appId || !apiKey) {
      const queued = await queueRealtimeFallback(admin, targetUserId, targetTenant, title, message, data);
      if (!queued) return json({ error: "notification_delivery_unavailable" }, 503);
      return json({ ok: true, delivered: false, fallback_queued: true, delivery: "supabase_realtime", reason: "onesignal_not_configured", target_user_id: targetUserId });
    }

    let response: Response;
    let result: Record<string, unknown> = {};
    try {
      response = await fetch("https://api.onesignal.com/notifications", {
        method: "POST",
        headers: { "Content-Type": "application/json", "Authorization": `Key ${apiKey}` },
        body: JSON.stringify({
          app_id: appId,
          target_channel: "push",
          include_aliases: { external_id: [targetUserId] },
          headings: { en: title },
          contents: { en: message },
          data: { ...data, zhirox_target_user_id: targetUserId },
        }),
      });
      try { result = await response.json(); } catch (_) {}
    } catch (error) {
      console.error("OneSignal network send failed", error instanceof Error ? error.message : String(error));
      const queued = await queueRealtimeFallback(admin, targetUserId, targetTenant, title, message, data);
      if (!queued) return json({ error: "notification_delivery_unavailable" }, 503);
      return json({ ok: true, delivered: false, fallback_queued: true, delivery: "supabase_realtime", reason: "onesignal_network_failed", target_user_id: targetUserId });
    }

    const messageId = typeof result.id === "string" && result.id.trim() ? result.id.trim() : null;
    if (!response.ok || !messageId) {
      console.error("OneSignal send unavailable; using realtime fallback", response.status, result);
      const queued = await queueRealtimeFallback(admin, targetUserId, targetTenant, title, message, data);
      if (!queued) return json({ error: "notification_delivery_unavailable" }, 503);
      return json({
        ok: true,
        delivered: false,
        fallback_queued: true,
        delivery: "supabase_realtime",
        reason: response.ok ? "no_active_push_subscription" : "onesignal_send_failed",
        target_user_id: targetUserId,
      });
    }

    return json({ ok: true, delivered: true, fallback_queued: false, delivery: "onesignal", message_id: messageId, target_user_id: targetUserId });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (message.startsWith("invalid_") || message === "data_too_large") return json({ error: message }, 400);
    console.error("onesignal-send error", message);
    return json({ error: "request_failed" }, 500);
  }
}

Deno.serve(handle);
