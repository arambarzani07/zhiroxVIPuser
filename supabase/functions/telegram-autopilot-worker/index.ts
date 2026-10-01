import { createClient } from "npm:@supabase/supabase-js@2.116.0";

function envJsonKey(name: string): string | null {
  const raw = Deno.env.get(name);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as Record<string, string>;
    return parsed.default ?? Object.values(parsed)[0] ?? null;
  } catch (_) {
    return raw;
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

async function secureSecretEqual(left: string, right: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [aHash, bHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(left)),
    crypto.subtle.digest("SHA-256", encoder.encode(right)),
  ]);
  const a = new Uint8Array(aHash);
  const b = new Uint8Array(bHash);
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

function formatAmount(value: unknown, currency: unknown): string {
  const amount = Number(value ?? 0);
  const normalized = Number.isFinite(amount) ? amount : 0;
  if (String(currency ?? "").toUpperCase() === "USD") {
    return `$${normalized.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
  }
  return `${Math.round(normalized).toLocaleString("en-US")} د.ع`;
}

function formatIqd(value: unknown): string {
  const amount = Number(value ?? 0);
  return `${Math.round(Number.isFinite(amount) ? amount : 0).toLocaleString("en-US")} د.ع`;
}

function eventMessage(eventType: string, payload: Record<string, unknown>): string {
  const market = String(payload.market_name ?? "ZHIROX").trim() || "ZHIROX";
  switch (eventType) {
    case "debt_created":
      return `${market}\n🧾 قەرزی نوێ تۆمارکرا\nبڕ: ${formatAmount(payload.amount, payload.currency)}\nکۆی ماوە: ${formatIqd(payload.remaining_iqd)}`;
    case "payment_created":
      return Number(payload.remaining_iqd ?? 0) <= 0
        ? `${market}\n✅ قەرزەکانت بە تەواوی دراونەتەوە 🎉\nبڕی وەرگیراو: ${formatAmount(payload.amount, payload.currency)}`
        : `${market}\n💰 پارەدانەوە تۆمارکرا\nبڕی دراو: ${formatAmount(payload.amount, payload.currency)}\nماوە: ${formatIqd(payload.remaining_iqd)}`;
    case "due_reminder": {
      const overdue = payload.overdue === true;
      const overdueDays = Number(payload.days_overdue ?? 0);
      const untilDays = Number(payload.days_until_due ?? 0);
      if (overdue) {
        return `${market}\n⚠️ قەرزەکەت ${overdueDays > 0 ? `${overdueDays} ڕۆژ ` : ""}دواکەوتووە\nکۆی ماوە: ${formatIqd(payload.remaining_iqd)}`;
      }
      return `${market}\n⏰ ${untilDays === 0 ? "ئەمڕۆ بەرواری دانەوەی قەرزەکەتە" : `${untilDays} ڕۆژ ماوە بۆ دانەوەی قەرز`}\nبڕ: ${formatAmount(payload.amount, payload.currency)}`;
    }
    case "installment_reminder":
      return `${market}\n📅 بیرخستنەوەی قسط${payload.installment_no ? `ی ${payload.installment_no}` : ""}\nبڕ: ${formatAmount(payload.amount, payload.currency)}`;
    case "monthly_statement":
      return `${market}\n📄 کەشفی حیسابی مانگی ${String(payload.period ?? "")} ئامادەیە\nقەرزی نوێ: ${formatIqd(payload.total_debt)}\nپارەدان: ${formatIqd(payload.total_paid)}\nماوە: ${formatIqd(payload.remaining_iqd)}`;
    case "debt_limit_changed":
      return `${market}\n📊 سنووری قەرزەکەت نوێکرایەوە\nلە ${formatIqd(payload.old_limit)} بۆ ${formatIqd(payload.new_limit)}`;
    case "manual":
      return `${market}\n${String(payload.message ?? "").trim()}`;
    default:
      return `${market}\nئاگادارکردنەوەی نوێ لە ZHIROX`;
  }
}

function retryableTelegramStatus(status: number): boolean {
  return status === 408 || status === 425 || status === 429 || status >= 500;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = (Deno.env.get("SUPABASE_URL") ?? "").trim();
  const secret = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? envJsonKey("SUPABASE_SECRET_KEYS") ?? "").trim();
  if (!url || !secret) return json({ error: "server_not_configured" }, 500);

  const admin = createClient(url, secret, { auth: { persistSession: false, autoRefreshToken: false } });

  const runtime = await admin.rpc("get_customer_push_runtime_config_service");
  if (runtime.error) return json({ error: "worker_runtime_unavailable" }, 500);
  const workerSecret = String(runtime.data?.customer_push_worker_secret ?? "").trim();
  const provided = (req.headers.get("x-zhirox-push-worker") ?? "").trim();
  if (!provided || !workerSecret || !(await secureSecretEqual(provided, workerSecret))) {
    return json({ error: "unauthorized" }, 401);
  }

  const config = await admin.rpc("get_telegram_runtime_config_service");
  if (config.error) return json({ error: "telegram_config_unavailable" }, 500);
  const configRow = Array.isArray(config.data) ? config.data[0] : config.data;
  const botToken = String(configRow?.bot_token ?? "").trim();
  if (!botToken) return json({ ok: true, processed: 0, reason: "telegram_not_configured" });

  const claimed = await admin.rpc("claim_telegram_autopilot_deliveries_service", { p_limit: 25 });
  if (claimed.error) return json({ error: "claim_failed" }, 500);

  let processed = 0;
  let sent = 0;
  let skipped = 0;
  let retried = 0;
  let failed = 0;

  for (const row of claimed.data ?? []) {
    processed++;
    const deliveryId = String(row.delivery_id ?? "");
    const chatId = String(row.chat_id ?? "").trim();
    const eventType = String(row.event_type ?? "");
    const payload = (row.payload && typeof row.payload === "object" ? row.payload : {}) as Record<string, unknown>;
    const deepLink = String(row.deep_link ?? "").trim();

    if (!deliveryId) continue;
    if (!chatId) {
      await admin.rpc("finish_telegram_autopilot_delivery_service", {
        p_delivery_id: deliveryId,
        p_status: "skipped",
        p_error: "customer_telegram_not_connected",
        p_provider_message_id: null,
      });
      skipped++;
      continue;
    }

    let text = eventMessage(eventType, payload);
    if (deepLink.startsWith("https://")) text += `\n${deepLink}`;

    try {
      const response = await fetch(`https://api.telegram.org/bot${botToken}/sendMessage`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ chat_id: chatId, text, disable_web_page_preview: true }),
        signal: AbortSignal.timeout(8000),
      });

      let result: Record<string, any> = {};
      try { result = await response.json(); } catch (_) { result = {}; }

      if (response.ok && result?.ok === true) {
        await admin.rpc("finish_telegram_autopilot_delivery_service", {
          p_delivery_id: deliveryId,
          p_status: "sent",
          p_error: null,
          p_provider_message_id: String(result?.result?.message_id ?? ""),
        });
        sent++;
        continue;
      }

      const errorText = String(result?.description ?? `telegram_http_${response.status}`).slice(0, 500);
      if (retryableTelegramStatus(response.status)) {
        await admin.rpc("retry_telegram_autopilot_delivery_service", {
          p_delivery_id: deliveryId,
          p_error: errorText,
        });
        retried++;
      } else {
        await admin.rpc("finish_telegram_autopilot_delivery_service", {
          p_delivery_id: deliveryId,
          p_status: "failed",
          p_error: errorText,
          p_provider_message_id: null,
        });
        failed++;
      }
    } catch (error) {
      await admin.rpc("retry_telegram_autopilot_delivery_service", {
        p_delivery_id: deliveryId,
        p_error: String(error instanceof Error ? error.message : error).slice(0, 500),
      });
      retried++;
    }
  }

  return json({ ok: true, processed, sent, skipped, retried, failed });
});
