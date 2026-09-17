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
        url: "/functions/v1/customer-push",
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

  return json({ ok: true, processed });
}

if (import.meta.main) Deno.serve(serve);
