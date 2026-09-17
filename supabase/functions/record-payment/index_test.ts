import { assertEquals } from "jsr:@std/assert@1";
import {
  canonicalPaymentId,
  finalizePaymentPush,
} from "./index.ts";

const paymentIdA = "00000000-0000-0000-0000-000000000401";
const paymentIdB = "00000000-0000-0000-0000-000000000402";
const paymentIdC = "00000000-0000-0000-0000-000000000403";
const customerId = "00000000-0000-0000-0000-000000000121";
const marketId = "00000000-0000-0000-0000-000000000101";
const debtId = "00000000-0000-0000-0000-000000000301";

Deno.test("canonical payment id handles single and customer-wide results", () => {
  assertEquals(canonicalPaymentId({ id: paymentIdA }), paymentIdA);
  assertEquals(
    canonicalPaymentId({ payments: [{ id: paymentIdB }, { id: paymentIdC }] }),
    paymentIdB,
  );
});

Deno.test("customer-wide payment enqueues one event using total action amount", async () => {
  let enqueued: Record<string, unknown> | null = null;
  const paymentResult = {
    customer_id: customerId,
    amount: 25000,
    remaining: 100000,
    payments: [{ id: paymentIdB }, { id: paymentIdC }],
  };

  const returned = await finalizePaymentPush(
    paymentResult,
    { debtId: "", customerId, amount: 25000 },
    {
      now: () => new Date("2026-09-17T00:00:00Z"),
      loadContext: async () => ({
        customerId,
        marketId,
        marketName: "ZHIROX Market",
        currency: "IQD",
        dollarRate: 0,
        remainingIqd: 100000,
      }),
      enqueuePush: async (args) => {
        enqueued = args;
      },
      reportError: () => {},
    },
  );

  assertEquals(returned, paymentResult);
  assertEquals(enqueued, {
    marketId,
    customerId,
    eventType: "payment_created",
    eventRecordId: paymentIdB,
    idempotencyKey: `payment_created:${paymentIdB}`,
    payload: {
      amount: 25000,
      currency: "IQD",
      remaining_iqd: 100000,
      market_name: "ZHIROX Market",
      occurred_at: "2026-09-17T00:00:00.000Z",
    },
  });
});

Deno.test("debt-specific USD payment converts stored IQD amount for push copy", async () => {
  let enqueued: Record<string, unknown> | null = null;
  const paymentResult = { id: paymentIdA, debt_id: debtId, amount: 150000 };

  await finalizePaymentPush(
    paymentResult,
    { debtId, customerId: "", amount: 150000 },
    {
      now: () => new Date("2026-09-17T00:00:00Z"),
      loadContext: async () => ({
        customerId,
        marketId,
        marketName: "ZHIROX Market",
        currency: "USD",
        dollarRate: 1500,
        remainingIqd: 300000,
      }),
      enqueuePush: async (args) => {
        enqueued = args;
      },
      reportError: () => {},
    },
  );

  assertEquals((enqueued?.payload as Record<string, unknown>).amount, 100);
  assertEquals((enqueued?.payload as Record<string, unknown>).currency, "USD");
});

Deno.test("push enqueue failure never fails a successful payment result", async () => {
  const paymentResult = { id: paymentIdA, debt_id: debtId, amount: 1000 };
  let reported = "";

  const returned = await finalizePaymentPush(
    paymentResult,
    { debtId, customerId: "", amount: 1000 },
    {
      now: () => new Date("2026-09-17T00:00:00Z"),
      loadContext: async () => ({
        customerId,
        marketId,
        marketName: "ZHIROX Market",
        currency: "IQD",
        dollarRate: 0,
        remainingIqd: 9000,
      }),
      enqueuePush: async () => {
        throw new Error("push unavailable");
      },
      reportError: (message) => {
        reported = message;
      },
    },
  );

  assertEquals(returned, paymentResult);
  assertEquals(reported.includes("push unavailable"), true);
});
