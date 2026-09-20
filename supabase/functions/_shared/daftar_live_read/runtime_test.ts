import { assertEquals } from "jsr:@std/assert@1";
import { LiveReadError } from "./policy.ts";
import {
  handleDaftarLiveRead,
  type RuntimeDeps,
} from "./runtime.ts";

function runtimeDeps(overrides: Partial<RuntimeDeps> = {}): RuntimeDeps {
  return {
    verifyUser: async () => ({ id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" }),
    loadViewer: async () => ({
      id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      role: "admin",
      tenantId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    }),
    loadSource: async () => ({
      id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
      legacy_user_id: 28,
      live_read_mode: "live",
      live_read_fallback_enabled: true,
      live_read_stale_after_seconds: 300,
      last_success_at: "2026-09-20T00:00:00Z",
      mirror_last_full_at: "2026-09-20T00:00:00Z",
    }),
    ensureFresh: async () => ({
      liveStatus: 304,
      liveLatencyMs: 10,
      changed: false,
      validatedAt: "2026-09-20T00:01:00Z",
    }),
    localRead: async () => ({ items: [] }),
    recordEvent: async () => {},
    now: () => Date.parse("2026-09-20T00:01:00Z"),
    ...overrides,
  };
}

function authenticatedReadRequest(operation: string, params: Record<string, unknown>): Request {
  return new Request("https://example.test", {
    method: "POST",
    headers: {
      authorization: "Bearer valid-user-token",
      "content-type": "application/json",
    },
    body: JSON.stringify({ operation, params }),
  });
}

async function responseJson(response: Response) {
  return await response.json() as Record<string, any>;
}

Deno.test("rejects missing bearer", async () => {
  const response = await handleDaftarLiveRead(
    new Request("https://example.test", { method: "POST" }),
    runtimeDeps(),
  );
  assertEquals(response.status, 401);
});

Deno.test("rejects a customer reading another customer", async () => {
  const req = authenticatedReadRequest("customer_finance_snapshot", {
    customer_id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
  });
  const response = await handleDaftarLiveRead(req, runtimeDeps({
    loadViewer: async () => ({
      id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      role: "customer",
      tenantId: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
    }),
  }));
  assertEquals(response.status, 403);
});

Deno.test("rejects unsupported operation without fallback", async () => {
  const response = await handleDaftarLiveRead(
    authenticatedReadRequest("drop_everything", {}),
    runtimeDeps(),
  );
  assertEquals(response.status, 400);
});

Deno.test("live validation success returns local normalized DTO as source live", async () => {
  const response = await handleDaftarLiveRead(
    authenticatedReadRequest("customer_finance_snapshot", {
      customer_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    }),
    runtimeDeps({ localRead: async () => ({ total_remaining_iqd: 125000 }) }),
  );
  const body = await responseJson(response);
  assertEquals(body.source, "live");
  assertEquals(body.data.total_remaining_iqd, 125000);
  assertEquals(body.fallback_reason, null);
});

Deno.test("timeout falls back to mirror with same DTO shape", async () => {
  const response = await handleDaftarLiveRead(
    authenticatedReadRequest("customer_finance_snapshot", {
      customer_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    }),
    runtimeDeps({
      ensureFresh: async () => {
        throw new LiveReadError({ kind: "timeout" }, "source_timeout");
      },
      localRead: async () => ({ total_remaining_iqd: 125000 }),
    }),
  );
  const body = await responseJson(response);
  assertEquals(body.source, "mirror");
  assertEquals(body.data.total_remaining_iqd, 125000);
  assertEquals(body.fallback_reason, "source_timeout");
});

Deno.test("401 from Daftar does not fallback", async () => {
  const response = await handleDaftarLiveRead(
    authenticatedReadRequest("customer_finance_snapshot", {
      customer_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    }),
    runtimeDeps({
      ensureFresh: async () => {
        throw new LiveReadError({ kind: "http", status: 401 }, "source_http_401");
      },
    }),
  );
  const body = await responseJson(response);
  assertEquals(response.status, 502);
  assertEquals(body.error, "source_http_401");
});

Deno.test("integrity failures never fallback", async () => {
  let localReads = 0;
  const response = await handleDaftarLiveRead(
    authenticatedReadRequest("admin_dashboard", {}),
    runtimeDeps({
      ensureFresh: async () => {
        throw new LiveReadError({ kind: "integrity" }, "invalid_source_response");
      },
      localRead: async () => {
        localReads++;
        return {};
      },
    }),
  );
  assertEquals(response.status, 502);
  assertEquals(localReads, 0);
});

Deno.test("local materialization failure after live validation is an error", async () => {
  const response = await handleDaftarLiveRead(
    authenticatedReadRequest("admin_dashboard", {}),
    runtimeDeps({
      localRead: async () => {
        throw new Error("local_read_failed");
      },
    }),
  );
  assertEquals(response.status, 500);
});
