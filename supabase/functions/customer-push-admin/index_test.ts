import { assertEquals } from "jsr:@std/assert@1";
import { sha256Hex } from "../_shared/customer_push/crypto.ts";
import { handleAdminAction } from "./index.ts";

const actorId = "00000000-0000-0000-0000-000000000101";
const customerId = "00000000-0000-0000-0000-000000000121";

Deno.test("create_link stores only token hash and expires in 15 minutes", async () => {
  let storedHash = "";
  const response = await handleAdminAction(
    { action: "create_link", customer_id: customerId },
    actorId,
    {
      now: () => new Date("2026-09-17T00:00:00Z"),
      randomToken: () => "a".repeat(64),
      hash: sha256Hex,
      manageLink: async ({ tokenHash }) => {
        storedHash = tokenHash;
      },
      status: async () => ({
        active: false,
        device_count: 0,
        latest_status: null,
        latest_at: null,
      }),
      revokeAll: async () => 0,
      publicBaseUrl:
        "https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/customer-push",
    },
  );

  assertEquals(storedHash, await sha256Hex("a".repeat(64)));
  assertEquals(response.expires_at, "2026-09-17T00:15:00.000Z");
  assertEquals(
    String(response.url).endsWith("token=" + "a".repeat(64)),
    true,
  );
});

Deno.test("status is passed through without secret material", async () => {
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
        latest_status: "sent",
        latest_at: "2026-09-17T00:00:00Z",
      }),
      revokeAll: async () => 0,
      publicBaseUrl: "https://example.test/customer-push",
    },
  );

  assertEquals(response, {
    active: true,
    device_count: 2,
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
