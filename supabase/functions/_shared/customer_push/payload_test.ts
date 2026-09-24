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

Deno.test("payment notification uses supermarket name as title", () => {
  assertEquals(
    formatPushBody("payment_created", {
      amount: 25000,
      currency: "IQD",
      remaining_iqd: 100000,
      market_name: "ZHIROX Market",
      occurred_at: "2026-09-17T00:00:00Z",
    }),
    {
      title: "ZHIROX Market",
      body:
        "💰 پارەدانەوە تۆمارکرا • بڕی دراو: 25,000 د.ع • ماوە: 100,000 د.ع • کلیک بکە بۆ پسووڵە/کەشفی حیساب",
    },
  );
});

Deno.test("due reminder preserves reminder wording and supermarket title", () => {
  assertEquals(
    formatPushBody("due_reminder", {
      amount: 50000,
      currency: "IQD",
      remaining_iqd: 75000,
      market_name: "کانی چنار",
      occurred_at: "2026-09-17T00:00:00Z",
      due_date: "2026-09-16",
      overdue: true,
      days_overdue: 7,
    }),
    {
      title: "کانی چنار",
      body:
        "⚠️ قەرزەکەت 7 ڕۆژ دوا کەوتووە • بڕی دواخراو: 50,000 د.ع • کۆی ماوە: 75,000 د.ع",
    },
  );
});

Deno.test("fully settled payment uses a distinct cheerful notification", () => {
  assertEquals(
    formatPushBody("payment_created", {
      amount: 25000,
      currency: "IQD",
      remaining_iqd: 0,
      market_name: "کانی چنار",
      occurred_at: "2026-09-24T00:00:00Z",
    }),
    {
      title: "کانی چنار",
      body:
        "✅ قەرزەکانت بە تەواوی دراونەتەوە 🎉 • بڕی وەرگیراو: 25,000 د.ع • کلیک بکە بۆ پسووڵە",
    },
  );
});

Deno.test("installment and monthly statement notifications have dedicated copy", () => {
  assertEquals(
    formatPushBody("installment_reminder", {
      amount: 50000,
      currency: "IQD",
      installment_no: 2,
      market_name: "کانی چنار",
      occurred_at: "2026-09-24T00:00:00Z",
      overdue: false,
    }).body,
    "📅 بیرخستنەوەی قسطی 2 • بڕ: 50,000 د.ع",
  );
  assertEquals(
    formatPushBody("monthly_statement", {
      market_name: "کانی چنار",
      occurred_at: "2026-09-24T00:00:00Z",
      period: "2026-08",
      total_debt: 100000,
      total_paid: 40000,
      remaining_iqd: 60000,
    }).body,
    "📄 کەشفی حیسابی مانگی 2026-08 ئامادەیە • کۆی قەرزی نوێ: 100,000 د.ع • پارەدان: 40,000 د.ع • ماوە: 60,000 د.ع",
  );
});

Deno.test("manual notification uses supermarket name and manager message", () => {
  assertEquals(
    formatPushBody("manual", {
      market_name: "کانی چنار",
      message: "سبەی فرۆشگاکە تا کاتژمێر 10 داخراوە.",
      occurred_at: "2026-09-17T00:00:00Z",
    }),
    {
      title: "کانی چنار",
      body: "سبەی فرۆشگاکە تا کاتژمێر 10 داخراوە.",
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
