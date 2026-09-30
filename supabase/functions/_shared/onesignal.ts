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

export type OneSignalOutboxEvent = {
  outboxId: string;
  customerId: string;
  eventType: PushEventType;
  eventRecordId?: string | null;
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

function appPayload(input: {
  customerId: string;
  eventType: PushEventType;
  eventRecordId?: string | null;
  payload: PushPayload;
}): Record<string, unknown> {
  const base: Record<string, unknown> = {
    customer_id: input.customerId,
  };
  const recordId = String(input.eventRecordId ?? "").trim();

  switch (input.eventType) {
    case "debt_created":
      return {
        ...base,
        type: "new_debt",
        if_debt_id: undefined,
        ...(recordId ? { debt_id: recordId } : {}),
        open_financial_chat: true,
      };
    case "payment_created":
      return {
        ...base,
        type: "payment_received",
        ...(recordId ? { payment_id: recordId } : {}),
        open_financial_chat: true,
      };
    case "due_reminder":
      return {
        ...base,
        type: "due_reminder",
        ...(input.payload.debt_id ? { debt_id: input.payload.debt_id } : {}),
        open_financial_chat: true,
      };
    case "installment_reminder":
      return {
        ...base,
        type: "installment_reminder",
        ...(input.payload.debt_id ? { debt_id: input.payload.debt_id } : {}),
        ...(input.payload.installment_no != null
          ? { installment_no: input.payload.installment_no }
          : {}),
        open_financial_chat: true,
      };
    case "debt_limit_changed":
      return {
        ...base,
        type: "debt_limit_changed",
        open_financial_chat: true,
      };
    case "monthly_statement":
      return {
        ...base,
        type: "monthly_statement",
        ...(input.payload.period ? { period: input.payload.period } : {}),
      };
    case "manual":
      return {
        ...base,
        type: "manual",
      };
  }
}

async function sendOneSignal(params: {
  customerId: string;
  eventType: PushEventType;
  eventRecordId?: string | null;
  payload: PushPayload;
  idempotencyKey: string;
  logContext: string;
}): Promise<OneSignalSendResult> {
  const appId = env("ONESIGNAL_APP_ID");
  const apiKey = env("ONESIGNAL_REST_API_KEY");
  if (!appId || !apiKey) {
    return {
      attempted: false,
      delivered: false,
      reason: "onesignal_not_configured",
    };
  }

  const customerId = params.customerId.trim();
  const idempotencyKey = params.idempotencyKey.trim();
  if (!customerId || !isUuid(idempotencyKey)) {
    return {
      attempted: false,
      delivered: false,
      reason: "invalid_target_or_event_id",
    };
  }

  const message = formatPushBody(params.eventType, params.payload);

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
        data: appPayload({
          customerId,
          eventType: params.eventType,
          eventRecordId: params.eventRecordId,
          payload: params.payload,
        }),
        idempotency_key: idempotencyKey,
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
        `${params.logContext} failed`,
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
    return messageId
      ? { attempted: true, delivered: true, messageId }
      : {
          attempted: true,
          delivered: false,
          reason: "no_active_subscription",
        };
  } catch (error) {
    console.warn(
      `${params.logContext} deferred`,
      error instanceof Error ? error.message : String(error),
    );
    return {
      attempted: true,
      delivered: false,
      reason: "transport_error",
    };
  }
}

/**
 * Best-effort delivery for debt/payment writes. The financial record remains
 * authoritative and a push-provider outage must never roll it back.
 */
export function sendOneSignalFinancialEventBestEffort(
  event: OneSignalFinancialEvent,
): Promise<OneSignalSendResult> {
  return sendOneSignal({
    customerId: event.customerId,
    eventType: event.eventType,
    eventRecordId: event.eventRecordId,
    payload: event.payload,
    idempotencyKey: event.eventRecordId,
    logContext: "OneSignal financial push",
  });
}

/**
 * Best-effort delivery for the existing notification outbox. Debt/payment are
 * intentionally skipped here because they are already sent immediately by the
 * transaction Edge Functions with their record ID as the idempotency key.
 */
export function sendOneSignalOutboxEventBestEffort(
  event: OneSignalOutboxEvent,
): Promise<OneSignalSendResult> {
  if (event.eventType === "debt_created" || event.eventType === "payment_created") {
    return Promise.resolve({
      attempted: false,
      delivered: false,
      reason: "financial_event_sent_at_write_time",
    });
  }

  return sendOneSignal({
    customerId: event.customerId,
    eventType: event.eventType,
    eventRecordId: event.eventRecordId,
    payload: event.payload,
    idempotencyKey: event.outboxId,
    logContext: `OneSignal outbox ${event.eventType}`,
  });
}
