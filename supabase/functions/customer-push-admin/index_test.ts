import { assertEquals, assertRejects, assertStringIncludes } from "jsr:@std/assert@1";
import { sha256Hex } from "../_shared/customer_push/crypto.ts";
import { CUSTOMER_PUSH_STATIC_URL, routeCustomerPushLink } from "../customer-push-link/index.ts";
import {
  CUSTOMER_PUSH_PUBLIC_BASE_URL,
  handleAdminAction,
} from "./index.ts";

const actorId = "00000000-0000-0000-0000-000000000101";
const customerId = "00000000-0000-0000-0000-000000000121";
const requestId = "00000000-0000-0000-0000-000000000999";
const publicLinkBase = "https://push.zhirox.com/";
const gatewayBase = "https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/customer-push-link";

function deps(overrides: Record<string, unknown> = {}) {
  return {
    now: () => new Date("2026-09-17T00:00:00Z"),
    randomToken: () => "a".repeat(64),
    randomId: () => requestId,
    hash: sha256Hex,
    manageLink: async () => {},
    status: async () => ({
      active: false,
      device_count: 0,
      active_link_count: 1,
      latest_status: null,
      latest_at: null,
    }),
    revokeAll: async () => 0,
    getSettings: async () => ({ overdue_interval_days: 3 }),
    updateSettings: async ({ overdueIntervalDays }: any) => ({
      overdue_interval_days: overdueIntervalDays,
    }),
    sendManual: async () => ({
      campaign_id: requestId,
      queued_customers: 0,
      target_devices: 0,
      market_name: "ZHIROX Market",
    }),
    publicBaseUrl: publicLinkBase,
    ...overrides,
  } as any;
}

Deno.test("production QR links use the ZHIROX customer domain", () => {
  assertEquals(CUSTOMER_PUSH_PUBLIC_BASE_URL, publicLinkBase);
});

Deno.test("legacy Supabase QR gateway redirects to the ZHIROX customer domain", () => {
  const token = "a".repeat(64);
  const response = routeCustomerPushLink(
    new Request(`${gatewayBase}?token=${token}`),
  );
  assertEquals(response.status, 307);
  assertEquals(
    response.headers.get("location"),
    `${CUSTOMER_PUSH_STATIC_URL}?token=${token}`,
  );
});

Deno.test("create_link stores only token hash and has no expiry", async () => {
  let storedHash = "";
  let storedExpiresAt: string | null | undefined;
  const response = await handleAdminAction(
    { action: "create_link", customer_id: customerId },
    actorId,
    deps({
      manageLink: async ({ tokenHash, expiresAt }: any) => {
        storedHash = tokenHash;
        storedExpiresAt = expiresAt;
      },
    }),
  );

  assertEquals(storedHash, await sha256Hex("a".repeat(64)));
  assertEquals(storedExpiresAt, null);
  assertEquals(response.expires_at, null);
  assertEquals(
    response.url,
    `${publicLinkBase}?token=${"a".repeat(64)}`,
  );
});

Deno.test("status passes through active link count without secret material", async () => {
  const response = await handleAdminAction(
    { action: "status", customer_id: customerId },
    actorId,
    deps({
      status: async () => ({
        active: true,
        device_count: 2,
        active_link_count: 3,
        latest_status: "sent",
        latest_at: "2026-09-17T00:00:00Z",
      }),
    }),
  );

  assertEquals(response, {
    active: true,
    device_count: 2,
    active_link_count: 3,
    latest_status: "sent",
    latest_at: "2026-09-17T00:00:00Z",
  });
});

Deno.test("revoke_all returns revoked device count", async () => {
  const response = await handleAdminAction(
    { action: "revoke_all", customer_id: customerId },
    actorId,
    deps({ revokeAll: async () => 3 }),
  );
  assertEquals(response, { revoked_count: 3 });
});

Deno.test("send_manual queues one customer and never accepts a client title", async () => {
  let captured: Record<string, unknown> = {};
  const response = await handleAdminAction(
    {
      action: "send_manual",
      customer_id: customerId,
      message: "  کڕیارێکی بەڕێز، کاڵای نوێ گەیشت.  ",
      title: "spoofed title",
    },
    actorId,
    deps({
      sendManual: async (args: Record<string, unknown>) => {
        captured = args;
        return {
          campaign_id: requestId,
          queued_customers: 1,
          target_devices: 2,
          market_name: "کانی چنار",
        };
      },
    }),
  );

  assertEquals(captured, {
    actorId,
    customerId,
    message: "کڕیارێکی بەڕێز، کاڵای نوێ گەیشت.",
    requestId,
  });
  assertEquals(response, {
    campaign_id: requestId,
    queued_customers: 1,
    target_devices: 2,
    market_name: "کانی چنار",
  });
});

Deno.test("broadcast_manual does not require a customer id", async () => {
  let captured: Record<string, unknown> = {};
  const response = await handleAdminAction(
    {
      action: "broadcast_manual",
      message: "ئەمڕۆ تا کاتژمێر 11 کراوەین.",
    },
    actorId,
    deps({
      sendManual: async (args: Record<string, unknown>) => {
        captured = args;
        return {
          campaign_id: requestId,
          queued_customers: 18,
          target_devices: 23,
          market_name: "کانی چنار",
        };
      },
    }),
  );

  assertEquals(captured, {
    actorId,
    customerId: null,
    message: "ئەمڕۆ تا کاتژمێر 11 کراوەین.",
    requestId,
  });
  assertEquals(response, {
    campaign_id: requestId,
    queued_customers: 18,
    target_devices: 23,
    market_name: "کانی چنار",
  });
});

Deno.test("notification interval settings can be read and updated", async () => {
  assertEquals(
    await handleAdminAction(
      { action: "get_settings" },
      actorId,
      deps({ getSettings: async () => ({ overdue_interval_days: 5 }) }),
    ),
    { overdue_interval_days: 5 },
  );

  let captured = 0;
  assertEquals(
    await handleAdminAction(
      { action: "update_settings", overdue_interval_days: 7 },
      actorId,
      deps({
        updateSettings: async ({ overdueIntervalDays }: any) => {
          captured = overdueIntervalDays;
          return { overdue_interval_days: overdueIntervalDays };
        },
      }),
    ),
    { overdue_interval_days: 7 },
  );
  assertEquals(captured, 7);
});

Deno.test("notification interval rejects values outside 1-30 days", async () => {
  await assertRejects(
    () => handleAdminAction(
      { action: "update_settings", overdue_interval_days: 0 },
      actorId,
      deps(),
    ),
    Error,
    "invalid_overdue_interval",
  );
  await assertRejects(
    () => handleAdminAction(
      { action: "update_settings", overdue_interval_days: 31 },
      actorId,
      deps(),
    ),
    Error,
    "invalid_overdue_interval",
  );
});

Deno.test("manual push rejects empty and oversized messages", async () => {
  await assertRejects(
    () => handleAdminAction(
      { action: "send_manual", customer_id: customerId, message: "   " },
      actorId,
      deps(),
    ),
    Error,
    "invalid_message",
  );

  await assertRejects(
    () => handleAdminAction(
      { action: "broadcast_manual", message: "x".repeat(241) },
      actorId,
      deps(),
    ),
    Error,
    "invalid_message",
  );
});
