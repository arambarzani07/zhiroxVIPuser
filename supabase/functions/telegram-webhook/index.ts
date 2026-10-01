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

async function secureEqual(left: string, right: string): Promise<boolean> {
  const enc = new TextEncoder();
  const [aHash, bHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(left)),
    crypto.subtle.digest("SHA-256", enc.encode(right)),
  ]);
  const a = new Uint8Array(aHash);
  const b = new Uint8Array(bHash);
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

function randomHex(byteLength = 32): string {
  return Array.from(crypto.getRandomValues(new Uint8Array(byteLength)))
    .map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function loadBotToken(admin: any): Promise<string> {
  const fromEnv = env("TELEGRAM_BOT_TOKEN");
  if (fromEnv) return fromEnv;
  const { data, error } = await admin.rpc("get_telegram_runtime_config_service");
  if (error) return "";
  const row = Array.isArray(data) ? data[0] : data;
  return String(row?.bot_token ?? "").trim();
}

const menuKeyboard = {
  keyboard: [
    [{ text: "💰 قەرزی ماوە" }, { text: "🧾 کۆتا پارەدان" }],
    [{ text: "📋 کەشف حساب" }, { text: "🌐 هەژماری من" }],
  ],
  resize_keyboard: true,
  is_persistent: true,
};

async function telegramApi(token: string, method: string, body: Record<string, unknown>) {
  const response = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(8000),
  });
  let payload: any = {};
  try { payload = await response.json(); } catch (_) {}
  if (!response.ok || payload?.ok !== true) throw new Error(`telegram_${method}_failed`);
  return payload.result;
}

async function sendMessage(token: string, chatId: string, text: string, withMenu = false) {
  try {
    await telegramApi(token, "sendMessage", {
      chat_id: chatId,
      text,
      disable_web_page_preview: true,
      ...(withMenu ? { reply_markup: menuKeyboard } : {}),
    });
  } catch (_) {}
}

function formatIqd(value: unknown): string {
  const n = Number(value ?? 0);
  return `${Math.round(Number.isFinite(n) ? n : 0).toLocaleString("en-US")} د.ع`;
}

function formatDate(value: unknown): string {
  const raw = String(value ?? "");
  const d = new Date(raw);
  if (!Number.isFinite(d.getTime())) return "—";
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: "Asia/Baghdad",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(d);
}

async function snapshot(admin: any, chatId: string): Promise<any | null> {
  const { data, error } = await admin.rpc("get_telegram_customer_snapshot_service", { p_chat_id: chatId });
  if (error) throw error;
  return data && typeof data === "object" ? data : null;
}

function statementText(data: any): string {
  const rows = Array.isArray(data?.recent) ? data.recent : [];
  if (!rows.length) return `📋 کەشف حساب\n\nهیچ مامەڵەیەک تۆمار نەکراوە.\n\nقەرزی ماوە: ${formatIqd(data?.remaining_iqd)}`;
  const lines = rows.map((r: any, index: number) => {
    const kind = String(r?.kind ?? "") === "payment" ? "✅ پارەدان" : "🧾 قەرز";
    const note = String(r?.note ?? "").trim();
    return `${index + 1}. ${kind} • ${formatIqd(r?.amount)}\n   ${formatDate(r?.occurred_at)}${note ? ` • ${note.slice(0, 80)}` : ""}`;
  });
  return `📋 10 مامەڵەی کۆتایی\n\n${lines.join("\n\n")}\n\n💰 قەرزی ماوە: ${formatIqd(data?.remaining_iqd)}`;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("ok", { status: 200 });

  const supabaseUrl = env("SUPABASE_URL");
  const secret = serviceKey();
  if (!supabaseUrl || !secret) return new Response("unavailable", { status: 503 });

  const admin = createClient(supabaseUrl, secret, { auth: { persistSession: false, autoRefreshToken: false } });
  const botToken = await loadBotToken(admin);
  if (!botToken) return new Response("unavailable", { status: 503 });

  const expectedSecret = await sha256Hex(botToken);
  const providedSecret = req.headers.get("X-Telegram-Bot-Api-Secret-Token") ?? "";
  if (!providedSecret || !(await secureEqual(providedSecret, expectedSecret))) {
    return new Response("forbidden", { status: 403 });
  }

  let update: any;
  try { update = await req.json(); } catch (_) { return new Response("ok", { status: 200 }); }

  const message = update?.message;
  const chatId = message?.chat?.id != null ? String(message.chat.id) : "";
  const text = String(message?.text ?? "").trim();
  if (!chatId || !text) return new Response("ok", { status: 200 });

  const startMatch = text.match(/^\/start(?:@\w+)?(?:\s+zhirox_([A-Za-z0-9_-]{20,100}))?$/);
  if (startMatch) {
    const code = startMatch[1] ?? "";
    if (!code) {
      try {
        const current = await snapshot(admin, chatId);
        if (current) {
          await sendMessage(botToken, chatId, `بەخێربێیت بۆ ZHIROX • ${String(current.market_name ?? "ZHIROX")}\nدوگمەی خوارەوە هەڵبژێرە.`, true);
        } else {
          await sendMessage(botToken, chatId, "بۆ پەیوەستکردنی Telegram، لە ناو ZHIROX → Telegram → «پەیوەستکردن» کلیک بکە.");
        }
      } catch (_) {}
      return new Response("ok", { status: 200 });
    }

    const codeHash = await sha256Hex(code);
    const telegramUserId = message?.from?.id != null ? String(message.from.id) : null;
    const username = String(message?.from?.username ?? "").trim().slice(0, 64);
    const { data, error } = await admin.rpc("consume_telegram_link_code_service", {
      p_code_hash: codeHash,
      p_chat_id: chatId,
      p_telegram_user_id: telegramUserId,
      p_telegram_username: username || null,
    });
    if (error || !data) {
      await sendMessage(botToken, chatId, "❌ لینکی پەیوەستکردن بەسەرچووە یان دروست نییە. تکایە لە ZHIROX لینکێکی نوێ دروست بکە.");
      return new Response("ok", { status: 200 });
    }
    await sendMessage(botToken, chatId, "✅ Telegram بە سەرکەوتوویی پەیوەست کرا.\nئێستا دەتوانیت بە دوگمەکانی خوارەوە زانیاری هەژمارەکەت ببینیت.", true);
    return new Response("ok", { status: 200 });
  }

  let current: any = null;
  try { current = await snapshot(admin, chatId); } catch (_) {}
  if (!current) {
    await sendMessage(botToken, chatId, "🔒 ئەم Telegram ـە بە هەژماری ZHIROX پەیوەست نییە. سەرەتا لە ZHIROX → Telegram پەیوەستی بکە.");
    return new Response("ok", { status: 200 });
  }

  if (text === "/menu" || text === "menu" || text === "🏠 لیستی سەرەکی") {
    await sendMessage(botToken, chatId, "خزمەتگوزارییەک هەڵبژێرە:", true);
    return new Response("ok", { status: 200 });
  }

  if (text === "💰 قەرزی ماوە" || /^\/balance(?:@\w+)?$/.test(text)) {
    await sendMessage(botToken, chatId, `💰 قەرزی ماوە\n\n${formatIqd(current.remaining_iqd)}\n\n🏪 ${String(current.market_name ?? "ZHIROX")}\n🕒 ${formatDate(current.as_of)}`, true);
    return new Response("ok", { status: 200 });
  }

  if (text === "🧾 کۆتا پارەدان" || /^\/lastpayment(?:@\w+)?$/.test(text)) {
    const p = current.last_payment;
    const msg = p
      ? `🧾 کۆتا پارەدان\n\nبڕ: ${formatIqd(p.amount)}\nکات: ${formatDate(p.created_at)}${String(p.note ?? "").trim() ? `\nتێبینی: ${String(p.note).trim().slice(0, 160)}` : ""}`
      : "🧾 کۆتا پارەدان\n\nهێشتا هیچ پارەدانێک تۆمار نەکراوە.";
    await sendMessage(botToken, chatId, msg, true);
    return new Response("ok", { status: 200 });
  }

  if (text === "📋 کەشف حساب" || /^\/statement(?:@\w+)?$/.test(text)) {
    await sendMessage(botToken, chatId, statementText(current), true);
    return new Response("ok", { status: 200 });
  }

  if (text === "🌐 هەژماری من" || /^\/account(?:@\w+)?$/.test(text)) {
    const rawToken = randomHex(32);
    const tokenHash = await sha256Hex(rawToken);
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
    const { error } = await admin.rpc("create_telegram_customer_read_link_service", {
      p_chat_id: chatId,
      p_token_hash: tokenHash,
      p_expires_at: expiresAt,
    });
    if (error) {
      await sendMessage(botToken, chatId, "❌ نەتوانرا لینکی پارێزراو دروست بکرێت. دووبارە هەوڵ بدەوە.", true);
    } else {
      await sendMessage(botToken, chatId, `🌐 هەژماری ZHIROX ـت\n\nلینکەکە 10 خولەک کار دەکات:\nhttps://push.zhirox.com/?token=${rawToken}`, true);
    }
    return new Response("ok", { status: 200 });
  }

  await sendMessage(botToken, chatId, "فرمانەکە نەناسرا. یەکێک لە دوگمەکان هەڵبژێرە.", true);
  return new Response("ok", { status: 200 });
});
