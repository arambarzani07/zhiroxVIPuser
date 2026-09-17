import { assertEquals } from "jsr:@std/assert@1";
import {
  processOutboxEvent,
  type WorkerDelivery,
  type WorkerDeps,
  type WorkerEvent,
  type WorkerSubscription,
} from "./index.ts";

const subA: WorkerSubscription = {
  id: "sub-a", endpoint: "https://push.example/a", p256dh: "p-a", auth: "a-a", active: true,
};
const subB: WorkerSubscription = {
  id: "sub-b", endpoint: "https://push.example/b", p256dh: "p-b", auth: "a-b", active: true,
};
const subC: WorkerSubscription = {
  id: "sub-c", endpoint: "https://push.example/c", p256dh: "p-c", auth: "a-c", active: true,
};

const baseEvent = (): WorkerEvent => ({
  id: "event-1",
  market_id: "market-1",
  customer_id: "customer-1",
  event_type: "debt_created",
  payload: {
    amount: 1000,
    currency: "IQD",
    remaining_iqd: 5000,
    market_name: "Market A",
    occurred_at: "2026-09-17T00:00:00Z",
  },
  fanout_at: null,
});

function fakeWorker(options: {
  subscriptions?: WorkerSubscription[];
  sendStatus?: number;
} = {}) {
  const subscriptions = [...(options.subscriptions ?? [subA, subB])];
  const deliveries: WorkerDelivery[] = [];
  const outboxPatches: Record<string, unknown>[] = [];
  const subscriptionPatches = new Map<string, Record<string, unknown>>();
  let fanoutAt: string | null = null;

  const deps: WorkerDeps = {
    now: () => new Date("2026-09-17T00:00:00Z"),
    listActiveSubscriptions: async () => subscriptions.filter((s) => s.active),
    insertDeliveryIfMissing: async (_outboxId, subscriptionId) => {
      if (deliveries.some((d) => d.subscription_id === subscriptionId)) return;
      const subscription = subscriptions.find((s) => s.id === subscriptionId)!;
      deliveries.push({
        id: `delivery-${subscriptionId}`,
        subscription_id: subscriptionId,
        status: "pending",
        attempt_count: 0,
        next_attempt_at: null,
        subscription,
      });
    },
    setFanoutAt: async (_outboxId, iso) => { fanoutAt = iso; },
    listDueDeliveries: async () => deliveries.filter((d) => d.status === "pending"),
    sendPush: async () => {
      if (options.sendStatus) throw { statusCode: options.sendStatus, message: `HTTP ${options.sendStatus}` };
    },
    updateDelivery: async (deliveryId, patch) => {
      const delivery = deliveries.find((d) => d.id === deliveryId)!;
      Object.assign(delivery, patch);
    },
    updateSubscription: async (subscriptionId, patch) => {
      const subscription = subscriptions.find((s) => s.id === subscriptionId)!;
      Object.assign(subscription, patch);
      subscriptionPatches.set(subscriptionId, patch);
    },
    countPendingDeliveries: async () => deliveries.filter((d) => d.status === "pending").length,
    earliestPendingAt: async () => {
      const pending = deliveries.find((d) => d.status === "pending");
      return pending?.next_attempt_at ?? null;
    },
    updateOutbox: async (_outboxId, patch) => { outboxPatches.push(patch); },
  };

  return { deps, subscriptions, deliveries, outboxPatches, subscriptionPatches, get fanoutAt() { return fanoutAt; } };
}

Deno.test("fanout is frozen after first processing", async () => {
  const repo = fakeWorker();
  const event = baseEvent();
  await processOutboxEvent(event, repo.deps);
  repo.subscriptions.push(subC);
  await processOutboxEvent(event, repo.deps);
  assertEquals(
    repo.deliveries.map((d) => d.subscription_id).sort(),
    [subA.id, subB.id].sort(),
  );
});

Deno.test("410 expires subscription without retry", async () => {
  const repo = fakeWorker({ subscriptions: [{ ...subA }], sendStatus: 410 });
  const event = baseEvent();
  await processOutboxEvent(event, repo.deps);
  assertEquals(repo.deliveries[0].status, "expired");
  assertEquals(repo.subscriptions[0].active, false);
  assertEquals(repo.outboxPatches.at(-1)?.status, "completed");
});

Deno.test("transient failure schedules bounded retry", async () => {
  const repo = fakeWorker({ subscriptions: [{ ...subA }], sendStatus: 503 });
  const event = baseEvent();
  await processOutboxEvent(event, repo.deps);
  assertEquals(repo.deliveries[0].status, "pending");
  assertEquals(repo.deliveries[0].attempt_count, 1);
  assertEquals(repo.deliveries[0].next_attempt_at, "2026-09-17T00:01:00.000Z");
  assertEquals(repo.outboxPatches.at(-1)?.status, "processing");
});

Deno.test("zero-device event completes", async () => {
  const repo = fakeWorker({ subscriptions: [] });
  const event = baseEvent();
  await processOutboxEvent(event, repo.deps);
  assertEquals(repo.deliveries.length, 0);
  assertEquals(repo.outboxPatches.at(-1)?.status, "completed");
});
