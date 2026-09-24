import { assertEquals } from "jsr:@std/assert@1";
import { routeCustomerPush, type PublicPushDeps } from "./index.ts";
import { sha256Hex } from "../_shared/customer_push/crypto.ts";

const token = "a".repeat(64);

function deps(overrides: Partial<PublicPushDeps> = {}): PublicPushDeps {
  return {
    hash: sha256Hex,
    randomToken: () => "d".repeat(64),
    vapidPublicKey: "BTestPublicKey",
    rateLimitSalt: "rate-salt",
    inspect: async () => ({
      customer_name: "Customer A",
      market_name: "Market A",
      expires_at: null,
    }),
    portal: async () => ({
      customer_name: "Customer A",
      market_name: "Market A",
      debt_limit: 100000,
      can_subscribe: true,
      totals: [{ currency: "IQD", total_debt: 50000, remaining: 30000, paid: 20000 }],
      rows: [],
      has_more: false,
    }),
    receipt: async (args) => ({
      id: args.receiptId,
      receipt_number: "R-100",
      market_name: "Market A",
      customer_name: "Customer A",
      source_type: "payment",
      source: { kind: "payment", amount: 2500, currency: "IQD" },
      settings: {},
    }),
    notificationHistory: async () => ({
      items: [{
        id: "00000000-0000-0000-0000-000000000123",
        event_type: "payment_created",
        status: "sent",
        created_at: "2026-09-18T08:30:00Z",
        message: null,
        amount: 2500,
        currency: "IQD",
      }],
      limit: 20,
    }),
    preferences: async () => ({
      mandatory_financial: true,
      due_reminders: true,
      installment_reminders: true,
      monthly_statements: true,
      manual_messages: true,
    }),
    updatePreferences: async (args) => ({
      mandatory_financial: true,
      due_reminders: args.dueReminders,
      installment_reminders: args.installmentReminders,
      monthly_statements: args.monthlyStatements,
      manual_messages: args.manualMessages,
    }),
    markNotification: async (args) => ({
      id: args.notificationId,
      read_at: "2026-09-24T09:00:00Z",
      acknowledged_at: args.acknowledge ? "2026-09-24T09:00:00Z" : null,
      requires_ack: true,
    }),
    redeem: async () => ({ linked: true }),
    unsubscribe: async () => true,
    consumeRateLimit: async () => true,
    ...overrides,
  };
}

Deno.test("legacy token GET redirects to custom domain without changing token", async () => {
  const res = await routeCustomerPush(
    new Request(`https://x/functions/v1/customer-push?token=${token}`),
    deps(),
  );
  assertEquals(res.status, 307);
  assertEquals(res.headers.get("location"), `https://push.zhirox.com/?token=${token}`);
});

Deno.test("legacy generic GET redirects to custom domain", async () => {
  const res = await routeCustomerPush(
    new Request("https://x/functions/v1/customer-push"),
    deps(),
  );
  assertEquals(res.status, 307);
  assertEquals(res.headers.get("location"), "https://push.zhirox.com/");
});

Deno.test("public API preflight allows JSON POST", async () => {
  const res = await routeCustomerPush(
    new Request("https://x/functions/v1/customer-push", {
      method: "OPTIONS",
      headers: {
        origin: "https://push.zhirox.com",
        "access-control-request-method": "POST",
        "access-control-request-headers": "content-type",
      },
    }),
    deps(),
  );
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("access-control-allow-origin"), "*");
  assertEquals(res.headers.get("access-control-allow-methods")?.includes("POST"), true);
  assertEquals(res.headers.get("access-control-allow-headers")?.includes("content-type"), true);
});

Deno.test("subscribe rejects missing PushSubscription keys", async () => {
  const res = await routeCustomerPush(
    new Request("https://x/functions/v1/customer-push", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ action: "subscribe", token, subscription: {} }),
    }),
    deps(),
  );
  assertEquals(res.status, 400);
  assertEquals(await res.json(), { error: "invalid_subscription" });
});

Deno.test("validate exposes permanent display data and VAPID public key", async () => {
  const res = await routeCustomerPush(
    new Request("https://x/functions/v1/customer-push", {
      method: "POST",
      headers: { "content-type": "application/json", "cf-connecting-ip": "1.2.3.4" },
      body: JSON.stringify({ action: "validate", token }),
    }),
    deps(),
  );
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("content-type")?.includes("application/json"), true);
  assertEquals(res.headers.get("access-control-allow-origin"), "*");
  assertEquals(await res.json(), {
    customer_name: "Customer A",
    market_name: "Market A",
    expires_at: null,
    vapid_public_key: "BTestPublicKey",
  });
});

Deno.test("the same permanent token can be validated repeatedly", async () => {
  let inspectCalls = 0;
  const testDeps = deps({
    inspect: async () => {
      inspectCalls++;
      return {
        customer_name: "Customer A",
        market_name: "Market A",
        expires_at: null,
      };
    },
  });

  for (let index = 0; index < 2; index++) {
    const res = await routeCustomerPush(
      new Request("https://x/functions/v1/customer-push", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ action: "validate", token }),
      }),
      testDeps,
    );
    assertEquals(res.status, 200);
  }
  assertEquals(inspectCalls, 2);
});

Deno.test("subscribe returns device secret once after redeem", async () => {
  let receivedSecretHash = "";
  const res = await routeCustomerPush(
    new Request("https://x/functions/v1/customer-push", {
      method: "POST",
      headers: { "content-type": "application/json", "user-agent": "test" },
      body: JSON.stringify({
        action: "subscribe",
        token,
        platform: "ios",
        subscription: {
          endpoint: "https://push.example/device",
          keys: { p256dh: "p-key", auth: "a-key" },
        },
      }),
    }),
    deps({
      redeem: async (args) => {
        receivedSecretHash = args.deviceSecretHash;
        return {};
      },
    }),
  );
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { linked: true, device_secret: "d".repeat(64) });
  assertEquals(receivedSecretHash, await sha256Hex("d".repeat(64)));
});

Deno.test("portal can authenticate with the same link token", async () => {
  const res = await routeCustomerPush(
    new Request("https://x/functions/v1/customer-push", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ action: "portal", token }),
    }),
    deps(),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.customer_name, "Customer A");
  assertEquals(body.totals[0].remaining, 30000);
  assertEquals(body.vapid_public_key, "BTestPublicKey");
});

Deno.test("portal can reopen from installed app using device credentials", async () => {
  let receivedHash = "";
  const secret = "b".repeat(64);
  const res = await routeCustomerPush(
    new Request("https://x/functions/v1/customer-push", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ action: "portal", endpoint: "https://push.example/device", device_secret: secret }),
    }),
    deps({ portal: async (args) => { receivedHash = args.deviceSecretHash ?? ""; return { rows: [], totals: [] }; } }),
  );
  assertEquals(res.status, 200);
  assertEquals(receivedHash, await sha256Hex(secret));
});

Deno.test("secure receipt can be opened with the same portal token", async () => {
  const receiptId = "00000000-0000-4000-8000-000000000456";
  const res = await routeCustomerPush(
    new Request("https://x/functions/v1/customer-push", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        action: "receipt",
        token,
        receipt_id: receiptId,
      }),
    }),
    deps(),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.id, receiptId);
  assertEquals(body.receipt_number, "R-100");
  assertEquals(body.customer_name, "Customer A");
});

Deno.test("notification history can authenticate with permanent token", async () => {
  let receivedHash = "";
  const res = await routeCustomerPush(
    new Request("https://x/functions/v1/customer-push", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ action: "notifications", token, limit: 10 }),
    }),
    deps({
      notificationHistory: async (args) => {
        receivedHash = args.tokenHash ?? "";
        return { items: [{ event_type: "manual", status: "sent" }], limit: args.limit };
      },
    }),
  );
  assertEquals(res.status, 200);
  assertEquals(receivedHash, await sha256Hex(token));
  assertEquals(await res.json(), {
    items: [{ event_type: "manual", status: "sent" }],
    limit: 10,
  });
});

Deno.test("notification history can reopen with device credentials", async () => {
  let receivedHash = "";
  const secret = "b".repeat(64);
  const res = await routeCustomerPush(
    new Request("https://x/functions/v1/customer-push", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        action: "notifications",
        endpoint: "https://push.example/device",
        device_secret: secret,
      }),
    }),
    deps({
      notificationHistory: async (args) => {
        receivedHash = args.deviceSecretHash ?? "";
        return { items: [], limit: args.limit };
      },
    }),
  );
  assertEquals(res.status, 200);
  assertEquals(receivedHash, await sha256Hex(secret));
});


Deno.test("notification preferences can be read and updated with device credentials", async () => {
  const secret = "b".repeat(64);
  const readRes = await routeCustomerPush(
    new Request("https://x/functions/v1/customer-push", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        action: "preferences",
        endpoint: "https://push.example/device",
        device_secret: secret,
      }),
    }),
    deps(),
  );
  assertEquals(readRes.status, 200);
  assertEquals((await readRes.json()).mandatory_financial, true);

  const updateRes = await routeCustomerPush(
    new Request("https://x/functions/v1/customer-push", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        action: "update_preferences",
        endpoint: "https://push.example/device",
        device_secret: secret,
        due_reminders: false,
        installment_reminders: true,
        monthly_statements: false,
        manual_messages: true,
      }),
    }),
    deps(),
  );
  assertEquals(updateRes.status, 200);
  assertEquals(await updateRes.json(), {
    mandatory_financial: true,
    due_reminders: false,
    installment_reminders: true,
    monthly_statements: false,
    manual_messages: true,
  });
});

Deno.test("notification can be marked read or acknowledged without exposing customer identity", async () => {
  const notificationId = "00000000-0000-4000-8000-000000000123";
  const read = await routeCustomerPush(
    new Request("https://x/functions/v1/customer-push", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        action: "mark_read",
        token,
        notification_id: notificationId,
      }),
    }),
    deps(),
  );
  assertEquals(read.status, 200);
  assertEquals((await read.json()).acknowledged_at, null);

  const ack = await routeCustomerPush(
    new Request("https://x/functions/v1/customer-push", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        action: "acknowledge",
        token,
        notification_id: notificationId,
      }),
    }),
    deps(),
  );
  assertEquals(ack.status, 200);
  assertEquals((await ack.json()).acknowledged_at, "2026-09-24T09:00:00Z");
});

Deno.test("revoked or unavailable token returns generic error", async () => {
  const res = await routeCustomerPush(
    new Request("https://x/functions/v1/customer-push", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ action: "validate", token }),
    }),
    deps({ inspect: async () => { throw new Error("no_data_found"); } }),
  );
  assertEquals(res.status, 404);
  assertEquals(await res.json(), { error: "link_unavailable" });
});
