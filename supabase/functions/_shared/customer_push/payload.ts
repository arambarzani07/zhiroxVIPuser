export type PushEventType = "debt_created" | "payment_created" | "manual";

export type PushPayload = {
  amount?: number;
  currency?: string;
  remaining_iqd?: number;
  market_name: string;
  occurred_at: string;
  message?: string;
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
        `🧾 قەرزی نوێ تۆمارکرا • بڕ: ${formatAmount(payload.amount, payload.currency)} • کۆی ماوە: ${formatIqd(payload.remaining_iqd)}`,
    };
  }

  return {
    title: market,
    body:
      `💰 پارەدانەوە تۆمارکرا • بڕی دراو: ${formatAmount(payload.amount, payload.currency)} • ماوە: ${formatIqd(payload.remaining_iqd)}`,
  };
}
