import {
  assertEquals,
  assertRejects,
} from "jsr:@std/assert@1";
import { LiveReadError } from "./policy.ts";
import { ensureDaftarFresh } from "./freshness.ts";

const sourceFixture = {
  id: "11111111-1111-4111-8111-111111111111",
  legacy_user_id: 28,
  api_base_url: "https://daftar-source.test/api/v1",
  contacts_etag: '"contacts-v1"',
  transactions_etag: '"transactions-v1"',
};

Deno.test("304 on both probes validates live without worker sync", async () => {
  const calls: string[] = [];
  const result = await ensureDaftarFresh(sourceFixture, {
    fetcher: async (url) => {
      calls.push(String(url));
      return new Response(null, { status: 304, headers: { etag: '"same"' } });
    },
    invokeWorker: async () => {
      throw new Error("worker must not run");
    },
    now: () => 1000,
    sleep: async () => {},
  });
  assertEquals(result.changed, false);
  assertEquals(calls.length, 2);
});

Deno.test("changed endpoint invokes normalization worker before live success", async () => {
  let workerCalls = 0;
  const result = await ensureDaftarFresh(sourceFixture, {
    fetcher: async () => new Response("[]", { status: 200 }),
    invokeWorker: async () => {
      workerCalls++;
      return { ok: true };
    },
    now: () => 1000,
    sleep: async () => {},
  });
  assertEquals(result.changed, true);
  assertEquals(workerCalls, 1);
});

Deno.test("429 retries once then reports retryable live failure", async () => {
  let calls = 0;
  await assertRejects(
    () => ensureDaftarFresh(sourceFixture, {
      fetcher: async () => {
        calls++;
        return new Response("busy", { status: 429 });
      },
      invokeWorker: async () => ({ ok: true }),
      now: () => 1000,
      sleep: async () => {},
    }),
    LiveReadError,
    "source_http_429",
  );
  assertEquals(calls, 4);
});

Deno.test("new upstream data is normalized before the read is released", async () => {
  const order: string[] = [];
  await ensureDaftarFresh(sourceFixture, {
    fetcher: async () => {
      order.push("live");
      return new Response("[]", { status: 200 });
    },
    invokeWorker: async () => {
      order.push("worker");
      return { ok: true };
    },
    now: () => 1000,
    sleep: async () => {},
  });
  assertEquals(order.slice(-1), ["worker"]);
});
