import { createClient } from "npm:@supabase/supabase-js@2.116.0";

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

async function sendMessage(token: string, chatId: string, text: string) {
  try {
    await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: chatId,
        text,
        disable_web_page_preview: true,
      }),
    });
  } catch (_) {}
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("ok", { status: 200 });

  const supabaseUrl = env("SUPABASE_URL");
  const secret = serviceKey();
  if (!supabaseUrl || !secret) {
    return new Response("unavailable", { status: 503 });
  }

  const admin = createClient(supabaseUrl, secret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const botToken = await loadBotToken(admin);
  if (!botToken) return new Response("unavailable", { status: 503 });

  const expectedSecret = await sha256Hex(botToken);
  const providedSecret =
    req.headers.get("X-Telegram-Bot-Api-Secret-Token") ?? "";
  if (!providedSecret || providedSecret !== expectedSecret) {
    return new Response("forbidden", { status: 403 });
  }

  let update: any;
  try {
    update = await req.json();
  } catch (_) {
    return new Response("ok", { status: 200 });
  }

  const message = update?.message;
  const chatId = message?.chat?.id != null ? String(message.chat.id) : "";
  const text = String(message?.text ?? "").trim();
  if (!chatId || !text) return new Response("ok", { status: 200 });

  const startMatch = text.match(
    /^\/start(?:@\w+)?(?:\s+zhirox_([A-Za-z0-9_-]{20,100}))?$/,
  );
  if (!startMatch) return new Response("ok", { status: 200 });

  const code = startMatch[1] ?? "";
  if (!code) {
    await sendMessage(
      botToken,
      chatId,
      "بۆ پەیوەستکردنی Telegram، لە ناو ZHIROX → ئاگادارکردنەوەکان → ڕێکخستنی Telegram کلیک لە «پەیوەستکردن» بکە.",
    );
    return new Response("ok", { status: 200 });
  }

  const codeHash = await sha256Hex(code);
  const telegramUserId =
    message?.from?.id != null ? String(message.from.id) : null;
  const username = String(message?.from?.username ?? "").trim().slice(0, 64);

  const { data, error } = await admin.rpc(
    "consume_telegram_link_code_service",
    {
      p_code_hash: codeHash,
      p_chat_id: chatId,
      p_telegram_user_id: telegramUserId,
      p_telegram_username: username || null,
    },
  );

  if (error || !data) {
    await sendMessage(
      botToken,
      chatId,
      "❌ لینکی پەیوەستکردن بەسەرچووە یان دروست نییە. تکایە لە ZHIROX لینکێکی نوێ دروست بکە.",
    );
    return new Response("ok", { status: 200 });
  }

  await sendMessage(
    botToken,
    chatId,
    "✅ Telegram بە سەرکەوتوویی بە هەژماری ZHIROX ـەکەت پەیوەست کرا. لەمەودوا ئاگادارکردنەوەکان بە شێوەی پارێزراو دەتوانن بگاتە تۆ.",
  );
  return new Response("ok", { status: 200 });
});
