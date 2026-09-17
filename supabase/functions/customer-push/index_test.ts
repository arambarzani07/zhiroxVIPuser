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
    redeem: async () => ({ linked: true }),
    unsubscribe: async () => true,
    consumeRateLimit: async () => true,
    ...overrides,
  };
}

Deno.test("token page never embeds raw customer id", async () => {
  const res = await routeCustomerPush(
    new Request(`https://x/functions/v1/customer-push?token=${token}`),
    deps(),
  );
  const html = await res.text();
  assertEquals(res.status, 200);
  assertEquals(html.includes("customer_id"), false);
  assertEquals(html.includes("چالاککردنی ئاگادارکردنەوە"), true);
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
