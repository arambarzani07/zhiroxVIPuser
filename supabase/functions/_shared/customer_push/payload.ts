export type PushEventType =
  | "debt_created"
  | "payment_created"
  | "due_reminder"
  | "manual"
  | "debt_limit_changed"
  | "installment_reminder"
  | "monthly_statement";

export type PushPayload = {
  amount?: number;
  currency?: string;
  remaining_iqd?: number;
  market_name: string;
  occurred_at: string;
  due_date?: string;
  overdue?: boolean;
  message?: string;
  old_limit?: number;
  new_limit?: number;
  installment_no?: number;
  debt_id?: string;
  days_until_due?: number;
  days_overdue?: number;
  period?: string;
  total_debt?: number;
  total_paid?: number;
};

function formatAmount(amount: number | undefined, currency: string | undefined): string {
  const normalized = Number.isFinite(amount) ? Number(amount) : 0;
  if (String(currency ?? "").trim().toUpperCase() === "USD") {
    return `$${normalized.toLocaleString("en-US", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    })}`;
  }
  return `${Math.round(normalized).toLocaleString("en-US")} د.ع`;
}

function formatIqd(amount: number | undefined): string {
  const normalized = Number.isFinite(amount) ? Number(amount) : 0;
  return `${Math.round(normalized).toLocaleString("en-US")} د.ع`;
}

export function retryDelayAfterFailure(attemptCount: number): number | null {
  switch (attemptCount) {
    case 1:
      return 60;
    case 2:
      return 300;
    case 3:
      return 1800;
    case 4:
      return 7200;
    default:
      return null;
  }
}

export function classifyPushFailure(
  status: number,
): "expired" | "retry" | "failed" {
  if (status === 404 || status === 410) return "expired";
  if (status === 408 || status === 425 || status === 429 || status >= 500) {
    return "retry";
  }
  return "failed";
}

export function formatPushBody(
  eventType: PushEventType,
  payload: PushPayload,
): { title: string; body: string } {
  const market = String(payload.market_name ?? "").trim() || "ZHIROX";

  if (eventType === "manual") {
    return {
      title: market,
      body: String(payload.message ?? "").trim(),
    };
  }

  if (eventType === "debt_created") {
    return {
      title: market,
      body:
        `🧾 قەرزی نوێ تۆمارکرا • بڕ: ${formatAmount(payload.amount, payload.currency)} • کۆی ماوە: ${formatIqd(payload.remaining_iqd)} • کلیک بکە بۆ پسووڵە/کەشفی حیساب`,
    };
  }

  if (eventType === "payment_created") {
    if (Number(payload.remaining_iqd ?? 0) <= 0) {
      return {
        title: market,
        body:
          `✅ قەرزەکانت بە تەواوی دراونەتەوە 🎉 • بڕی وەرگیراو: ${formatAmount(payload.amount, payload.currency)} • کلیک بکە بۆ پسووڵە`,
      };
    }
    return {
      title: market,
      body:
        `💰 پارەدانەوە تۆمارکرا • بڕی دراو: ${formatAmount(payload.amount, payload.currency)} • ماوە: ${formatIqd(payload.remaining_iqd)} • کلیک بکە بۆ پسووڵە/کەشفی حیساب`,
    };
  }

  if (eventType === "due_reminder") {
    const overdueDays = Number(payload.days_overdue ?? 0);
    const untilDays = Number(payload.days_until_due ?? 0);
    return {
      title: market,
      body: payload.overdue === true
        ? `⚠️ قەرزەکەت ${overdueDays > 0 ? `${overdueDays} ڕۆژ ` : ""}دوا کەوتووە • بڕی دواخراو: ${formatAmount(payload.amount, payload.currency)} • کۆی ماوە: ${formatIqd(payload.remaining_iqd)}`
        : untilDays === 0
        ? `⏰ ئەمڕۆ بەرواری دانەوەی قەرزەکەتە • بڕ: ${formatAmount(payload.amount, payload.currency)}`
        : `⏰ ${untilDays} ڕۆژ ماوە بۆ دانەوەی قەرز • بڕ: ${formatAmount(payload.amount, payload.currency)}`,
    };
  }

  if (eventType === "installment_reminder") {
    const no = Number(payload.installment_no ?? 0);
    return {
      title: market,
      body: payload.overdue === true
        ? `⚠️ قسطی ${no || ""} دوا کەوتووە • بڕ: ${formatAmount(payload.amount, payload.currency)}`
        : `📅 بیرخستنەوەی قسطی ${no || ""} • بڕ: ${formatAmount(payload.amount, payload.currency)}`,
    };
  }

  if (eventType === "debt_limit_changed") {
    return {
      title: market,
      body:
        `📊 سنووری قەرزەکەت نوێکرایەوە • لە ${formatIqd(payload.old_limit)} بۆ ${formatIqd(payload.new_limit)}`,
    };
  }

  return {
    title: market,
    body:
      `📄 کەشفی حیسابی مانگی ${String(payload.period ?? "").trim()} ئامادەیە • کۆی قەرزی نوێ: ${formatIqd(payload.total_debt)} • پارەدان: ${formatIqd(payload.total_paid)} • ماوە: ${formatIqd(payload.remaining_iqd)}`,
  };
}
