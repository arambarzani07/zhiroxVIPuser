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
  const bytes = new TextEncoder().encode(value);
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
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

function isUuid(value: unknown): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(value ?? ""));
}

async function loadBotToken(admin: any): Promise<string> {
  const direct = env("TELEGRAM_BOT_TOKEN");
  if (direct) return direct;
  const { data, error } = await admin.rpc("get_telegram_runtime_config_service");
  if (error) return "";
  const row = Array.isArray(data) ? data[0] : data;
  return String(row?.bot_token ?? "").trim();
}

const customerMenuKeyboard = {
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
      ...(withMenu ? { reply_markup: customerMenuKeyboard } : {}),
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
  const n = Number(value ?? 0);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
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
  const { data, error } = await admin.rpc("get_telegram_customer_snapshot_service", { p_chat_id: chatId });
  if (error) throw error;
  return data && typeof data === "object" ? data : null;
}

async function ownerByChat(admin: any, chatId: string): Promise<string | null> {
  const { data, error } = await admin.rpc("get_telegram_system_owner_by_chat_service", { p_chat_id: chatId });
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

async function ownerAsk(admin: any, ownerId: string, question: string): Promise<any> {
  const { data, error } = await admin.rpc("ask_owner_telegram_os_service", {
    p_owner_user_id: ownerId,
    p_text: question,
  });
  if (error) throw error;
  return data && typeof data === "object" ? data : {};
}

async function getDecision(admin: any, ownerId: string, decisionId: string): Promise<any | null> {
  if (!isUuid(decisionId)) return null;
  const { data, error } = await admin.rpc("get_owner_decision_by_id_service", {
    p_owner_user_id: ownerId,
    p_decision_id: decisionId,
  });
  if (error) throw error;
  return data && typeof data === "object" ? data : null;
}

function decisionDetailText(item: any): string {
  if (!item) return "📥 Decision\n\nئەم بڕیارە نەدۆزرایەوە.";
  const severity = String(item?.severity ?? "info");
  const icon = severity === "critical" ? "🔴" : severity === "warning" ? "🟠" : "🔵";
  const status = String(item?.status ?? "open");
  return [
    `📥 ${icon} ${String(item?.title ?? "Decision").slice(0, 180)}`,
    "",
    String(item?.body ?? "وردەکاری بەردەست نییە.").slice(0, 1200),
    "",
    `Status: ${status} • Severity: ${severity}`,
    `🕒 ${formatDate(item?.last_seen_at)}`,
    "",
    "🔒 Acknowledge تەنها دۆخی بڕیارەکە دەگۆڕێت؛ هیچ financial action ـێک ناکات.",
  ].join("\n");
}

function decisionRecommendationText(item: any): string {
  const actions = Array.isArray(item?.recommended_actions) ? item.recommended_actions : [];
  const lines = [
    `💡 Recommendations • ${String(item?.title ?? "Decision").slice(0, 160)}`,
    "",
  ];
  if (!actions.length) {
    lines.push("• هیچ هەنگاوی تایبەت تۆمار نەکراوە؛ evidence ـەکە بپشکنە.");
  } else {
    actions.slice(0, 5).forEach((a: any, i: number) => {
      const value = typeof a === "string" ? a : String(a?.label ?? a?.title ?? a?.action ?? JSON.stringify(a));
      lines.push(`${i + 1}. ${value.slice(0, 400)}`);
    });
  }
  lines.push("", "🔒 ئەمانە پێشنیارن؛ هیچ action ـێک خۆکار جێبەجێ ناکرێت.");
  return lines.join("\n");
}

async function issueOwnerActionButton(
  admin: any,
  botToken: string,
  ownerId: string,
  label: string,
  action: string,
  entityType: string | null,
  entityId: string | null,
  payload: Record<string, unknown>,
): Promise<any | null> {
  const raw = randomHex(12);
  const tokenHash = await sha256Hex(raw);
  const { error } = await admin.rpc("create_owner_telegram_action_token_service", {
    p_owner_user_id: ownerId,
    p_token_hash: tokenHash,
    p_action: action,
    p_entity_type: entityType,
    p_entity_id: entityId && isUuid(entityId) ? entityId : null,
    p_payload: payload,
    p_ttl_seconds: 300,
  });
  if (error) return null;
  const signature = (await sha256Hex(`${raw}:${botToken}:owner-action`)).slice(0, 12);
  return { text: label, callback_data: `za:${raw}:${signature}` };
}

function inferDecisionId(result: any): string | null {
  const candidates = [
    result?.entity?.type === "decision" ? result?.entity?.id : null,
    result?.decision_id,
    result?.evidence?.id,
    result?.evidence?.item?.id,
  ];
  for (const value of candidates) if (isUuid(value)) return String(value);
  return null;
}

function inferMarket(result: any): { id: string | null; name: string | null } {
  const idCandidates = [result?.market_id, result?.entity?.type === "market" ? result?.entity?.id : null, result?.evidence?.market_id];
  const nameCandidates = [result?.market_name, result?.entity?.type === "market" ? result?.entity?.name : null, result?.evidence?.market_name];
  let id: string | null = null;
  let name: string | null = null;
  for (const value of idCandidates) if (isUuid(value)) { id = String(value); break; }
  for (const value of nameCandidates) {
    const v = String(value ?? "").trim();
    if (v) { name = v.slice(0, 140); break; }
  }
  return { id, name };
}

function baseQueryForIntent(intent: string): string | null {
  if (intent.includes("brief")) return "ئەمڕۆ چی گرنگە؟";
  if (intent === "health") return "دۆخی سیستەم چیە؟";
  if (intent === "risk") return "ڕیسک چۆنە؟";
  return null;
}

async function buildOwnerActionKeyboard(admin: any, botToken: string, ownerId: string, result: any): Promise<any | null> {
  const intent = String(result?.intent ?? "help");
  const market = inferMarket(result);
  const decisionId = inferDecisionId(result);
  const rows: any[][] = [];

  if (market.id || market.name) {
    const baseQuery = `دۆخی ${market.name ?? "مارکێتەکە"} چیە؟`;
    const evidence = await issueOwnerActionButton(admin, botToken, ownerId, "🔎 Evidence", "evidence", "market", market.id, { base_query: baseQuery, market_name: market.name });
    const recommend = await issueOwnerActionButton(admin, botToken, ownerId, "💡 پێشنیار", "recommend", "market", market.id, { base_query: baseQuery, market_name: market.name });
    const openMarket = await issueOwnerActionButton(admin, botToken, ownerId, "🏪 مارکێت", "market", "market", market.id, { base_query: baseQuery, market_name: market.name });
    if (evidence || recommend) rows.push([evidence, recommend].filter(Boolean));
    if (openMarket) rows.push([openMarket]);
  } else if (decisionId && intent !== "decision_ack") {
    const evidence = await issueOwnerActionButton(admin, botToken, ownerId, "🔎 Evidence", "evidence", "decision", decisionId, {});
    const recommend = await issueOwnerActionButton(admin, botToken, ownerId, "💡 پێشنیار", "recommend", "decision", decisionId, {});
    const ack = await issueOwnerActionButton(admin, botToken, ownerId, "✅ Acknowledge", "ack", "decision", decisionId, {});
    if (evidence || recommend) rows.push([evidence, recommend].filter(Boolean));
    if (ack) rows.push([ack]);
  } else {
    const baseQuery = baseQueryForIntent(intent);
    if (baseQuery) {
      const evidence = await issueOwnerActionButton(admin, botToken, ownerId, "🔎 Evidence", "evidence", null, null, { base_query: baseQuery });
      if (evidence) rows.push([evidence]);
    }
    if (["brief", "health", "risk", "changes", "decisions", "decision_ack"].some((x) => intent.includes(x))) {
      const decisions = await issueOwnerActionButton(admin, botToken, ownerId, "📥 Decision Inbox", "decisions", null, null, {});
      if (decisions) rows.push([decisions]);
    }
  }

  return rows.length ? { inline_keyboard: rows } : null;
}

async function sendOwnerSmartMessage(admin: any, botToken: string, chatId: string, ownerId: string, text: string, result: any) {
  try {
    const inline = await buildOwnerActionKeyboard(admin, botToken, ownerId, result);
    await telegramApi(botToken, "sendMessage", {
      chat_id: chatId,
      text,
      disable_web_page_preview: true,
      ...(inline ? { reply_markup: inline } : {}),
    });
  } catch (_) {
    await sendOwnerMessage(botToken, chatId, text);
  }
}

async function sendAskResult(admin: any, botToken: string, chatId: string, ownerId: string, question: string) {
  const result = await ownerAsk(admin, ownerId, question.slice(0, 500));
  const intent = String(result?.intent ?? "help").slice(0, 64);
  const confidence = String(result?.confidence ?? "unknown").slice(0, 32);
  const output = String(result?.message ?? "").trim() || "💬 Ask ZHIROX\n\nنەتوانرا وەڵامێکی ڕوون دروست بکرێت.";
  await auditOwnerCommand(admin, ownerId, `ask:${intent}`, "ok", { confidence, question: question.slice(0, 180) });
  await sendOwnerSmartMessage(admin, botToken, chatId, ownerId, output, result);
  return result;
}

async function ownerDecisionInboxText(admin: any, ownerId: string): Promise<string> {
  const { data, error } = await admin.rpc("get_owner_decision_inbox_service", { p_owner_user_id: ownerId, p_limit: 10 });
  if (error) throw error;
  const items = Array.isArray(data?.items) ? data.items : [];
  if (!items.length) return "📥 ZHIROX • Decision Inbox\n\n✅ ئێستا هیچ بڕیارێکی چالاک پێویست نییە.";
  const lines = ["📥 ZHIROX • Decision Inbox", `Critical ${asInt(data?.critical)} • Warning ${asInt(data?.warning)} • Total ${asInt(data?.total)}`, ""];
  for (const [index, item] of items.entries()) {
    const severity = String(item?.severity ?? "info");
    const icon = severity === "critical" ? "🔴" : severity === "warning" ? "🟠" : "🔵";
    lines.push(`${index + 1}. ${icon} ${String(item?.title ?? "Decision").slice(0, 160)}`);
    const body = String(item?.body ?? "").trim();
    if (body) lines.push(`   ${body.slice(0, 220)}`);
    lines.push(`   🕒 ${formatDate(item?.last_seen_at)}`);
  }
  lines.push("", "ℹ️ بڵێ «یەکەم»، «دووەم»... بۆ وردەکاری، یان inline action ـەکان بەکاربهێنە.");
  return lines.join("\n");
}

async function handleOwnerActionCallback(admin: any, botToken: string, query: any): Promise<Response> {
  const callbackId = String(query?.id ?? "");
  const chatId = query?.message?.chat?.id != null ? String(query.message.chat.id) : "";
  const data = String(query?.data ?? "");
  if (!callbackId || !chatId || !data) return new Response("ok", { status: 200 });

  const ownerId = await ownerByChat(admin, chatId);
  if (!ownerId) {
    try { await telegramApi(botToken, "answerCallbackQuery", { callback_query_id: callbackId, text: "Owner access نییە.", show_alert: true }); } catch (_) {}
    return new Response("ok", { status: 200 });
  }

  const match = data.match(/^za:([0-9a-f]{24}):([0-9a-f]{12})$/i);
  if (!match) {
    try { await telegramApi(botToken, "answerCallbackQuery", { callback_query_id: callbackId, text: "Action نادروستە.", show_alert: true }); } catch (_) {}
    return new Response("ok", { status: 200 });
  }

  const raw = match[1].toLowerCase();
  const suppliedSig = match[2].toLowerCase();
  const expectedSig = (await sha256Hex(`${raw}:${botToken}:owner-action`)).slice(0, 12);
  if (!(await secureEqual(suppliedSig, expectedSig))) {
    await auditOwnerCommand(admin, ownerId, "action_card_signature", "rejected");
    try { await telegramApi(botToken, "answerCallbackQuery", { callback_query_id: callbackId, text: "Signature نادروستە.", show_alert: true }); } catch (_) {}
    return new Response("ok", { status: 200 });
  }

  const tokenHash = await sha256Hex(raw);
  const { data: consumed, error } = await admin.rpc("consume_owner_telegram_action_token_service", {
    p_owner_user_id: ownerId,
    p_token_hash: tokenHash,
  });
  if (error || consumed?.ok !== true) {
    await auditOwnerCommand(admin, ownerId, "action_card_consume", "expired_or_used");
    try { await telegramApi(botToken, "answerCallbackQuery", { callback_query_id: callbackId, text: "⏱️ دوگمەکە بەسەرچووە یان پێشتر بەکارهاتووە.", show_alert: true }); } catch (_) {}
    return new Response("ok", { status: 200 });
  }

  try { await telegramApi(botToken, "answerCallbackQuery", { callback_query_id: callbackId, text: "✅ وەرگیرا" }); } catch (_) {}

  const action = String(consumed?.action ?? "");
  const entityType = String(consumed?.entity_type ?? "");
  const entityId = String(consumed?.entity_id ?? "");
  const payload = consumed?.payload && typeof consumed.payload === "object" ? consumed.payload : {};
  await auditOwnerCommand(admin, ownerId, `action:${action}`, "ok", { entity_type: entityType || null, entity_id: entityId || null });

  try {
    if (action === "decisions") {
      const text = await ownerDecisionInboxText(admin, ownerId);
      const result = await ownerAsk(admin, ownerId, "بڕیارەکانم پیشان بدە");
      await sendOwnerSmartMessage(admin, botToken, chatId, ownerId, text, { ...result, intent: "decisions" });
      return new Response("ok", { status: 200 });
    }

    if (entityType === "market") {
      const baseQuery = String(payload?.base_query ?? "").trim();
      if (!baseQuery) throw new Error("market_query_missing");
      let result = await ownerAsk(admin, ownerId, baseQuery);
      if (action === "evidence") result = await ownerAsk(admin, ownerId, "وردەکاری");
      if (action === "recommend") result = await ownerAsk(admin, ownerId, "چی پێشنیار دەکەیت؟");
      const output = String(result?.message ?? "").trim() || "نەتوانرا وەڵام دروست بکرێت.";
      await sendOwnerSmartMessage(admin, botToken, chatId, ownerId, output, result);
      return new Response("ok", { status: 200 });
    }

    if (entityType === "decision" && isUuid(entityId)) {
      if (action === "ack") {
        const { data: ack, error: ackError } = await admin.rpc("acknowledge_owner_decision_service", {
          p_owner_user_id: ownerId,
          p_decision_id: entityId,
        });
        if (ackError || ack?.ok !== true) throw new Error("ack_failed");
        const title = String(ack?.title ?? "Decision").slice(0, 180);
        const output = ack?.already_acknowledged === true
          ? `✅ ${title}\n\nپێشتر Acknowledge کراوە.`
          : `✅ ${title}\n\nAcknowledge کرا. هیچ financial action ـێک جێبەجێ نەکرا.`;
        await sendOwnerSmartMessage(admin, botToken, chatId, ownerId, output, { intent: "decision_ack" });
        return new Response("ok", { status: 200 });
      }

      const item = await getDecision(admin, ownerId, entityId);
      if (!item) throw new Error("decision_not_found");
      const output = action === "recommend" ? decisionRecommendationText(item) : decisionDetailText(item);
      await sendOwnerSmartMessage(admin, botToken, chatId, ownerId, output, {
        intent: action === "recommend" ? "decision_recommendation" : "decision_detail",
        entity: { type: "decision", id: entityId },
        evidence: item,
      });
      return new Response("ok", { status: 200 });
    }

    const baseQuery = String(payload?.base_query ?? "").trim();
    if (action === "evidence" && baseQuery) {
      await ownerAsk(admin, ownerId, baseQuery);
      const result = await ownerAsk(admin, ownerId, "بۆچی؟");
      await sendOwnerSmartMessage(admin, botToken, chatId, ownerId, String(result?.message ?? ""), result);
      return new Response("ok", { status: 200 });
    }

    throw new Error("unsupported_action");
  } catch (_) {
    await auditOwnerCommand(admin, ownerId, `action:${action}`, "failed");
    await sendOwnerMessage(botToken, chatId, "❌ Action Card لەم ساتەدا نەتوانرا جێبەجێ بکرێت. داتای دارایی نەگۆڕدرا.");
    return new Response("ok", { status: 200 });
  }
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

async function requestPdf(supabaseUrl: string, botToken: string, chatId: string, action: "statement" | "receipt") {
  const internal = await sha256Hex(`${botToken}:customer-pdf`);
  const response = await fetch(`${supabaseUrl}/functions/v1/telegram-customer-pdf`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-zhirox-telegram-internal": internal },
    body: JSON.stringify({ chat_id: chatId, action }),
    signal: AbortSignal.timeout(30000),
  });
  let body: any = {};
  try { body = await response.json(); } catch (_) {}
  if (!response.ok) throw new Error("pdf_failed");
  return body;
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
  if (!providedSecret || !(await secureEqual(providedSecret, expectedSecret))) return new Response("forbidden", { status: 403 });

  let update: any;
  try { update = await req.json(); } catch (_) { return new Response("ok", { status: 200 }); }

  if (update?.callback_query) return handleOwnerActionCallback(admin, botToken, update.callback_query);

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
        await sendOwnerMessage(botToken, chatId, "✅ Telegramی System Owner پەیوەستە.\n🧠 ZHIROX Telegram OS + Intelligent Action Cards چالاکە.\nDaily Digest هەر ڕۆژ 08:30 بە کاتی عێراق دەنێردرێت.");
        return new Response("ok", { status: 200 });
      }
      try {
        const current = await snapshot(admin, chatId);
        if (current) await sendMessage(botToken, chatId, `بەخێربێیت بۆ ZHIROX • ${String(current.market_name ?? "ZHIROX")}\nدوگمەی خوارەوە هەڵبژێرە.`, true);
        else await sendMessage(botToken, chatId, "بۆ پەیوەستکردنی Telegram، لە ناو ZHIROX → Telegram → «پەیوەستکردن» کلیک بکە.");
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
    const { data: linkedProfile } = await admin.from("profiles").select("is_system_owner").eq("id", data).maybeSingle();
    if (linkedProfile?.is_system_owner === true) {
      await sendOwnerMessage(botToken, chatId, "✅ Telegramی System Owner بە سەرکەوتوویی پەیوەست کرا.\n💬 Ask ZHIROX + signed Action Cards چالاکن.\nDaily Owner Digest هەر ڕۆژ 08:30 بە کاتی عێراق دەنێردرێت.");
    } else {
      await sendMessage(botToken, chatId, "✅ Telegram بە سەرکەوتوویی پەیوەست کرا.\nئێستا دەتوانیت بە دوگمەکانی خوارەوە زانیاری هەژمارەکەت ببینیت.", true);
    }
    return new Response("ok", { status: 200 });
  }

  const owner = await ownerByChat(admin, chatId);
  if (owner) {
    if (text === "/menu" || text === "menu") {
      await auditOwnerCommand(admin, owner, "menu");
      await sendOwnerMessage(botToken, chatId, "🧠 ZHIROX Telegram OS\n\n💬 بە زمانی ئاسایی بپرسە یان دوگمەکان بەکاربهێنە. Action Cards ـەکان 5 خولەک کار دەکەن.");
      return new Response("ok", { status: 200 });
    }

    if (text === "🕒 Daily Digest") {
      await auditOwnerCommand(admin, owner, "daily_digest_info", "ok");
      await sendOwnerMessage(botToken, chatId, "🕒 Daily Owner Digest\n\nهەر ڕۆژ 08:30 بە کاتی عێراق دەنێردرێت.\nئەگەر failure بێت هەر 15 خولەک retry دەکرێت تا سەرکەوتن، و لە هەر ڕۆژێک تەنها یەکجار دەنێردرێت.");
      return new Response("ok", { status: 200 });
    }

    let question = text;
    if (text === "🧠 Executive Brief" || /^\/brief(?:@\w+)?$/.test(text)) question = "ئەمڕۆ چی گرنگە؟";
    else if (text === "📥 Decision Inbox" || /^\/decisions(?:@\w+)?$/.test(text)) question = "بڕیارەکانم پیشان بدە";
    else if (text === "🔄 چی گۆڕاوە؟" || /^\/changes(?:@\w+)?$/.test(text)) question = "چی گۆڕاوە؟";
    else if (text === "📊 دۆخی AutoPilot" || /^\/health(?:@\w+)?$/.test(text) || /^\/digest(?:@\w+)?$/.test(text)) question = "دۆخی سیستەم چیە؟";
    else if (text === "💬 Ask ZHIROX" || text === "/ask") question = "help";
    else if (text.startsWith("/")) {
      await auditOwnerCommand(admin, owner, "unknown_slash", "ignored", { text: text.slice(0, 80) });
      await sendOwnerMessage(botToken, chatId, "💬 Ask ZHIROX\n\nبە زمانی ئاسایی بپرسە، یان: /brief • /decisions • /changes • /health");
      return new Response("ok", { status: 200 });
    }

    try {
      await sendAskResult(admin, botToken, chatId, owner, question);
    } catch (_) {
      await auditOwnerCommand(admin, owner, "ask", "failed", { question: question.slice(0, 180) });
      await sendOwnerMessage(botToken, chatId, "❌ Ask ZHIROX لەم ساتەدا نەتوانی وەڵام بدات. فرمانە بنەڕەتییەکان هەر کار دەکەن.");
    }
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
    await sendMessage(botToken, chatId, "📄 کەشف حسابی PDF دروست دەکرێت…");
    try { await requestPdf(supabaseUrl, botToken, chatId, "statement"); }
    catch (_) { await sendMessage(botToken, chatId, "❌ نەتوانرا PDF دروست بکرێت. دووبارە هەوڵ بدەوە.", true); }
    return new Response("ok", { status: 200 });
  }
  if (text === "🧾 PDF پسووڵە" || /^\/receiptpdf(?:@\w+)?$/.test(text)) {
    await sendMessage(botToken, chatId, "🧾 پسووڵەی PDF دروست دەکرێت…");
    try {
      const result = await requestPdf(supabaseUrl, botToken, chatId, "receipt");
      if (result?.sent === false && result?.reason === "no_transactions") await sendMessage(botToken, chatId, "هێشتا هیچ مامەڵەیەک نییە بۆ دروستکردنی پسووڵە.", true);
    } catch (_) { await sendMessage(botToken, chatId, "❌ نەتوانرا پسووڵەی PDF دروست بکرێت. دووبارە هەوڵ بدەوە.", true); }
    return new Response("ok", { status: 200 });
  }
  if (text === "📚 کەشفی تەواو PDF" || /^\/fullstatementpdf(?:@\w+)?$/.test(text)) {
    const { data, error } = await admin.rpc("enqueue_telegram_full_statement_service", { p_chat_id: chatId });
    if (error || !data) await sendMessage(botToken, chatId, "❌ نەتوانرا کەشف حسابی تەواو دەستپێبکرێت. دووبارە هەوڵ بدەوە.", true);
    else {
      const total = Number(data.total_rows ?? 0);
      const parts = Number(data.total_parts ?? 1);
      const existing = Boolean(data.existing);
      await sendMessage(botToken, chatId, existing
        ? `📚 کەشف حسابی تەواو پێشتر لە ڕیزدایە.\n${total.toLocaleString("en-US")} مامەڵە • ${parts} بەشی PDF`
        : `📚 دروستکردنی کەشف حسابی تەواو دەستی پێکرد.\n${total.toLocaleString("en-US")} مامەڵە • ${parts} بەشی PDF\nبەشەکان خۆکار یەک بە یەک دەنێردرێن.`, true);
    }
    return new Response("ok", { status: 200 });
  }
  if (text === "🌐 هەژماری من" || /^\/account(?:@\w+)?$/.test(text)) {
    const rawToken = randomHex(32);
    const tokenHash = await sha256Hex(rawToken);
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
    const { error } = await admin.rpc("create_telegram_customer_read_link_service", { p_chat_id: chatId, p_token_hash: tokenHash, p_expires_at: expiresAt });
    if (error) await sendMessage(botToken, chatId, "❌ نەتوانرا لینکی پارێزراو دروست بکرێت. دووبارە هەوڵ بدەوە.", true);
    else await sendMessage(botToken, chatId, `🌐 هەژماری ZHIROX ـت\n\nلینکەکە 10 خولەک کار دەکات:\nhttps://push.zhirox.com/?token=${rawToken}`, true);
    return new Response("ok", { status: 200 });
  }

  await sendMessage(botToken, chatId, "فرمانەکە نەناسرا. یەکێک لە دوگمەکان هەڵبژێرە.", true);
  return new Response("ok", { status: 200 });
});
