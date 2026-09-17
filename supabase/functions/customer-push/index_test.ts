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
      expires_at: "2026-09-17T00:15:00Z",
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

Deno.test("validate exposes only display data and VAPID public key", async () => {
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
    expires_at: "2026-09-17T00:15:00Z",
    vapid_public_key: "BTestPublicKey",
  });
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

Deno.test("expired token returns generic unavailable error", async () => {
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
