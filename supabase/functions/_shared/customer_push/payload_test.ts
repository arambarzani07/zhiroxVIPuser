import { assertEquals, assertMatch } from "jsr:@std/assert@1";
import { randomHexToken, sha256Hex } from "./crypto.ts";
import {
  classifyPushFailure,
  formatPushBody,
  retryDelayAfterFailure,
} from "./payload.ts";

Deno.test("token is 32 bytes as 64 hex chars", () => {
  assertMatch(randomHexToken(), /^[a-f0-9]{64}$/);
});

Deno.test("sha256 is stable", async () => {
  assertEquals(
    await sha256Hex("zhirox"),
    "2e324e6d0fcf6fd0f7759accb3979ec739e4dc9830b509e7fe03778b2a8b9067",
  );
});

Deno.test("retry schedule stops after failed attempt five", () => {
  assertEquals(
    [1, 2, 3, 4, 5].map(retryDelayAfterFailure),
    [60, 300, 1800, 7200, null],
  );
});

Deno.test("payment copy uses IQD remaining balance", () => {
  assertEquals(
    formatPushBody("payment_created", {
      amount: 25000,
      currency: "IQD",
      remaining_iqd: 100000,
      market_name: "ZHIROX Market",
      occurred_at: "2026-09-17T00:00:00Z",
    }),
    {
      title: "💰 پارەدانەوە تۆمارکرا",
      body:
        "بڕی دراو: 25,000 د.ع • ماوە: 100,000 د.ع • مارکێت: ZHIROX Market",
    },
  );
});

Deno.test("push status classification", () => {
  assertEquals(classifyPushFailure(410), "expired");
  assertEquals(classifyPushFailure(404), "expired");
  assertEquals(classifyPushFailure(429), "retry");
  assertEquals(classifyPushFailure(503), "retry");
  assertEquals(classifyPushFailure(400), "failed");
});
