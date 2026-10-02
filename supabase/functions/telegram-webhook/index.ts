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
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function loadBotToken(admin: any): Promise<string> {
  const direct = env("TELEGRAM_BOT_TOKEN");
  if (direct) return direct;
  const { data, error } = await admin.rpc("get_telegram_runtime_config_service");
  if (error) return "";
  const row = Array.isArray(data) ? data[0] : data;
  return String(row?.bot_token ?? "").trim();
}

const menuKeyboard = {
  keyboard: [
    [{ text: "💰 قەرزی ماوە" }, { text: "🧾 کۆتا پارەدان" }],
    [{ text: "📋 کەشف حساب" }, { text: "🌐 هەژماری من" }],
    [{ text: "📄 PDF کەشف حساب" }, { text: "🧾 PDF پسووڵە" }],
    [{ text: "📚 کەشفی تەواو PDF" }],
  ],
  resize_keyboard: true,
  is_persistent: true,
};

const ownerMenuKeyboard = {
  keyboard: [
    [{ text: "💬 Ask ZHIROX" }],
    [{ text: "🧠 Executive Brief" }, { text: "📥 Decision Inbox" }],
    [{ text: "🔄 چی گۆڕاوە؟" }, { text: "📊 دۆخی AutoPilot" }],
    [{ text: "🕒 Daily Digest" }],
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
  try {
    payload = await response.json();
  } catch (_) {}
  if (!response.ok || payload?.ok !== true) {
    throw new Error(`telegram_${method}_failed`);
  }
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

async function sendOwnerMessage(token: string, chatId: string, text: string) {
  try {
    await telegramApi(token, "sendMessage", {
      chat_id: chatId,
      text,
      disable_web_page_preview: true,
      reply_markup: ownerMenuKeyboard,
    });
  } catch (_) {}
}

function asInt(value: unknown): number {
  const number = Number(value ?? 0);
  return Number.isFinite(number) ? Math.trunc(number) : 0;
}

function signed(value: unknown): string {
  const number = asInt(value);
  return number > 0 ? `+${number}` : String(number);
}

function formatIqd(value: unknown): string {
  const n = Number(value ?? 0);
  return `${Math.round(Number.isFinite(n) ? n : 0).toLocaleString("en-US")} د.ع`;
}

function formatDate(value: unknown): string {
  const d = new Date(String(value ?? ""));
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
  const { data, error } = await admin.rpc("get_telegram_customer_snapshot_service", {
    p_chat_id: chatId,
  });
  if (error) throw error;
  return data && typeof data === "object" ? data : null;
}

async function ownerByChat(admin: any, chatId: string): Promise<string | null> {
  const { data, error } = await admin.rpc("get_telegram_system_owner_by_chat_service", {
    p_chat_id: chatId,
  });
  if (error) return null;
  return data ? String(data) : null;
}

async function auditOwnerCommand(
  admin: any,
  ownerId: string,
  command: string,
  result = "ok",
  context: Record<string, unknown> = {},
) {
  try {
    await admin.rpc("log_owner_telegram_os_command_service", {
      p_owner_user_id: ownerId,
      p_command: command,
      p_result: result,
      p_context: context,
    });
  } catch (_) {}
}

function deltaLines(delta: any): string[] {
  const fields: Array<[string, string]> = [
    ["attention", "Attention"],
    ["degraded", "Degraded"],
    ["active_queue", "Queue"],
    ["retrying", "Retry"],
    ["dead_letter", "Dead-letter"],
    ["risk_high", "High Risk"],
    ["risk_critical", "Critical Risk"],
    ["telegram_linked_customers", "Telegram linked"],
  ];
  const lines: string[] = [];
  for (const [key, label] of fields) {
    const value = asInt(delta?.[key]);
    if (value !== 0) lines.push(`• ${label}: ${signed(value)}`);
  }
  return lines;
}

async function ownerOverviewText(admin: any): Promise<string> {
  const { data, error } = await admin.rpc("get_system_owner_autopilot_overview_service", {
    p_search: "",
    p_health: "all",
    p_page: 1,
    p_per_page: 100,
  });
  if (error) throw error;
  const o = data?.overview ?? {};
  const items = Array.isArray(data?.items) ? data.items : [];
  const bad = items
    .filter((x: any) => String(x?.health?.status ?? "") !== "healthy")
    .slice(0, 5);
  const lines = [
    "📊 ZHIROX • AutoPilot Status",
    "",
    `🏪 مارکێت: ${asInt(o.total_markets)} • Healthy ${asInt(o.healthy)} • Degraded ${asInt(o.degraded)} • Attention ${asInt(o.attention)}`,
    `⚙️ Queue ${asInt(o.active_queue)} • Retry ${asInt(o.retrying)} • Dead-letter ${asInt(o.dead_letter)}`,
    `🤖 AutoPilot ON ${asInt(o.autopilot_enabled)} • OFF ${asInt(o.autopilot_disabled)}`,
    `📨 Telegram linked ${asInt(o.telegram_linked_customers)}`,
    `🛡️ Risk ${asInt(o.risk_total)} • High ${asInt(o.risk_high)} • Critical ${asInt(o.risk_critical)}`,
  ];
  if (bad.length) {
    lines.push("", "⚠️ پێویستی بە سەرنج:");
    for (const market of bad) {
      lines.push(`• ${String(market?.market_name ?? "مارکێت")} — ${String(market?.health?.status ?? "attention")}`);
    }
  } else {
    lines.push("", "✅ هیچ مارکێتێکی کێشەدار نییە.");
  }
  return lines.join("\n");
}

async function ownerExecutiveBriefText(admin: any, ownerId: string): Promise<string> {
  const { data, error } = await admin.rpc("get_owner_executive_brief_service", {
    p_owner_user_id: ownerId,
  });
  if (error) throw error;
  const current = data?.current ?? {};
  const delta = data?.delta_24h ?? {};
  const decisions = data?.decisions ?? {};
  const markets = Array.isArray(data?.markets) ? data.markets : [];
  const problemMarkets = markets
    .filter((m: any) => String(m?.health?.status ?? "healthy") !== "healthy")
    .slice(0, 3);
  const changes = deltaLines(delta);
  const lines = [
    "🧠 ZHIROX • Executive Brief",
    `🕒 ${formatDate(data?.generated_at)}`,
    "",
    `🏪 ${asInt(current.total_markets)} مارکێت • Healthy ${asInt(current.healthy)} • Degraded ${asInt(current.degraded)} • Attention ${asInt(current.attention)}`,
    `⚙️ Queue ${asInt(current.active_queue)} • Retry ${asInt(current.retrying)} • Dead-letter ${asInt(current.dead_letter)}`,
    `🛡️ Risk ${asInt(current.risk_total)} • High ${asInt(current.risk_high)} • Critical ${asInt(current.risk_critical)}`,
    `📨 Telegram linked ${asInt(current.telegram_linked_customers)}`,
    `📥 Decision Inbox ${asInt(decisions.total)} • Critical ${asInt(decisions.critical)} • Warning ${asInt(decisions.warning)}`,
  ];
  if (problemMarkets.length) {
    lines.push("", "⚠️ مارکێتە پێویست بە سەرنجەکان:");
    for (const market of problemMarkets) {
      lines.push(`• ${String(market?.market_name ?? "مارکێت")} — ${String(market?.health?.status ?? "attention")}`);
    }
  } else {
    lines.push("", "✅ دۆخی هەموو مارکێتەکان سالمە.");
  }
  if (changes.length) {
    lines.push("", `🔄 گۆڕان لە ${formatDate(delta?.reference_at)}:`, ...changes);
  } else {
    lines.push("", "🔄 هیچ گۆڕانکارییەکی گرنگ لە baseline ـی بەردەست نییە.");
  }
  if (asInt(decisions.total) === 0) {
    lines.push("", "✅ ئێستا هیچ بڕیارێکی فوری لە Owner پێویست نییە.");
  }
  return lines.join("\n");
}

async function ownerDecisionInboxText(admin: any, ownerId: string): Promise<string> {
  const { data, error } = await admin.rpc("get_owner_decision_inbox_service", {
    p_owner_user_id: ownerId,
    p_limit: 10,
  });
  if (error) throw error;
  const items = Array.isArray(data?.items) ? data.items : [];
  if (!items.length) {
    return "📥 ZHIROX • Decision Inbox\n\n✅ ئێستا هیچ بڕیارێکی چالاک پێویست نییە.";
  }
  const lines = [
    "📥 ZHIROX • Decision Inbox",
    `Critical ${asInt(data?.critical)} • Warning ${asInt(data?.warning)} • Total ${asInt(data?.total)}`,
    "",
  ];
  for (const [index, item] of items.entries()) {
    const severity = String(item?.severity ?? "info");
    const icon = severity === "critical" ? "🔴" : severity === "warning" ? "🟠" : "🔵";
    lines.push(`${index + 1}. ${icon} ${String(item?.title ?? "Decision").slice(0, 160)}`);
    const body = String(item?.body ?? "").trim();
    if (body) lines.push(`   ${body.slice(0, 220)}`);
    lines.push(`   🕒 ${formatDate(item?.last_seen_at)}`);
  }
  lines.push("", "ℹ️ ئەم قۆناغە read-only ـە؛ هیچ گۆڕانکارییەکی دارایی خۆکار ناکرێت.");
  return lines.join("\n");
}

async function ownerChangesText(admin: any, ownerId: string): Promise<string> {
  const { data, error } = await admin.rpc("get_owner_changes_since_last_check_service", {
    p_owner_user_id: ownerId,
    p_mark_seen: true,
  });
  if (error) throw error;
  const changes = deltaLines(data?.delta ?? {});
  const notifications = Array.isArray(data?.notifications) ? data.notifications : [];
  const lines = [
    "🔄 ZHIROX • چی گۆڕاوە؟",
    `لە ${formatDate(data?.since)} تا ${formatDate(data?.generated_at)}`,
  ];
  if (!changes.length && !notifications.length) {
    lines.push("", "✅ هیچ گۆڕانکارییەکی گرنگ یان alert ـی نوێ تۆمار نەکراوە.");
    return lines.join("\n");
  }
  if (changes.length) lines.push("", "📊 گۆڕانی دۆخ:", ...changes);
  if (notifications.length) {
    lines.push("", `🔔 Alert/Event نوێ: ${asInt(data?.notification_count)}`);
    for (const event of notifications.slice(0, 5)) {
      lines.push(`• ${String(event?.title ?? event?.event_type ?? "Event").slice(0, 170)} — ${formatDate(event?.created_at)}`);
    }
  }
  return lines.join("\n");
}

async function ownerAsk(admin: any, ownerId: string, question: string): Promise<any> {
  const { data, error } = await admin.rpc("ask_owner_telegram_os_service", {
    p_owner_user_id: ownerId,
    p_text: question,
  });
  if (error) throw error;
  return data && typeof data === "object" ? data : {};
}

function statementText(data: any): string {
  const rows = Array.isArray(data?.recent) ? data.recent : [];
  if (!rows.length) {
    return `📋 کەشف حساب\n\nهیچ مامەڵەیەک تۆمار نەکراوە.\n\nقەرزی ماوە: ${formatIqd(data?.remaining_iqd)}`;
  }
  const lines = rows.map((r: any, index: number) => {
    const kind = String(r?.kind ?? "") === "payment" ? "✅ پارەدان" : "🧾 قەرز";
    const note = String(r?.note ?? "").trim();
    return `${index + 1}. ${kind} • ${formatIqd(r?.amount)}\n   ${formatDate(r?.occurred_at)}${note ? ` • ${note.slice(0, 80)}` : ""}`;
  });
  return `📋 10 مامەڵەی کۆتایی\n\n${lines.join("\n\n")}\n\n💰 قەرزی ماوە: ${formatIqd(data?.remaining_iqd)}`;
}

async function requestPdf(
  supabaseUrl: string,
  botToken: string,
  chatId: string,
  action: "statement" | "receipt",
) {
  const internal = await sha256Hex(`${botToken}:customer-pdf`);
  const response = await fetch(`${supabaseUrl}/functions/v1/telegram-customer-pdf`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-zhirox-telegram-internal": internal,
    },
    body: JSON.stringify({ chat_id: chatId, action }),
    signal: AbortSignal.timeout(30000),
  });
  let body: any = {};
  try {
    body = await response.json();
  } catch (_) {}
  if (!response.ok) throw new Error("pdf_failed");
  return body;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("ok", { status: 200 });

  const supabaseUrl = env("SUPABASE_URL");
  const secret = serviceKey();
  if (!supabaseUrl || !secret) return new Response("unavailable", { status: 503 });

  const admin = createClient(supabaseUrl, secret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const botToken = await loadBotToken(admin);
  if (!botToken) return new Response("unavailable", { status: 503 });

  const expectedSecret = await sha256Hex(botToken);
  const providedSecret = req.headers.get("X-Telegram-Bot-Api-Secret-Token") ?? "";
  if (!providedSecret || !(await secureEqual(providedSecret, expectedSecret))) {
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

  const startMatch = text.match(/^\/start(?:@\w+)?(?:\s+zhirox_([A-Za-z0-9_-]{20,100}))?$/);
  if (startMatch) {
    const code = startMatch[1] ?? "";
    if (!code) {
      const owner = await ownerByChat(admin, chatId);
      if (owner) {
        await sendOwnerMessage(
          botToken,
          chatId,
          "✅ Telegramی System Owner پەیوەستە.\n🧠 ZHIROX Telegram OS + Ask ZHIROX چالاکە.\nDaily Digest هەر ڕۆژ 08:30 بە کاتی عێراق دەنێردرێت.",
        );
        return new Response("ok", { status: 200 });
      }
      try {
        const current = await snapshot(admin, chatId);
        if (current) {
          await sendMessage(
            botToken,
            chatId,
            `بەخێربێیت بۆ ZHIROX • ${String(current.market_name ?? "ZHIROX")}\nدوگمەی خوارەوە هەڵبژێرە.`,
            true,
          );
        } else {
          await sendMessage(
            botToken,
            chatId,
            "بۆ پەیوەستکردنی Telegram، لە ناو ZHIROX → Telegram → «پەیوەستکردن» کلیک بکە.",
          );
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
      await sendMessage(
        botToken,
        chatId,
        "❌ لینکی پەیوەستکردن بەسەرچووە یان دروست نییە. تکایە لە ZHIROX لینکێکی نوێ دروست بکە.",
      );
      return new Response("ok", { status: 200 });
    }
    const { data: linkedProfile } = await admin
      .from("profiles")
      .select("is_system_owner")
      .eq("id", data)
      .maybeSingle();
    if (linkedProfile?.is_system_owner === true) {
      await sendOwnerMessage(
        botToken,
        chatId,
        "✅ Telegramی System Owner بە سەرکەوتوویی پەیوەست کرا.\n💬 Ask ZHIROX، Executive Brief، Decision Inbox و Changes چالاکن.\nDaily Owner Digest هەر ڕۆژ 08:30 بە کاتی عێراق دەنێردرێت.",
      );
    } else {
      await sendMessage(
        botToken,
        chatId,
        "✅ Telegram بە سەرکەوتوویی پەیوەست کرا.\nئێستا دەتوانیت بە دوگمەکانی خوارەوە زانیاری هەژمارەکەت ببینیت.",
        true,
      );
    }
    return new Response("ok", { status: 200 });
  }

  const owner = await ownerByChat(admin, chatId);
  if (owner) {
    if (text === "/menu" || text === "menu") {
      await auditOwnerCommand(admin, owner, "menu");
      await sendOwnerMessage(
        botToken,
        chatId,
        "🧠 ZHIROX Telegram OS\n\n💬 دەتوانیت بە زمانی ئاسایی بپرسیت، یان یەکێک لە دوگمەکان هەڵبژێریت.",
      );
      return new Response("ok", { status: 200 });
    }

    if (text === "🧠 Executive Brief" || /^\/brief(?:@\w+)?$/.test(text)) {
      try {
        const output = await ownerExecutiveBriefText(admin, owner);
        await auditOwnerCommand(admin, owner, "brief", "ok");
        await sendOwnerMessage(botToken, chatId, output);
      } catch (_) {
        await auditOwnerCommand(admin, owner, "brief", "failed");
        await sendOwnerMessage(botToken, chatId, "❌ نەتوانرا Executive Brief بخوێندرێتەوە.");
      }
      return new Response("ok", { status: 200 });
    }

    if (text === "📥 Decision Inbox" || /^\/decisions(?:@\w+)?$/.test(text)) {
      try {
        const output = await ownerDecisionInboxText(admin, owner);
        await auditOwnerCommand(admin, owner, "decisions", "ok");
        await sendOwnerMessage(botToken, chatId, output);
      } catch (_) {
        await auditOwnerCommand(admin, owner, "decisions", "failed");
        await sendOwnerMessage(botToken, chatId, "❌ نەتوانرا Decision Inbox بخوێندرێتەوە.");
      }
      return new Response("ok", { status: 200 });
    }

    if (text === "🔄 چی گۆڕاوە؟" || /^\/changes(?:@\w+)?$/.test(text)) {
      try {
        const output = await ownerChangesText(admin, owner);
        await auditOwnerCommand(admin, owner, "changes", "ok");
        await sendOwnerMessage(botToken, chatId, output);
      } catch (_) {
        await auditOwnerCommand(admin, owner, "changes", "failed");
        await sendOwnerMessage(botToken, chatId, "❌ نەتوانرا گۆڕانکارییە نوێکان بخوێندرێنەوە.");
      }
      return new Response("ok", { status: 200 });
    }

    if (
      text === "📊 دۆخی AutoPilot" ||
      /^\/health(?:@\w+)?$/.test(text) ||
      /^\/digest(?:@\w+)?$/.test(text)
    ) {
      try {
        const output = await ownerOverviewText(admin);
        await auditOwnerCommand(admin, owner, "health", "ok");
        await sendOwnerMessage(botToken, chatId, output);
      } catch (_) {
        await auditOwnerCommand(admin, owner, "health", "failed");
        await sendOwnerMessage(botToken, chatId, "❌ نەتوانرا دۆخی AutoPilot بخوێندرێتەوە.");
      }
      return new Response("ok", { status: 200 });
    }

    if (text === "🕒 Daily Digest") {
      await auditOwnerCommand(admin, owner, "daily_digest_info", "ok");
      await sendOwnerMessage(
        botToken,
        chatId,
        "🕒 Daily Owner Digest\n\nهەر ڕۆژ 08:30 بە کاتی عێراق دەنێردرێت.\nئەگەر failure بێت هەر 15 خولەک retry دەکرێت تا سەرکەوتن، و لە هەر ڕۆژێک تەنها یەکجار دەنێردرێت.",
      );
      return new Response("ok", { status: 200 });
    }

    if (text.startsWith("/") && text !== "/ask") {
      await auditOwnerCommand(admin, owner, "unknown_slash", "ignored", { text: text.slice(0, 80) });
      await sendOwnerMessage(
        botToken,
        chatId,
        "💬 Ask ZHIROX\n\nبە زمانی ئاسایی بپرسە، یان: /brief • /decisions • /changes • /health",
      );
      return new Response("ok", { status: 200 });
    }

    try {
      const question = text === "💬 Ask ZHIROX" || text === "/ask"
        ? "help"
        : text.slice(0, 500);
      const result = await ownerAsk(admin, owner, question);
      const intent = String(result?.intent ?? "help").slice(0, 64);
      const confidence = String(result?.confidence ?? "unknown").slice(0, 32);
      const output = String(result?.message ?? "").trim() ||
        "💬 Ask ZHIROX\n\nنەتوانرا وەڵامێکی ڕوون دروست بکرێت.";
      await auditOwnerCommand(admin, owner, `ask:${intent}`, "ok", {
        confidence,
        question: question.slice(0, 180),
      });
      await sendOwnerMessage(botToken, chatId, output);
    } catch (_) {
      await auditOwnerCommand(admin, owner, "ask", "failed", { question: text.slice(0, 180) });
      await sendOwnerMessage(
        botToken,
        chatId,
        "❌ Ask ZHIROX لەم ساتەدا نەتوانی وەڵام بدات. فرمانە بنەڕەتییەکان هەر کار دەکەن.",
      );
    }
    return new Response("ok", { status: 200 });
  }

  let current: any = null;
  try {
    current = await snapshot(admin, chatId);
  } catch (_) {}
  if (!current) {
    await sendMessage(
      botToken,
      chatId,
      "🔒 ئەم Telegram ـە بە هەژماری ZHIROX پەیوەست نییە. سەرەتا لە ZHIROX → Telegram پەیوەستی بکە.",
    );
    return new Response("ok", { status: 200 });
  }

  if (text === "/menu" || text === "menu" || text === "🏠 لیستی سەرەکی") {
    await sendMessage(botToken, chatId, "خزمەتگوزارییەک هەڵبژێرە:", true);
    return new Response("ok", { status: 200 });
  }

  if (text === "💰 قەرزی ماوە" || /^\/balance(?:@\w+)?$/.test(text)) {
    await sendMessage(
      botToken,
      chatId,
      `💰 قەرزی ماوە\n\n${formatIqd(current.remaining_iqd)}\n\n🏪 ${String(current.market_name ?? "ZHIROX")}\n🕒 ${formatDate(current.as_of)}`,
      true,
    );
    return new Response("ok", { status: 200 });
  }

  if (text === "🧾 کۆتا پارەدان" || /^\/lastpayment(?:@\w+)?$/.test(text)) {
    const payment = current.last_payment;
    const msg = payment
      ? `🧾 کۆتا پارەدان\n\nبڕ: ${formatIqd(payment.amount)}\nکات: ${formatDate(payment.created_at)}${String(payment.note ?? "").trim() ? `\nتێبینی: ${String(payment.note).trim().slice(0, 160)}` : ""}`
      : "🧾 کۆتا پارەدان\n\nهێشتا هیچ پارەدانێک تۆمار نەکراوە.";
    await sendMessage(botToken, chatId, msg, true);
    return new Response("ok", { status: 200 });
  }

  if (text === "📋 کەشف حساب" || /^\/statement(?:@\w+)?$/.test(text)) {
    await sendMessage(botToken, chatId, statementText(current), true);
    return new Response("ok", { status: 200 });
  }

  if (text === "📄 PDF کەشف حساب" || /^\/statementpdf(?:@\w+)?$/.test(text)) {
    await sendMessage(botToken, chatId, "📄 کەشف حسابی PDF دروست دەکرێت…", false);
    try {
      await requestPdf(supabaseUrl, botToken, chatId, "statement");
    } catch (_) {
      await sendMessage(botToken, chatId, "❌ نەتوانرا PDF دروست بکرێت. دووبارە هەوڵ بدەوە.", true);
    }
    return new Response("ok", { status: 200 });
  }

  if (text === "🧾 PDF پسووڵە" || /^\/receiptpdf(?:@\w+)?$/.test(text)) {
    await sendMessage(botToken, chatId, "🧾 پسووڵەی PDF دروست دەکرێت…", false);
    try {
      const result = await requestPdf(supabaseUrl, botToken, chatId, "receipt");
      if (result?.sent === false && result?.reason === "no_transactions") {
        await sendMessage(botToken, chatId, "هێشتا هیچ مامەڵەیەک نییە بۆ دروستکردنی پسووڵە.", true);
      }
    } catch (_) {
      await sendMessage(botToken, chatId, "❌ نەتوانرا پسووڵەی PDF دروست بکرێت. دووبارە هەوڵ بدەوە.", true);
    }
    return new Response("ok", { status: 200 });
  }

  if (text === "📚 کەشفی تەواو PDF" || /^\/fullstatementpdf(?:@\w+)?$/.test(text)) {
    const { data, error } = await admin.rpc("enqueue_telegram_full_statement_service", {
      p_chat_id: chatId,
    });
    if (error || !data) {
      await sendMessage(
        botToken,
        chatId,
        "❌ نەتوانرا کەشف حسابی تەواو دەستپێبکرێت. دووبارە هەوڵ بدەوە.",
        true,
      );
    } else {
      const total = Number(data.total_rows ?? 0);
      const parts = Number(data.total_parts ?? 1);
      const existing = Boolean(data.existing);
      await sendMessage(
        botToken,
        chatId,
        existing
          ? `📚 کەشف حسابی تەواو پێشتر لە ڕیزدایە.\n${total.toLocaleString("en-US")} مامەڵە • ${parts} بەشی PDF`
          : `📚 دروستکردنی کەشف حسابی تەواو دەستی پێکرد.\n${total.toLocaleString("en-US")} مامەڵە • ${parts} بەشی PDF\nبەشەکان خۆکار یەک بە یەک دەنێردرێن.`,
        true,
      );
    }
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
      await sendMessage(
        botToken,
        chatId,
        `🌐 هەژماری ZHIROX ـت\n\nلینکەکە 10 خولەک کار دەکات:\nhttps://push.zhirox.com/?token=${rawToken}`,
        true,
      );
    }
    return new Response("ok", { status: 200 });
  }

  await sendMessage(botToken, chatId, "فرمانەکە نەناسرا. یەکێک لە دوگمەکان هەڵبژێرە.", true);
  return new Response("ok", { status: 200 });
});