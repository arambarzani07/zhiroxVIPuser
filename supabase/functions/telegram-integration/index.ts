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
  for (const value of bytes) binary += String.fromCharCode(value);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

async function sha256Hex(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", data));
  return Array.from(hash).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function loadBotToken(admin: any): Promise<string> {
  const fromEnv = env("TELEGRAM_BOT_TOKEN");
  if (fromEnv) return fromEnv;
  const { data, error } = await admin.rpc("get_telegram_runtime_config_service");
  if (error) return "";
  const row = Array.isArray(data) ? data[0] : data;
  return String(row?.bot_token ?? "").trim();
}

async function telegramApi(
  token: string,
  method: string,
  body: Record<string, unknown>,
) {
  const response = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  let payload: any = {};
  try {
    payload = await response.json();
  } catch (_) {}
  if (!response.ok || payload?.ok !== true) {
    throw new Error(`telegram_${method}_failed`);
  }
  return payload.result;
}

async function connection(admin: any, userId: string): Promise<any | null> {
  const { data, error } = await admin.rpc("get_telegram_connection_for_service", {
    p_user_id: userId,
  });
  if (error) throw error;
  return Array.isArray(data) && data.length > 0 ? data[0] : null;
}

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
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
  if (authError || !authData.user) {
    return json({ error: "authentication_required" }, 401);
  }

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "invalid_json" }, 400);
  }

  const action = String(body.action ?? "status").trim();
  const userId = authData.user.id;

  try {
    const botToken = await loadBotToken(admin);
    const current = await connection(admin, userId);

    if (action === "status") {
      return json({
        ok: true,
        service_configured: Boolean(botToken),
        connected: Boolean(current?.chat_id),
        telegram_username: current?.telegram_username || null,
        chat_hint: current?.chat_id
          ? `••••${String(current.chat_id).slice(-4)}`
          : null,
        connected_at: current?.connected_at || null,
        last_tested_at: current?.last_tested_at || null,
      });
    }

    if (action === "disconnect") {
      const { error } = await admin.rpc("disconnect_telegram_for_service", {
        p_user_id: userId,
      });
      if (error) throw error;
      return json({ ok: true, connected: false });
    }

    if (!botToken) {
      return json({ error: "telegram_service_not_configured" }, 503);
    }

    if (action === "create_link") {
      const me = await telegramApi(botToken, "getMe", {});
      const username = String(me?.username ?? "").trim();
      if (!username) {
        return json({ error: "telegram_bot_username_missing" }, 503);
      }

      const random = new Uint8Array(24);
      crypto.getRandomValues(random);
      const code = base64Url(random);
      const codeHash = await sha256Hex(code);
      const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

      const { error: codeError } = await admin.rpc(
        "create_telegram_link_code_service",
        {
          p_user_id: userId,
          p_code_hash: codeHash,
          p_expires_at: expiresAt,
        },
      );
      if (codeError) throw codeError;

      const webhookSecret = await sha256Hex(botToken);
      const webhookUrl = `${supabaseUrl}/functions/v1/telegram-webhook`;
      await telegramApi(botToken, "setWebhook", {
        url: webhookUrl,
        secret_token: webhookSecret,
        allowed_updates: ["message"],
        drop_pending_updates: false,
      });

      return json({
        ok: true,
        connect_url: `https://t.me/${username}?start=zhirox_${code}`,
        bot_username: `@${username}`,
        expires_at: expiresAt,
      });
    }

    if (action === "test") {
      if (!current?.chat_id) {
        return json({ error: "telegram_not_connected" }, 409);
      }
      await telegramApi(botToken, "sendMessage", {
        chat_id: String(current.chat_id),
        text:
          "✅ تاقیکردنەوەی ZHIROX سەرکەوتوو بوو. ئاگادارکردنەوەکانی Telegram بە شێوەی پارێزراو چالاکن.",
        disable_web_page_preview: true,
      });
      const { error } = await admin.rpc("mark_telegram_tested_service", {
        p_user_id: userId,
      });
      if (error) throw error;
      return json({
        ok: true,
        delivered: true,
        tested_at: new Date().toISOString(),
      });
    }

    return json({ error: "unsupported_action" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(
      "telegram-integration error",
      message.replace(/bot\d+:[^/\s]+/g, "bot[redacted]"),
    );
    if (message.startsWith("telegram_")) {
      return json({ error: message }, 502);
    }
    return json({ error: "request_failed" }, 500);
  }
}

Deno.serve(handle);
