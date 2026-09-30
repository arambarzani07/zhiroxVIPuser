import {
  formatPushBody,
  type PushEventType,
  type PushPayload,
} from "./customer_push/payload.ts";

export type OneSignalFinancialEvent = {
  customerId: string;
  eventType: "debt_created" | "payment_created";
  eventRecordId: string;
  payload: PushPayload;
};

export type OneSignalSendResult = {
  attempted: boolean;
  delivered: boolean;
  messageId?: string;
  reason?: string;
};

function env(name: string): string {
  return (Deno.env.get(name) ?? "").trim();
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

function appPayload(event: OneSignalFinancialEvent): Record<string, unknown> {
  if (event.eventType === "debt_created") {
    return {
      type: "new_debt",
      customer_id: event.customerId,
      debt_id: event.eventRecordId,
      open_financial_chat: true,
    };
  }

  return {
    type: "payment_received",
    customer_id: event.customerId,
    payment_id: event.eventRecordId,
    open_financial_chat: true,
  };
}

/**
 * Send a mobile push for an already-persisted financial event.
 *
 * This is intentionally best-effort: missing OneSignal secrets or provider
 * outages must never roll back a debt/payment write. The financial record and
 * notification_outbox remain authoritative.
 *
 * eventRecordId is used as OneSignal's idempotency key. Debt/payment record IDs
 * are UUIDs, so safe retries return the original OneSignal result instead of
 * delivering the same mobile notification twice.
 */
export async function sendOneSignalFinancialEventBestEffort(
  event: OneSignalFinancialEvent,
): Promise<OneSignalSendResult> {
  const appId = env("ONESIGNAL_APP_ID");
  const apiKey = env("ONESIGNAL_REST_API_KEY");
  if (!appId || !apiKey) {
    return {
      attempted: false,
      delivered: false,
      reason: "onesignal_not_configured",
    };
  }

  const customerId = event.customerId.trim();
  const recordId = event.eventRecordId.trim();
  if (!customerId || !isUuid(recordId)) {
    return {
      attempted: false,
      delivered: false,
      reason: "invalid_target_or_event_id",
    };
  }

  const message = formatPushBody(
    event.eventType as PushEventType,
    event.payload,
  );

  try {
    const response = await fetch("https://api.onesignal.com/notifications", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Key ${apiKey}`,
      },
      body: JSON.stringify({
        app_id: appId,
        target_channel: "push",
        include_aliases: { external_id: [customerId] },
        headings: { en: message.title },
        contents: { en: message.body },
        data: appPayload(event),
        idempotency_key: recordId,
      }),
    });

    let result: Record<string, unknown> = {};
    try {
      result = await response.json();
    } catch (_) {
      result = {};
    }

    if (!response.ok) {
      console.warn(
        "OneSignal financial push failed",
        response.status,
        JSON.stringify(result),
      );
      return {
        attempted: true,
        delivered: false,
        reason: `provider_${response.status}`,
      };
    }

    const messageId = typeof result.id === "string" ? result.id : "";
    return {
      attempted: true,
      delivered: messageId.length > 0,
      if: undefined,
      ...(messageId ? { messageId } : { reason: "no_active_subscription" }),
    } as OneSignalSendResult;
  } catch (error) {
    console.warn(
      "OneSignal financial push deferred",
      error instanceof Error ? error.message : String(error),
    );
    return {
      attempted: true,
      delivered: false,
      reason: "transport_error",
    };
  }
}
