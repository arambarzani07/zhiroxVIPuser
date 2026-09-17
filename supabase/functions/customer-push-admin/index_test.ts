import { assertEquals } from "jsr:@std/assert@1";
import { sha256Hex } from "../_shared/customer_push/crypto.ts";
import {
  CUSTOMER_PUSH_PUBLIC_BASE_URL,
  handleAdminAction,
} from "./index.ts";

const actorId = "00000000-0000-0000-0000-000000000101";
const customerId = "00000000-0000-0000-0000-000000000121";

Deno.test("production QR links use the canonical push domain", () => {
  assertEquals(CUSTOMER_PUSH_PUBLIC_BASE_URL, "https://push.zhirox.com/");
});

Deno.test("create_link stores only token hash and has no expiry", async () => {
  let storedHash = "";
  let storedExpiresAt: string | null | undefined;
  const response = await handleAdminAction(
    { action: "create_link", customer_id: customerId },
    actorId,
    {
      now: () => new Date("2026-09-17T00:00:00Z"),
      randomToken: () => "a".repeat(64),
      hash: sha256Hex,
      manageLink: async ({ tokenHash, expiresAt }) => {
        storedHash = tokenHash;
        storedExpiresAt = expiresAt;
      },
      status: async () => ({
        active: false,
        device_count: 0,
        active_link_count: 1,
        latest_status: null,
        latest_at: null,
      }),
      revokeAll: async () => 0,
      publicBaseUrl: "https://push.zhirox.com/",
    },
  );

  assertEquals(storedHash, await sha256Hex("a".repeat(64)));
  assertEquals(storedExpiresAt, null);
  assertEquals(response.expires_at, null);
  assertEquals(
    response.url,
    `https://push.zhirox.com/?token=${"a".repeat(64)}`,
  );
});

Deno.test("status passes through active link count without secret material", async () => {
  const response = await handleAdminAction(
    { action: "status", customer_id: customerId },
    actorId,
    {
      now: () => new Date(),
      randomToken: () => "b".repeat(64),
      hash: sha256Hex,
      manageLink: async () => {},
      status: async () => ({
        active: true,
        device_count: 2,
        active_link_count: 3,
        latest_status: "sent",
        latest_at: "2026-09-17T00:00:00Z",
      }),
      revokeAll: async () => 0,
      publicBaseUrl: "https://push.zhirox.com/",
    },
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
    {
      now: () => new Date(),
      randomToken: () => "c".repeat(64),
      hash: sha256Hex,
      manageLink: async () => {},
      status: async () => ({}),
      revokeAll: async () => 3,
      publicBaseUrl: "https://example.test/customer-push",
    },
  );
  assertEquals(response, { revoked_count: 3 });
});
