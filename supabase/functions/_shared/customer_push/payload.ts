export type PushEventType = "debt_created" | "payment_created";

export type PushPayload = {
  amount: number;
  currency: string;
  remaining_iqd: number;
  market_name: string;
  occurred_at: string;
};

function formatAmount(amount: number, currency: string): string {
  const normalized = Number.isFinite(amount) ? amount : 0;
  if (currency === "USD") {
    return `$${normalized.toLocaleString("en-US", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    })}`;
  }
  return `${Math.round(normalized).toLocaleString("en-US")} د.ع`;
}

function formatIqd(amount: number): string {
  return `${Math.round(Number.isFinite(amount) ? amount : 0).toLocaleString("en-US")} د.ع`;
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
  const market = String(payload.market_name ?? "").trim();
  const marketSuffix = market ? ` • مارکێت: ${market}` : "";
  if (eventType === "debt_created") {
    return {
      title: "🧾 قەرزی نوێ تۆمارکرا",
      body:
        `بڕ: ${formatAmount(payload.amount, payload.currency)} • کۆی ماوە: ${formatIqd(payload.remaining_iqd)}${marketSuffix}`,
    };
  }
  return {
    title: "💰 پارەدانەوە تۆمارکرا",
    body:
      `بڕی دراو: ${formatAmount(payload.amount, payload.currency)} • ماوە: ${formatIqd(payload.remaining_iqd)}${marketSuffix}`,
  };
}
