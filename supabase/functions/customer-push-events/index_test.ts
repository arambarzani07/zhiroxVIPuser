import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  handleDebtPushAction,
  isLiveDebtEligible,
  type DebtPushContext,
} from "./index.ts";

const actorId = "00000000-0000-0000-0000-000000000101";
const marketId = "00000000-0000-0000-0000-000000000101";
const customerId = "00000000-0000-0000-0000-000000000121";
const debtId = "00000000-0000-0000-0000-000000000301";

function liveDebt(overrides: Partial<DebtPushContext> = {}): DebtPushContext {
  return {
    id: debtId,
    customerId,
    createdBy: actorId,
    marketId,
    marketName: "ZHIROX Market",
    amount: 150000,
    amountUsd: 100,
    currency: "USD",
    dollarRate: 1500,
    remainingIqd: 300000,
    occurredAt: "2026-09-17T00:00:00.000Z",
    deleted: false,
    legacyLinked: false,
    syncLinked: false,
    ...overrides,
  };
}

Deno.test("reconciliation eligibility excludes deleted imported synced recent and stale rows", () => {
  const now = new Date("2026-09-17T01:00:00Z");
  assertEquals(isLiveDebtEligible({
    deleted: false,
    legacyLinked: false,
    syncLinked: false,
    createdAt: "2026-09-17T00:30:00Z",
    now,
  }), true);
  assertEquals(isLiveDebtEligible({
    deleted: true,
    legacyLinked: false,
    syncLinked: false,
    createdAt: "2026-09-17T00:30:00Z",
    now,
  }), false);
  assertEquals(isLiveDebtEligible({
    deleted: false,
    legacyLinked: true,
    syncLinked: false,
    createdAt: "2026-09-17T00:30:00Z",
    now,
  }), false);
  assertEquals(isLiveDebtEligible({
    deleted: false,
    legacyLinked: false,
    syncLinked: true,
    createdAt: "2026-09-17T00:30:00Z",
    now,
  }), false);
  assertEquals(isLiveDebtEligible({
    deleted: false,
    legacyLinked: false,
    syncLinked: false,
    createdAt: "2026-09-17T00:59:30Z",
    now,
  }), false);
  assertEquals(isLiveDebtEligible({
    deleted: false,
    legacyLinked: false,
    syncLinked: false,
    createdAt: "2026-09-15T00:00:00Z",
    now,
  }), false);
});

Deno.test("live debt creates one idempotent debt_created event", async () => {
  const captured: Record<string, unknown>[] = [];
  const result = await handleDebtPushAction(
    { action: "enqueue_debt", debt_id: debtId },
    actorId,
    {
      loadDebt: async () => liveDebt(),
      actorCanAccess: async () => true,
      enqueuePush: async (args) => captured.push(args),
    },
  );

  assertEquals(result, { enqueued: true });
  assertEquals(captured, [{
    marketId,
    customerId,
    eventType: "debt_created",
    eventRecordId: debtId,
    idempotencyKey: `debt_created:${debtId}`,
    payload: {
      amount: 100,
      currency: "USD",
      remaining_iqd: 300000,
      market_name: "ZHIROX Market",
      occurred_at: "2026-09-17T00:00:00.000Z",
    },
  }]);
});

Deno.test("legacy and sync debts are ignored", async () => {
  for (const debt of [
    liveDebt({ legacyLinked: true }),
    liveDebt({ syncLinked: true }),
  ]) {
    let called = false;
    const result = await handleDebtPushAction(
      { action: "enqueue_debt", debt_id: debtId },
      actorId,
      {
        loadDebt: async () => debt,
        actorCanAccess: async () => true,
        enqueuePush: async () => {
          called = true;
        },
      },
    );
    assertEquals(result, { enqueued: false, reason: "non_live_source" });
    assertEquals(called, false);
  }
});

Deno.test("wrong creator and cross-tenant actor are rejected", async () => {
  await assertRejects(
    () => handleDebtPushAction(
      { action: "enqueue_debt", debt_id: debtId },
      actorId,
      {
        loadDebt: async () => liveDebt({ createdBy: "00000000-0000-0000-0000-000000000999" }),
        actorCanAccess: async () => true,
        enqueuePush: async () => {},
      },
    ),
    Error,
    "forbidden",
  );

  await assertRejects(
    () => handleDebtPushAction(
      { action: "enqueue_debt", debt_id: debtId },
      actorId,
      {
        loadDebt: async () => liveDebt(),
        actorCanAccess: async () => false,
        enqueuePush: async () => {},
      },
    ),
    Error,
    "forbidden",
  );
});
