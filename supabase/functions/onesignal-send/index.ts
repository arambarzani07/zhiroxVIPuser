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

function requiredEnv(name: string): string {
  const value = (Deno.env.get(name) ?? "").trim();
  if (!value) throw new Error(`missing_${name.toLowerCase()}`);
  return value;
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
  if (!normalized || normalized.length > maxLength) {
    throw new Error(`invalid_${field}`);
  }
  return normalized;
}

function sanitizeData(value: unknown): Record<string, unknown> {
  if (value == null) return {};
  if (typeof value !== "object" || Array.isArray(value)) {
    throw new Error("invalid_data");
  }
  const data = value as Record<string, unknown>;
  const encoded = JSON.stringify(data);
  if (encoded.length > 4096) throw new Error("data_too_large");
  return data;
}

function tenantId(profile: Record<string, unknown>): string {
  const role = String(profile.role ?? "");
  if (role === "admin") return String(profile.id ?? "");
  return String(profile.admin_id ?? "");
}

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const supabaseUrl = requiredEnv("SUPABASE_URL");
  const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
  const oneSignalAppId = requiredEnv("ONESIGNAL_APP_ID");
  const oneSignalRestApiKey = requiredEnv("ONESIGNAL_REST_API_KEY");

  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : "";
  if (!bearer) return json({ error: "authentication_required" }, 401);

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: authData, error: authError } = await admin.auth.getUser(bearer);
  if (authError || !authData.user) {
    return json({ error: "authentication_required" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "invalid_json" }, 400);
  }

  try {
    const targetUserId = requireUuid(body.target_user_id, "target_user_id");
    const title = requireText(body.title, "title", 120);
    const message = requireText(body.body, "body", 1000);
    const data = sanitizeData(body.data);

    const { data: actor, error: actorError } = await admin
      .from("profiles")
      .select("id,role,admin_id,active,is_system_owner")
      .eq("id", authData.user.id)
      .maybeSingle();

    if (actorError || !actor || actor.active !== true) {
      return json({ error: "forbidden" }, 403);
    }

    const actorRole = String(actor.role ?? "");
    let allowed = actorRole === "admin";

    if (actorRole === "employee") {
      const { data: permission, error: permissionError } = await admin
        .from("employee_permissions")
        .select("can_send_push_notifications,can_send_notifications")
        .eq("employee_id", actor.id)
        .maybeSingle();

      if (permissionError) throw permissionError;
      allowed = permission?.can_send_push_notifications === true ||
        permission?.can_send_notifications === true;
    }

    if (!allowed) return json({ error: "forbidden" }, 403);

    const { data: target, error: targetError } = await admin
      .from("profiles")
      .select("id,role,admin_id,active")
      .eq("id", targetUserId)
      .maybeSingle();

    if (targetError) throw targetError;
    if (!target || target.active !== true) {
      return json({ error: "target_not_found" }, 404);
    }

    const actorTenant = tenantId(actor as Record<string, unknown>);
    const targetTenant = tenantId(target as Record<string, unknown>);
    if (!actorTenant || actorTenant !== targetTenant) {
      return json({ error: "cross_tenant_forbidden" }, 403);
    }

    const payload = {
      app_id: oneSignalAppId,
      target_channel: "push",
      include_aliases: {
        external_id: [targetUserId],
      },
      headings: { en: title },
      contents: { en: message },
      data: {
        ...data,
        zhirox_target_user_id: targetUserId,
      },
    };

    const response = await fetch("https://api.onesignal.com/notifications", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Key ${oneSignalRestApiKey}`,
      },
      body: JSON.stringify(payload),
    });

    let result: Record<string, unknown> = {};
    try {
      result = await response.json();
    } catch (_) {
      result = {};
    }

    if (!response.ok) {
      console.error("OneSignal send failed", response.status, result);
      return json({ error: "onesignal_send_failed", status: response.status }, 502);
    }

    const messageId = typeof result.id === "string" ? result.id : null;
    if (!messageId) {
      return json({
        ok: false,
        delivered: false,
        reason: "no_active_push_subscription",
      }, 409);
    }

    return json({
      ok: true,
      delivered: true,
      message_id: messageId,
      target_user_id: targetUserId,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (
      message.startsWith("invalid_") ||
      message === "data_too_large"
    ) {
      return json({ error: message }, 400);
    }
    if (message.startsWith("missing_")) {
      console.error("OneSignal server configuration missing", message);
      return json({ error: "server_not_configured" }, 500);
    }
    console.error("onesignal-send error", message);
    return json({ error: "request_failed" }, 500);
  }
}

Deno.serve(handle);
