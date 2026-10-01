import { createClient } from "npm:@supabase/supabase-js@2.116.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

function env(name: string): string {
  return (Deno.env.get(name) ?? "").trim();
}

function serviceKey(): string {
  const raw = env("SUPABASE_SECRET_KEYS");
  if (raw) {
    try {
      const parsed = JSON.parse(raw) as Record<string, string>;
      const value = parsed.default ?? Object.values(parsed)[0];
      if (value) return String(value).trim();
    } catch (_) {}
  }
  return env("SUPABASE_SERVICE_ROLE_KEY");
}

async function sha256Hex(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", data));
  return Array.from(hash).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function loadBotToken(admin: any): Promise<string> {
  const configured = env("TELEGRAM_BOT_TOKEN");
  if (configured) return configured;
  const { data, error } = await admin.rpc("get_telegram_runtime_config_service");
  if (error) return "";
  const row = Array.isArray(data) ? data[0] : data;
  return String(row?.bot_token ?? "").trim();
}

async function telegramApi(token: string, method: string, body: Record<string, unknown>) {
  const response = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(8000),
  });
  let payload: any = {};
  try { payload = await response.json(); } catch (_) {}
  if (!response.ok || payload?.ok !== true) {
    throw new Error(`telegram_${method}_failed`);
  }
  return payload.result;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const supabaseUrl = env("SUPABASE_URL");
  const secret = serviceKey();
  if (!supabaseUrl || !secret) return json({ error: "server_not_configured" }, 500);

  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : "";
  if (!bearer) return json({ error: "authentication_required" }, 401);

  const admin = createClient(supabaseUrl, secret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await admin.auth.getUser(bearer);
  if (authError || !authData.user) return json({ error: "authentication_required" }, 401);

  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("id,active,is_system_owner,can_manage_security_settings")
    .eq("id", authData.user.id)
    .maybeSingle();
  if (profileError) return json({ error: "profile_lookup_failed" }, 500);
  if (!profile || profile.active !== true || profile.is_system_owner !== true) {
    return json({ error: "system_owner_required" }, 403);
  }

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch (_) { return json({ error: "invalid_json" }, 400); }
  const action = String(body.action ?? "status").trim();

  try {
    if (action === "status") {
      const token = await loadBotToken(admin);
      if (!token) return json({ ok: true, configured: false, verified: false, bot_username: null });
      try {
        const me = await telegramApi(token, "getMe", {});
        const username = String(me?.username ?? "").trim();
        return json({ ok: true, configured: true, verified: true, bot_username: username ? `@${username}` : null });
      } catch (_) {
        return json({ ok: true, configured: true, verified: false, bot_username: null });
      }
    }

    if (action === "set_token") {
      const token = String(body.bot_token ?? "").trim();
      if (token.length < 20 || token.length > 512 || !token.includes(":")) {
        return json({ error: "invalid_telegram_bot_token" }, 400);
      }

      const me = await telegramApi(token, "getMe", {});
      const username = String(me?.username ?? "").trim();
      if (!username) return json({ error: "telegram_bot_username_missing" }, 400);

      const webhookSecret = await sha256Hex(token);
      await telegramApi(token, "setWebhook", {
        url: `${supabaseUrl}/functions/v1/telegram-webhook`,
        secret_token: webhookSecret,
        allowed_updates: ["message"],
        drop_pending_updates: false,
      });

      const { error } = await admin.rpc("set_telegram_bot_token_service", { p_bot_token: token });
      if (error) throw error;

      return json({ ok: true, configured: true, verified: true, bot_username: `@${username}` });
    }

    if (action === "clear_token") {
      const token = await loadBotToken(admin);
      if (token) {
        try { await telegramApi(token, "deleteWebhook", { drop_pending_updates: false }); } catch (_) {}
      }
      const { error } = await admin.rpc("clear_telegram_bot_token_service");
      if (error) throw error;
      return json({ ok: true, configured: false, verified: false, bot_username: null });
    }

    return json({ error: "unsupported_action" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("telegram-admin-config error", message.replace(/bot\d+:[^/\s]+/g, "bot[redacted]"));
    if (message.startsWith("telegram_")) return json({ error: message }, 502);
    return json({ error: "request_failed" }, 500);
  }
});
