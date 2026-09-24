import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import webpush from "npm:web-push@3.6.7";
import {
  classifyPushFailure,
  formatPushBody,
  retryDelayAfterFailure,
  type PushEventType,
  type PushPayload,
} from "../_shared/customer_push/payload.ts";
import { loadOrInitializePushRuntime } from "../_shared/customer_push/runtime.ts";

function envJsonKey(name: string): string | null {
  const raw = Deno.env.get(name);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    return parsed.default ?? Object.values(parsed)[0] ?? null;
  } catch (_) {
    return raw;
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export type WorkerEvent = {
  id: string;
  market_id: string;
  customer_id: string;
  event_type: PushEventType;
  event_record_id?: string;
  deep_link?: string | null;
  receipt_id?: string | null;
  payload: PushPayload;
  fanout_at?: string | null;
};

export type WorkerSubscription = {
  id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  active: boolean;
};

export type WorkerDelivery = {
  id: string;
  subscription_id: string;
  status: "pending" | "sent" | "failed" | "expired";
  attempt_count: number;
  next_attempt_at?: string | null;
  subscription: WorkerSubscription;
};

export type WorkerDeps = {
  now: () => Date;
  listActiveSubscriptions: (event: WorkerEvent) => Promise<WorkerSubscription[]>;
  insertDeliveryIfMissing: (outboxId: string, subscriptionId: string) => Promise<void>;
  setFanoutAt: (outboxId: string, iso: string) => Promise<void>;
  listDueDeliveries: (outboxId: string, nowIso: string) => Promise<WorkerDelivery[]>;
  sendPush: (
    subscription: WorkerSubscription,
    message: { title: string; body: string; url: string },
  ) => Promise<void>;
  updateDelivery: (deliveryId: string, patch: Record<string, unknown>) => Promise<void>;
  updateSubscription: (subscriptionId: string, patch: Record<string, unknown>) => Promise<void>;
  countPendingDeliveries: (outboxId: string) => Promise<number>;
  earliestPendingAt: (outboxId: string) => Promise<string | null>;
  updateOutbox: (outboxId: string, patch: Record<string, unknown>) => Promise<void>;
};

export type ReconcileDebt = {
  id: string;
  marketId: string;
  customerId: string;
  marketName: string;
  amount: number;
  amountUsd: number;
  currency: string;
  dollarRate: number;
  remainingIqd: number;
  occurredAt: string;
  deleted: boolean;
  legacyLinked: boolean;
  syncLinked: boolean;
  hasOutbox: boolean;
};

export type ReconcileEnqueue = {
  marketId: string;
  customerId: string;
  eventType: "debt_created";
  eventRecordId: string;
  idempotencyKey: string;
  payload: {
    amount: number;
    currency: "IQD" | "USD";
    remaining_iqd: number;
    market_name: string;
    occurred_at: string;
  };
};

export type ReconcileDeps = {
  now: () => Date;
  listCandidates: (fromIso: string, toIso: string, limit: number) => Promise<ReconcileDebt[]>;
  enqueuePush: (event: ReconcileEnqueue) => Promise<void>;
};

function statusCode(error: unknown): number {
  if (error && typeof error === "object") {
    const map = error as Record<string, unknown>;
    return Number(map.statusCode ?? map.status ?? 0);
  }
  return 0;
}

function errorText(error: unknown): string {
  const text = error instanceof Error ? error.message : String(error);
  return text.slice(0, 500);
}

function portalUrlForEvent(event: WorkerEvent): string {
  const storedDeepLink = String(event.deep_link ?? "").trim();
  if (storedDeepLink.startsWith("/")) {
    const target = new URL(storedDeepLink, "https://push.zhirox.com/");
    if (!target.searchParams.has("notification")) {
      target.searchParams.set("notification", event.id);
    }
    return target.toString();
  }

  const params = new URLSearchParams();
  const eventType = event.event_type;
  params.set(
    "view",
    eventType === "manual" || eventType === "debt_limit_changed"
      ? "notifications"
      : "transactions",
  );
  params.set("notification", event.id);

  if (eventType === "debt_created" || eventType === "payment_created") {
    params.set("event", String((event as any).event_record_id ?? ""));
  } else if (eventType === "installment_reminder") {
    const debtId = String(event.payload.debt_id ?? "").trim();
    if (debtId) params.set("event", debtId);
  } else if (eventType === "monthly_statement") {
    const period = String(event.payload.period ?? "").trim();
    if (period) params.set("period", period);
  }

  return `https://push.zhirox.com/?${params.toString()}`;
}

export async function reconcileRecentDebts(deps: ReconcileDeps): Promise<number> {
  const now = deps.now();
  const from = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  const to = new Date(now.getTime() - 2 * 60 * 1000);
  const candidates = await deps.listCandidates(from.toISOString(), to.toISOString(), 100);
  let enqueued = 0;

  for (const debt of candidates) {
    if (debt.deleted || debt.legacyLinked || debt.syncLinked || debt.hasOutbox) continue;
    const occurredMs = Date.parse(debt.occurredAt);
    if (!Number.isFinite(occurredMs)) continue;
    const ageMs = now.getTime() - occurredMs;
    if (ageMs < 2 * 60 * 1000 || ageMs > 24 * 60 * 60 * 1000) continue;

    const useUsd = debt.currency.trim().toUpperCase() === "USD" && debt.dollarRate > 0;
    const currency: "IQD" | "USD" = useUsd ? "USD" : "IQD";
    const displayAmount = useUsd
      ? (debt.amountUsd > 0
        ? debt.amountUsd
        : Math.round((debt.amount / debt.dollarRate) * 100) / 100)
      : debt.amount;

    await deps.enqueuePush({
      marketId: debt.marketId,
      customerId: debt.customerId,
      eventType: "debt_created",
      eventRecordId: debt.id,
      idempotencyKey: `debt_created:${debt.id}`,
      payload: {
        amount: displayAmount,
        currency,
        remaining_iqd: debt.remainingIqd,
        market_name: debt.marketName,
        occurred_at: debt.occurredAt,
      },
    });
    enqueued++;
  }

  return enqueued;
}

export async function processOutboxEvent(
  event: WorkerEvent,
  deps: WorkerDeps,
): Promise<void> {
  const now = deps.now();
  const nowIso = now.toISOString();

  if (!event.fanout_at) {
    const subscriptions = await deps.listActiveSubscriptions(event);
    for (const subscription of subscriptions) {
      await deps.insertDeliveryIfMissing(event.id, subscription.id);
    }
    await deps.setFanoutAt(event.id, nowIso);
    event.fanout_at = nowIso;
  }

  const message = formatPushBody(event.event_type, event.payload);
  const due = await deps.listDueDeliveries(event.id, nowIso);
  for (const delivery of due) {
    const nextAttempt = delivery.attempt_count + 1;
    try {
      await deps.sendPush(delivery.subscription, {
        ...message,
        url: portalUrlForEvent(event),
      });
      await deps.updateDelivery(delivery.id, {
        status: "sent",
        attempt_count: nextAttempt,
        provider_status: 201,
        last_error: null,
        next_attempt_at: null,
        sent_at: nowIso,
        updated_at: nowIso,
      });
      await deps.updateSubscription(delivery.subscription.id, {
        failure_count: 0,
        last_failure_at: null,
        last_success_at: nowIso,
        updated_at: nowIso,
      });
    } catch (error) {
      const code = statusCode(error);
      const classification = classifyPushFailure(code || 500);
      if (classification === "expired") {
        await deps.updateDelivery(delivery.id, {
          status: "expired",
          attempt_count: nextAttempt,
          provider_status: code || null,
          last_error: errorText(error),
          next_attempt_at: null,
          updated_at: nowIso,
        });
        await deps.updateSubscription(delivery.subscription.id, {
          active: false,
          failure_count: nextAttempt,
          last_failure_at: nowIso,
          updated_at: nowIso,
        });
        continue;
      }

      const delay = classification === "retry"
        ? retryDelayAfterFailure(nextAttempt)
        : null;
      if (classification === "retry" && delay != null) {
        await deps.updateDelivery(delivery.id, {
          status: "pending",
          attempt_count: nextAttempt,
          provider_status: code || null,
          last_error: errorText(error),
          next_attempt_at: new Date(now.getTime() + delay * 1000).toISOString(),
          updated_at: nowIso,
        });
      } else {
        await deps.updateDelivery(delivery.id, {
          status: "failed",
          attempt_count: nextAttempt,
          provider_status: code || null,
          last_error: errorText(error),
          next_attempt_at: null,
          updated_at: nowIso,
        });
      }
      await deps.updateSubscription(delivery.subscription.id, {
        failure_count: nextAttempt,
        last_failure_at: nowIso,
        updated_at: nowIso,
      });
    }
  }

  const pending = await deps.countPendingDeliveries(event.id);
  if (pending === 0) {
    await deps.updateOutbox(event.id, {
      status: "completed",
      completed_at: nowIso,
      next_attempt_at: nowIso,
      last_error: null,
    });
  } else {
    const earliest = await deps.earliestPendingAt(event.id);
    await deps.updateOutbox(event.id, {
      status: "processing",
      next_attempt_at: earliest ?? nowIso,
      completed_at: null,
    });
  }
}

function repositoryDeps(admin: any): WorkerDeps {
  return {
    now: () => new Date(),
    listActiveSubscriptions: async (event) => {
      const preferenceField =
        event.event_type === "due_reminder"
          ? "due_reminders"
          : event.event_type === "installment_reminder"
          ? "installment_reminders"
          : event.event_type === "monthly_statement"
          ? "monthly_statements"
          : event.event_type === "manual"
          ? "manual_messages"
          : null;

      if (preferenceField) {
        const { data: preference, error: preferenceError } = await admin
          .from("customer_notification_preferences")
          .select(preferenceField)
          .eq("market_id", event.market_id)
          .eq("customer_id", event.customer_id)
          .maybeSingle();
        if (preferenceError) throw preferenceError;
        if (preference?.[preferenceField] === false) return [];
      }

      const { data, error } = await admin.from("customer_push_subscriptions")
        .select("id,endpoint,p256dh,auth,active")
        .eq("market_id", event.market_id)
        .eq("customer_id", event.customer_id)
        .eq("active", true);
      if (error) throw error;
      return (data ?? []) as WorkerSubscription[];
    },
    insertDeliveryIfMissing: async (outboxId, subscriptionId) => {
      const { error } = await admin.from("notification_deliveries").upsert({
        outbox_id: outboxId,
        subscription_id: subscriptionId,
        status: "pending",
      }, { onConflict: "outbox_id,subscription_id", ignoreDuplicates: true });
      if (error) throw error;
    },
    setFanoutAt: async (outboxId, iso) => {
      const { error } = await admin.from("notification_outbox")
        .update({ fanout_at: iso })
        .eq("id", outboxId)
        .is("fanout_at", null);
      if (error) throw error;
    },
    listDueDeliveries: async (outboxId, nowIso) => {
      const { data, error } = await admin.from("notification_deliveries")
        .select("id,subscription_id,status,attempt_count,next_attempt_at,customer_push_subscriptions(id,endpoint,p256dh,auth,active)")
        .eq("outbox_id", outboxId)
        .eq("status", "pending")
        .or(`next_attempt_at.is.null,next_attempt_at.lte.${nowIso}`);
      if (error) throw error;
      return (data ?? []).map((row: any) => ({
        id: row.id,
        subscription_id: row.subscription_id,
        status: row.status,
        attempt_count: Number(row.attempt_count ?? 0),
        next_attempt_at: row.next_attempt_at,
        subscription: Array.isArray(row.customer_push_subscriptions)
          ? row.customer_push_subscriptions[0]
          : row.customer_push_subscriptions,
      })).filter((row: WorkerDelivery) => row.subscription?.active === true);
    },
    sendPush: async (subscription, message) => {
      await webpush.sendNotification(
        {
          endpoint: subscription.endpoint,
          keys: { p256dh: subscription.p256dh, auth: subscription.auth },
        },
        JSON.stringify(message),
      );
    },
    updateDelivery: async (deliveryId, patch) => {
      const { error } = await admin.from("notification_deliveries")
        .update(patch).eq("id", deliveryId);
      if (error) throw error;
    },
    updateSubscription: async (subscriptionId, patch) => {
      const { error } = await admin.from("customer_push_subscriptions")
        .update(patch).eq("id", subscriptionId);
      if (error) throw error;
    },
    countPendingDeliveries: async (outboxId) => {
      const { count, error } = await admin.from("notification_deliveries")
        .select("id", { count: "exact", head: true })
        .eq("outbox_id", outboxId)
        .eq("status", "pending");
      if (error) throw error;
      return count ?? 0;
    },
    earliestPendingAt: async (outboxId) => {
      const { data, error } = await admin.from("notification_deliveries")
        .select("next_attempt_at,created_at")
        .eq("outbox_id", outboxId)
        .eq("status", "pending")
        .order("next_attempt_at", { ascending: true, nullsFirst: true })
        .limit(1);
      if (error) throw error;
      if (!data?.length) return null;
      return data[0].next_attempt_at ?? new Date().toISOString();
    },
    updateOutbox: async (outboxId, patch) => {
      const { error } = await admin.from("notification_outbox")
        .update(patch).eq("id", outboxId);
      if (error) throw error;
    },
  };
}

async function listReconcileCandidates(
  admin: any,
  fromIso: string,
  toIso: string,
  limit: number,
): Promise<ReconcileDebt[]> {
  const { data: debts, error: debtError } = await admin.from("debts")
    .select("id,customer_id,amount,amount_usd,currency,dollar_rate,is_deleted,custom_date,created_at")
    .eq("is_deleted", false)
    .gte("created_at", fromIso)
    .lte("created_at", toIso)
    .order("created_at", { ascending: true })
    .limit(limit);
  if (debtError) throw debtError;
  if (!debts?.length) return [];

  const debtIds = debts.map((row: any) => String(row.id));
  const customerIds = [...new Set(debts.map((row: any) => String(row.customer_id)).filter(Boolean))];
  const [legacyResult, syncResult, outboxResult, customerResult] = await Promise.all([
    admin.from("legacy_import_links")
      .select("target_id")
      .eq("entity_kind", "debt")
      .in("target_id", debtIds),
    admin.from("daftar_sync_seen")
      .select("target_id")
      .eq("entity_kind", "debt")
      .in("target_id", debtIds),
    admin.from("notification_outbox")
      .select("event_record_id")
      .eq("event_type", "debt_created")
      .in("event_record_id", debtIds),
    admin.from("profiles")
      .select("id,admin_id,role")
      .eq("role", "customer")
      .in("id", customerIds),
  ]);
  for (const result of [legacyResult, syncResult, outboxResult, customerResult]) {
    if (result.error) throw result.error;
  }

  const legacyIds = new Set((legacyResult.data ?? []).map((row: any) => String(row.target_id)));
  const syncIds = new Set((syncResult.data ?? []).map((row: any) => String(row.target_id)));
  const outboxIds = new Set((outboxResult.data ?? []).map((row: any) => String(row.event_record_id)));
  const customerMarket = new Map<string, string>();
  for (const row of customerResult.data ?? []) {
    customerMarket.set(String(row.id), String(row.admin_id ?? ""));
  }
  const marketIds = [...new Set([...customerMarket.values()].filter(Boolean))];

  const marketNames = new Map<string, string>();
  if (marketIds.length > 0) {
    const { data: markets, error: marketError } = await admin.from("profiles")
      .select("id,market_name")
      .eq("role", "admin")
      .in("id", marketIds);
    if (marketError) throw marketError;
    for (const row of markets ?? []) {
      marketNames.set(String(row.id), String(row.market_name ?? ""));
    }
  }

  const balances = new Map<string, number>();
  if (customerIds.length > 0) {
    const pageSize = 1000;
    let offset = 0;
    while (true) {
      const { data: rows, error } = await admin.from("debts")
        .select("customer_id,remaining")
        .in("customer_id", customerIds)
        .eq("is_deleted", false)
        .range(offset, offset + pageSize - 1);
      if (error) throw error;
      for (const row of rows ?? []) {
        const customerId = String(row.customer_id ?? "");
        const remaining = Number(row.remaining ?? 0);
        if (customerId && Number.isFinite(remaining) && remaining > 0) {
          balances.set(customerId, (balances.get(customerId) ?? 0) + remaining);
        }
      }
      if ((rows ?? []).length < pageSize) break;
      offset += pageSize;
    }
  }

  const result: ReconcileDebt[] = [];
  for (const row of debts) {
    const id = String(row.id);
    const customerId = String(row.customer_id ?? "");
    const marketId = customerMarket.get(customerId) ?? "";
    if (!customerId || !marketId) continue;
    result.push({
      id,
      marketId,
      customerId,
      marketName: marketNames.get(marketId) ?? "",
      amount: Number(row.amount ?? 0),
      amountUsd: Number(row.amount_usd ?? 0),
      currency: String(row.currency ?? "IQD"),
      dollarRate: Number(row.dollar_rate ?? 0),
      remainingIqd: balances.get(customerId) ?? 0,
      occurredAt: String(row.created_at ?? row.custom_date ?? ""),
      deleted: row.is_deleted === true,
      legacyLinked: legacyIds.has(id),
      syncLinked: syncIds.has(id),
      hasOutbox: outboxIds.has(id),
    });
  }
  return result;
}

function reconcileRepositoryDeps(admin: any): ReconcileDeps {
  return {
    now: () => new Date(),
    listCandidates: (fromIso, toIso, limit) =>
      listReconcileCandidates(admin, fromIso, toIso, limit),
    enqueuePush: async (event) => {
      const { error } = await admin.rpc("enqueue_customer_push_event_service", {
        p_market_id: event.marketId,
        p_customer_id: event.customerId,
        p_event_type: event.eventType,
        p_event_record_id: event.eventRecordId,
        p_idempotency_key: event.idempotencyKey,
        p_payload: event.payload,
      });
      if (error) throw error;
    },
  };
}

async function serve(req: Request): Promise<Response> {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL")!;
  const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? envJsonKey("SUPABASE_SECRET_KEYS");
  if (!url || !secret) return json({ error: "server_not_configured" }, 500);
  const admin = createClient(url, secret, { auth: { persistSession: false, autoRefreshToken: false } });

  let runtime;
  try {
    runtime = await loadOrInitializePushRuntime(admin);
  } catch (error) {
    console.error("customer-push runtime initialization failed", error instanceof Error ? error.message : String(error));
    return json({ error: "server_not_configured" }, 500);
  }

  if ((req.headers.get("x-zhirox-push-worker") ?? "") !== runtime.workerSecret) {
    return json({ error: "unauthorized" }, 401);
  }

  webpush.setVapidDetails(
    runtime.vapidSubject,
    runtime.vapidPublicKey,
    runtime.vapidPrivateKey,
  );

  let reconciled = 0;
  try {
    reconciled = await reconcileRecentDebts(reconcileRepositoryDeps(admin));
  } catch (error) {
    console.error("customer-push debt reconciliation failed", errorText(error));
  }

  const { data: claimed, error: claimError } = await admin.rpc(
    "claim_customer_push_outbox",
    { p_limit: 25 },
  );
  if (claimError) return json({ error: "claim_failed" }, 500);

  let processed = 0;
  const deps = repositoryDeps(admin);
  for (const raw of claimed ?? []) {
    const event = raw as WorkerEvent & { attempt_count?: number };
    try {
      await processOutboxEvent(event, deps);
      processed++;
    } catch (error) {
      const attemptCount = Number(event.attempt_count ?? 0) + 1;
      const terminal = attemptCount >= 5;
      await admin.from("notification_outbox").update({
        status: terminal ? "failed" : "pending",
        attempt_count: attemptCount,
        next_attempt_at: terminal
          ? new Date().toISOString()
          : new Date(Date.now() + 60_000).toISOString(),
        last_error: errorText(error),
        completed_at: terminal ? new Date().toISOString() : null,
      }).eq("id", event.id);
    }
  }

  return json({ ok: true, reconciled, processed });
}

if (import.meta.main) Deno.serve(serve);
