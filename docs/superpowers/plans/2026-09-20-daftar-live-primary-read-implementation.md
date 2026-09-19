# Daftar Qarz Live-Primary Read Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Daftar Qarz the live primary read source for Daftar-originated customer/debt/payment data while keeping all credentials server-side and transparently falling back to the durable ZHIROX mirror on transient upstream failures.

**Architecture:** Add an authenticated `daftar-live-read` Edge Function that validates Daftar freshness on every supported read, synchronously ingests changed upstream data through the existing normalization pipeline, and then materializes the response from the existing authorized ZHIROX read model. A successful live probe returns `source = "live"`; transient upstream failure returns the same DTO from the mirror with `source = "mirror"`. Flutter never calls the Daftar host directly and existing write paths remain unchanged.

**Tech Stack:** Flutter/Dart, Supabase Auth, Supabase Edge Functions (Deno 2 / TypeScript), Supabase Postgres, PostgREST/RPC, existing Daftar sync worker/gateway, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-20-daftar-live-primary-read-design.md`

## Global Constraints

- Daftar Qarz live reads must be server-side; the Flutter client must never contain the Daftar API host, API credentials, service-role key, Vault secret, or trigger secret.
- Daftar account scope remains `legacy_user_id = 28`.
- Existing mirror, connection lock, guardian, reconciliation, financial rehearsal, failover readiness, and outage qualification remain enabled.
- The live-read change is **read-only** with respect to Daftar; all existing ZHIROX writes stay unchanged.
- Mirror fallback is allowed only for transient upstream conditions: network/timeout, HTTP 408, 425, 429 after bounded retry, and HTTP 5xx.
- Authentication, authorization, malformed source data, unsupported operations, and data-integrity failures must not silently fall back.
- Live and mirror reads must return the same operation-specific DTO inside the stable response envelope.
- Mirror freshness threshold is 300 seconds.
- Live-read total interactive deadline is 8 seconds before fallback; only one quick retry is allowed for retryable upstream failures.
- Temporary live-read fallback must never change `sync_mode` from `mirror` to `zhirox_primary`.
- Existing iOS build, Flutter analyze/tests, Deno tests/checks, and Daftar protection verification scripts must remain green.

## Review Focus

- **New upstream row appears between one-minute syncs:** live read must force normalization before returning so the client receives stable ZHIROX IDs, not raw Daftar numeric IDs. Covered in Task 3.
- **HTTP 401/403 or malformed Daftar payload:** return a structured error and do not serve mirror data as though authorization/data integrity were healthy. Covered in Tasks 2 and 4.
- **A customer requests another customer's data:** existing RLS plus explicit tenant/customer checks must reject it. Covered in Task 4.
- **A Daftar payment is split across multiple ZHIROX payment allocations:** response must preserve the normalized ZHIROX allocation model after live freshness validation. Covered in Tasks 3 and 4.
- **Live succeeds but mirror/local materialization fails:** return a structured local-read error, not a misleading `source = "live"` success. Covered in Task 4.

---

## File Structure

### New files

- `supabase/functions/_shared/daftar_live_read/types.ts` — operation names, source/result metadata, fallback classifications, stable envelope types.
- `supabase/functions/_shared/daftar_live_read/policy.ts` — transient/non-transient error classification, stale calculation, response envelope helpers.
- `supabase/functions/_shared/daftar_live_read/freshness.ts` — live ETag probe, bounded retry, synchronous worker refresh when source changed.
- `supabase/functions/_shared/daftar_sync_auth.ts` — pure authorization helper shared by the sync worker and its tests; accepts only the dedicated trigger secret or the server service credential.
- `supabase/functions/_shared/daftar_sync_auth_test.ts` — worker server-to-server authorization regression tests.
- `supabase/functions/_shared/daftar_live_read/local_read.ts` — whitelisted ZHIROX read operations executed with the caller's JWT.
- `supabase/functions/_shared/daftar_live_read/runtime.ts` — auth, tenant/source resolution, live/fallback orchestration, telemetry.
- `supabase/functions/_shared/daftar_live_read/policy_test.ts` — fallback policy tests.
- `supabase/functions/_shared/daftar_live_read/freshness_test.ts` — 304/changed/retry/sync tests.
- `supabase/functions/_shared/daftar_live_read/runtime_test.ts` — auth, tenant, fallback, DTO contract tests.
- `supabase/functions/daftar-live-read/index.ts` — thin HTTP entrypoint.
- `supabase/functions/daftar-live-read/index_test.ts` — HTTP method/body/auth contract tests.
- `supabase/migrations/20260920020000_daftar_live_primary_read.sql` — rollout mode and service-only telemetry schema.
- `lib/services/daftar_live_read_service.dart` — Flutter Edge Function client and source/freshness metadata parser.
- `test/daftar_live_read_service_test.dart` — Dart response-envelope tests.
- `scripts/verify_daftar_live_primary_read.py` — static security/integration regression guard.

### Modified files

- `supabase/functions/daftar-sync/index.ts` — permit authenticated server-to-server invocation from `daftar-live-read` using the existing Supabase service credential, while retaining the dedicated sync-secret path.
- `supabase/config.toml` — add `[functions.daftar-live-read] verify_jwt = false`; handler still manually validates the bearer JWT.
- `lib/services/pb_service.dart` — route Daftar-originated read methods through `DaftarLiveReadService` while preserving public method signatures and existing writes.
- `.github/workflows/ios-unsigned-ipa.yml` — run live-read Deno tests/checks and the new static contract.
- `scripts/verify_daftar_read_path_independence.py` — preserve the no-direct-Daftar-client rule while explicitly allowing the server-side live-read function.

---

### Task 1: Add live-read rollout state and telemetry

**Files:**
- Create: `supabase/migrations/20260920020000_daftar_live_primary_read.sql`

**Interfaces:**
- Consumes: existing `public.daftar_sync_sources.id` and account-28 source row.
- Produces: `live_read_mode`, `live_read_fallback_enabled`, `live_read_stale_after_seconds`, and service-only `public.daftar_live_read_events`.

- [ ] **Step 1: Write the failing SQL regression query**

Create a temporary verification query in the migration-review session before applying DDL:

```sql
select
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'daftar_sync_sources'
      and column_name = 'live_read_mode'
  ) as has_mode,
  to_regclass('public.daftar_live_read_events') is not null as has_events;
```

Expected before implementation:

```text
has_mode = false
has_events = false
```

- [ ] **Step 2: Create the migration with explicit rollout state**

Write exactly this schema shape:

```sql
alter table public.daftar_sync_sources
  add column if not exists live_read_mode text not null default 'off',
  add column if not exists live_read_fallback_enabled boolean not null default true,
  add column if not exists live_read_stale_after_seconds integer not null default 300;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'daftar_sync_sources_live_read_mode_check'
      and conrelid = 'public.daftar_sync_sources'::regclass
  ) then
    alter table public.daftar_sync_sources
      add constraint daftar_sync_sources_live_read_mode_check
      check (live_read_mode in ('off', 'shadow', 'live'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'daftar_sync_sources_live_read_stale_check'
      and conrelid = 'public.daftar_sync_sources'::regclass
  ) then
    alter table public.daftar_sync_sources
      add constraint daftar_sync_sources_live_read_stale_check
      check (live_read_stale_after_seconds between 60 and 3600);
  end if;
end;
$$;

create table if not exists public.daftar_live_read_events (
  id bigint generated always as identity primary key,
  sync_source_id uuid not null
    references public.daftar_sync_sources(id) on delete restrict,
  viewer_id uuid not null,
  operation text not null,
  result_source text not null
    check (result_source in ('live', 'mirror', 'error')),
  status text not null
    check (status in ('success', 'fallback', 'rejected', 'failed')),
  fallback_reason text,
  live_status integer,
  live_latency_ms integer,
  total_latency_ms integer not null,
  mirror_age_ms bigint,
  detail_code text,
  created_at timestamptz not null default now()
);

create index if not exists daftar_live_read_events_source_time_idx
  on public.daftar_live_read_events(sync_source_id, created_at desc);

alter table public.daftar_live_read_events enable row level security;
revoke all on public.daftar_live_read_events
  from public, anon, authenticated;
grant all on public.daftar_live_read_events to service_role;
grant usage, select on sequence public.daftar_live_read_events_id_seq
  to service_role;
```

Do **not** enable live mode in the migration; the account-28 row must remain `off` after DDL.

- [ ] **Step 3: Run database checks**

Run:

```sql
select live_read_mode, live_read_fallback_enabled, live_read_stale_after_seconds
from public.daftar_sync_sources
where legacy_user_id = 28
  and source_fingerprint = 'daftar-live-account-28-v1';

select
  has_table_privilege('anon', 'public.daftar_live_read_events', 'select') as anon_select,
  has_table_privilege('authenticated', 'public.daftar_live_read_events', 'select') as auth_select,
  has_table_privilege('service_role', 'public.daftar_live_read_events', 'insert') as service_insert;
```

Expected:

```text
live_read_mode = off
live_read_fallback_enabled = true
live_read_stale_after_seconds = 300
anon_select = false
auth_select = false
service_insert = true
```

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260920020000_daftar_live_primary_read.sql
git commit -m "feat(sync): add live-read rollout state"
```

---

### Task 2: Define the live/fallback policy as pure TypeScript

**Files:**
- Create: `supabase/functions/_shared/daftar_live_read/types.ts`
- Create: `supabase/functions/_shared/daftar_live_read/policy.ts`
- Test: `supabase/functions/_shared/daftar_live_read/policy_test.ts`

**Interfaces:**
- Produces:
  - `DaftarLiveReadOperation`
  - `ReadSource = "live" | "mirror"`
  - `LiveFailure`
  - `isFallbackEligible(failure: LiveFailure): boolean`
  - `isMirrorStale(asOf: string | null, staleAfterSeconds: number, nowMs?: number): boolean`
  - `successEnvelope<T>(...): LiveReadEnvelope<T>`

- [ ] **Step 1: Write failing policy tests**

```ts
import {
  assertEquals,
  assertFalse,
} from "jsr:@std/assert@1";
import {
  isFallbackEligible,
  isMirrorStale,
} from "./policy.ts";

Deno.test("fallbacks on timeout, 408, 425, 429 and 5xx", () => {
  assertEquals(isFallbackEligible({ kind: "timeout" }), true);
  for (const status of [408, 425, 429, 500, 503]) {
    assertEquals(isFallbackEligible({ kind: "http", status }), true);
  }
});

Deno.test("does not fallback on auth, unsupported or integrity failures", () => {
  for (const kind of ["authentication", "authorization", "unsupported", "integrity"] as const) {
    assertFalse(isFallbackEligible({ kind }));
  }
  assertFalse(isFallbackEligible({ kind: "http", status: 401 }));
  assertFalse(isFallbackEligible({ kind: "http", status: 403 }));
  assertFalse(isFallbackEligible({ kind: "http", status: 422 }));
});

Deno.test("mirror becomes stale after configured threshold", () => {
  const asOf = "2026-09-20T00:00:00.000Z";
  assertFalse(isMirrorStale(asOf, 300, Date.parse("2026-09-20T00:04:59.000Z")));
  assertEquals(isMirrorStale(asOf, 300, Date.parse("2026-09-20T00:05:01.000Z")), true);
});
```

- [ ] **Step 2: Verify RED**

Run:

```bash
deno test supabase/functions/_shared/daftar_live_read/policy_test.ts
```

Expected: FAIL because `policy.ts` / exported functions do not exist.

- [ ] **Step 3: Implement the minimal policy**

Use explicit union types, not stringly-typed catch-all errors:

```ts
export type DaftarLiveReadOperation =
  | "customer_directory"
  | "customer_finance_snapshot"
  | "customer_timeline"
  | "customer_debts_page"
  | "debt_detail"
  | "debt_payments"
  | "customer_all_debts"
  | "admin_dashboard"
  | "admin_all_debts"
  | "employee_stats";

export type ReadSource = "live" | "mirror";

export type LiveFailure =
  | { kind: "timeout" }
  | { kind: "network" }
  | { kind: "http"; status: number }
  | { kind: "authentication" }
  | { kind: "authorization" }
  | { kind: "unsupported" }
  | { kind: "integrity" };

export type LiveReadEnvelope<T> = {
  ok: true;
  source: ReadSource;
  as_of: string | null;
  stale: boolean;
  fallback_reason: string | null;
  data: T;
};

export function isFallbackEligible(failure: LiveFailure): boolean {
  if (failure.kind === "timeout" || failure.kind === "network") return true;
  if (failure.kind !== "http") return false;
  return failure.status === 408 ||
    failure.status === 425 ||
    failure.status === 429 ||
    failure.status >= 500;
}

export function isMirrorStale(
  asOf: string | null,
  staleAfterSeconds: number,
  nowMs = Date.now(),
): boolean {
  if (!asOf) return true;
  const parsed = Date.parse(asOf);
  if (!Number.isFinite(parsed)) return true;
  return nowMs - parsed > staleAfterSeconds * 1000;
}
```

Add `successEnvelope<T>` in the same file so every operation uses one stable envelope.

- [ ] **Step 4: Verify GREEN**

```bash
deno test supabase/functions/_shared/daftar_live_read/policy_test.ts
deno check supabase/functions/_shared/daftar_live_read/policy.ts
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/daftar_live_read
git commit -m "feat(sync): define live-read fallback policy"
```

---

### Task 3: Make live freshness validation synchronize changed Daftar data

**Files:**
- Create: `supabase/functions/_shared/daftar_live_read/freshness.ts`
- Test: `supabase/functions/_shared/daftar_live_read/freshness_test.ts`
- Create: `supabase/functions/_shared/daftar_sync_auth.ts`
- Test: `supabase/functions/_shared/daftar_sync_auth_test.ts`
- Modify: `supabase/functions/daftar-sync/index.ts`

**Interfaces:**
- Consumes: account-28 source row fields `api_base_url`, `contacts_etag`, `transactions_etag`, `last_success_at`.
- Produces:
  - `ensureDaftarFresh(source, deps): Promise<LiveFreshnessResult>`
  - `LiveFreshnessResult = { liveStatus, liveLatencyMs, changed, validatedAt }`
- Server-to-server worker invocation uses the existing Supabase service credential in the `Authorization` header and never exposes it to Flutter.

- [ ] **Step 1: Write failing freshness tests**

Use dependency injection for `fetch`, delay, and worker invocation:

```ts
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
  assertEquals(calls, 4); // contacts and transactions, two bounded attempts each
});
```

Also add the Review Focus test:

```ts
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
```

- [ ] **Step 2: Verify RED**

```bash
deno test supabase/functions/_shared/daftar_live_read/freshness_test.ts
```

Expected: FAIL because `ensureDaftarFresh` does not exist.

- [ ] **Step 3: Implement live probes with an 8-second deadline and one retry**

Implement both endpoint probes with `If-None-Match`. The helper must:

```ts
const RETRYABLE = new Set([408, 425, 429]);

function retryableStatus(status: number) {
  return RETRYABLE.has(status) || status >= 500;
}
```

Each probe gets at most two attempts and uses `AbortSignal.timeout(4_000)`; total orchestrated deadline must not exceed 8 seconds.

If either endpoint returns 2xx changed, call `invokeWorker()` **before** returning live success.

- [ ] **Step 4: Extend the sync worker for internal server-to-server invocation**

Keep the current dedicated `x-daftar-sync-secret` path and add a second allowed path only when the bearer credential exactly matches the server's Supabase service credential.

The authorization logic must be equivalent to:

```ts
const bearer = (req.headers.get("authorization") ?? "")
  .replace(/^Bearer\s+/i, "")
  .trim();

const internalServiceAuthorized =
  bearer.length > 0 &&
  serviceCredential.length > 0 &&
  constantTimeEqual(
    await sha256Hex(bearer),
    await sha256Hex(serviceCredential),
  );

const dedicatedSecretAuthorized =
  providedSecret.length > 0 &&
  constantTimeEqual(
    await sha256Hex(providedSecret),
    source.trigger_secret_hash,
  );

if (!internalServiceAuthorized && !dedicatedSecretAuthorized) {
  return json({ error: "unauthorized" }, 401);
}
```

Do not log either credential.

- [ ] **Step 5: Extract and test worker authorization as a pure helper**

Create `supabase/functions/_shared/daftar_sync_auth.ts`:

```ts
export async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

export async function authorizeDaftarSyncRequest(input: {
  authorizationHeader: string | null;
  providedSecret: string;
  serviceCredential: string;
  expectedSecretHash: string;
}): Promise<boolean> {
  const bearer = (input.authorizationHeader ?? "")
    .replace(/^Bearer\\s+/i, "")
    .trim();

  const internalServiceAuthorized =
    bearer.length > 0 &&
    input.serviceCredential.length > 0 &&
    constantTimeEqual(
      await sha256Hex(bearer),
      await sha256Hex(input.serviceCredential),
    );

  const dedicatedSecretAuthorized =
    input.providedSecret.length > 0 &&
    constantTimeEqual(
      await sha256Hex(input.providedSecret),
      input.expectedSecretHash,
    );

  return internalServiceAuthorized || dedicatedSecretAuthorized;
}
```

Create `supabase/functions/_shared/daftar_sync_auth_test.ts`:

```ts
import { assertEquals } from "jsr:@std/assert@1";
import {
  authorizeDaftarSyncRequest,
  sha256Hex,
} from "./daftar_sync_auth.ts";

Deno.test("ordinary user bearer cannot invoke daftar-sync internally", async () => {
  const allowed = await authorizeDaftarSyncRequest({
    authorizationHeader: "Bearer user-token",
    providedSecret: "",
    serviceCredential: "service-token",
    expectedSecretHash: await sha256Hex("trigger-secret"),
  });
  assertEquals(allowed, false);
});

Deno.test("service bearer can invoke daftar-sync without trigger secret", async () => {
  const allowed = await authorizeDaftarSyncRequest({
    authorizationHeader: "Bearer service-token",
    providedSecret: "",
    serviceCredential: "service-token",
    expectedSecretHash: await sha256Hex("trigger-secret"),
  });
  assertEquals(allowed, true);
});

Deno.test("dedicated trigger secret still authorizes cron and gateway", async () => {
  const allowed = await authorizeDaftarSyncRequest({
    authorizationHeader: null,
    providedSecret: "trigger-secret",
    serviceCredential: "service-token",
    expectedSecretHash: await sha256Hex("trigger-secret"),
  });
  assertEquals(allowed, true);
});
```

Change `daftar-sync/index.ts` to call `authorizeDaftarSyncRequest(...)` instead of duplicating credential logic.

- [ ] **Step 6: Verify GREEN**

```bash
deno test supabase/functions/_shared/daftar_live_read/freshness_test.ts
deno test supabase/functions/daftar-sync
deno check supabase/functions/daftar-sync/index.ts
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/_shared/daftar_live_read         supabase/functions/daftar-sync
git commit -m "feat(sync): validate and normalize live Daftar reads"
```

---

### Task 4: Implement authenticated, tenant-scoped local materialization and HTTP runtime

**Files:**
- Create: `supabase/functions/_shared/daftar_live_read/local_read.ts`
- Create: `supabase/functions/_shared/daftar_live_read/runtime.ts`
- Create: `supabase/functions/_shared/daftar_live_read/runtime_test.ts`
- Create: `supabase/functions/daftar-live-read/index.ts`
- Create: `supabase/functions/daftar-live-read/index_test.ts`
- Modify: `supabase/config.toml`

**Interfaces:**
- Consumes:
  - valid user bearer JWT;
  - whitelisted `DaftarLiveReadOperation`;
  - current ZHIROX RPC/table reads;
  - `ensureDaftarFresh` from Task 3.
- Produces:
  - HTTP POST `/functions/v1/daftar-live-read`;
  - body `{ operation, params }`;
  - stable envelope `{ ok, source, as_of, stale, fallback_reason, data }`.

- [ ] **Step 1: Write failing runtime authorization tests**

Test these exact behaviors with injected fake clients:

```ts
Deno.test("rejects missing bearer", async () => {
  const response = await handleDaftarLiveRead(
    new Request("https://example.test", { method: "POST" }),
    deps,
  );
  assertEquals(response.status, 401);
});

Deno.test("rejects a customer reading another customer", async () => {
  const response = await runAuthorizedRequest({
    viewer: customerViewer("customer-a"),
    operation: "customer_finance_snapshot",
    params: { customer_id: "customer-b" },
  });
  assertEquals(response.status, 403);
});

Deno.test("rejects unsupported operation without fallback", async () => {
  const response = await runAuthorizedRequest({
    viewer: adminViewer,
    operation: "drop_everything",
    params: {},
  });
  assertEquals(response.status, 400);
});
```

- [ ] **Step 2: Write failing live/fallback contract tests**

```ts
Deno.test("live validation success returns local normalized DTO as source live", async () => {
  const response = await runFixture({
    freshness: { kind: "success", changed: false },
    localData: { total_remaining_iqd: 125000 },
  });
  assertEquals(response.body.source, "live");
  assertEquals(response.body.data.total_remaining_iqd, 125000);
  assertEquals(response.body.fallback_reason, null);
});

Deno.test("timeout falls back to mirror with same DTO shape", async () => {
  const response = await runFixture({
    freshness: { kind: "failure", failure: { kind: "timeout" } },
    localData: { total_remaining_iqd: 125000 },
  });
  assertEquals(response.body.source, "mirror");
  assertEquals(response.body.data.total_remaining_iqd, 125000);
  assertEquals(response.body.fallback_reason, "source_timeout");
});

Deno.test("401 from Daftar does not fallback", async () => {
  const response = await runFixture({
    freshness: { kind: "failure", failure: { kind: "http", status: 401 } },
    localData: { total_remaining_iqd: 125000 },
  });
  assertEquals(response.status, 502);
  assertEquals(response.body.error, "source_http_401");
});
```

Add tests for malformed source payload/integrity errors and local materialization failure after live success.

- [ ] **Step 3: Implement explicit viewer/source resolution**

Manual JWT validation is required because `verify_jwt = false` is used for compatibility:

```ts
const token = bearerToken(req);
if (!token) return json({ error: "authentication_required" }, 401);

const { data: userResult, error: userError } =
  await admin.auth.getUser(token);
if (userError || !userResult.user) {
  return json({ error: "authentication_required" }, 401);
}

const viewer = await loadViewerProfile(admin, userResult.user.id);
const tenantId = viewer.role === "admin"
  ? viewer.id
  : viewer.admin_id;

if (!tenantId) {
  return json({ error: "tenant_not_found" }, 403);
}

const source = await loadAccount28Source(admin, tenantId);
if (!source) {
  return json({ error: "daftar_source_not_available" }, 404);
}
```

Create a second Supabase client using `SUPABASE_ANON_KEY` plus the original user bearer for local reads, so existing RLS and auth-dependent RPCs still execute as the user.

- [ ] **Step 4: Implement only whitelisted local read operations**

`local_read.ts` must use a `switch` with no arbitrary RPC/table passthrough.

The first implementation must support:

```ts
const DEBT_SELECT = `
  *,
  customer_expand:profiles!debts_customer_id_fkey(*),
  debt_creator_expand:profiles!debts_created_by_fkey(*)
`;

const PAYMENT_SELECT = `
  *,
  debt_expand:debts!payments_debt_id_fkey(
    *,
    customer_expand:profiles!debts_customer_id_fkey(*),
    debt_creator_expand:profiles!debts_created_by_fkey(*)
  ),
  creator_expand:profiles!payments_created_by_fkey(*)
`;

switch (operation) {
  case "customer_directory":
    return unwrap(await userClient.rpc("get_customer_directory_page", {
      p_search: stringParam(params, "search", ""),
      p_limit: intParam(params, "limit", 60, 1, 100),
      ...directoryCursorParams(params["cursor"]),
    }));

  case "customer_finance_snapshot":
    return unwrap(await userClient.rpc("get_customer_finance_snapshot", {
      p_customer_id: uuidParam(params, "customer_id"),
    }));

  case "customer_timeline":
    return unwrap(await userClient.rpc("get_customer_financial_timeline_page", {
      p_customer_id: uuidParam(params, "customer_id"),
      p_limit: intParam(params, "limit", 50, 1, 100),
      ...timelineCursorParams(params["cursor"]),
    }));

  case "customer_debts_page":
    return unwrap(await userClient.rpc("get_customer_debts_page", {
      p_customer_id: uuidParam(params, "customer_id"),
      p_status: nullableStringParam(params, "status"),
      p_page: intParam(params, "page", 1, 1, 1000000),
      p_limit: intParam(params, "limit", 20, 1, 100),
    }));

  case "debt_detail": {
    const debtId = uuidParam(params, "debt_id");
    return unwrapOne(await userClient
      .from("debts")
      .select(DEBT_SELECT)
      .eq("id", debtId)
      .single());
  }

  case "debt_payments": {
    const debtId = uuidParam(params, "debt_id");
    return unwrap(await userClient
      .from("payments")
      .select(PAYMENT_SELECT)
      .eq("debt_id", debtId)
      .order("created_at", { ascending: false })
      .order("id", { ascending: false })
      .range(0, 499));
  }

  case "customer_all_debts":
    return readAllPages(async (from, to) =>
      unwrap(await userClient
        .from("debts")
        .select(DEBT_SELECT)
        .eq("customer_id", uuidParam(params, "customer_id"))
        .is("deleted_at", null)
        .order("created_at", { ascending: false })
        .order("id", { ascending: false })
        .range(from, to))
    );

  case "admin_dashboard":
    return unwrap(await userClient.rpc("get_admin_dashboard_snapshot"));

  case "admin_all_debts": {
    const requestedAdmin = uuidParam(params, "admin_id");
    if (requestedAdmin !== viewer.tenantId) {
      throw new LiveReadError({ kind: "authorization" }, "wrong_tenant");
    }
    return readAdminDebts(userClient, requestedAdmin, {
      from: nullableIsoParam(params, "from"),
      to: nullableIsoParam(params, "to"),
    });
  }

  case "employee_stats": {
    const employeeId = uuidParam(params, "employee_id");
    await assertEmployeeVisibleToViewer(userClient, viewer, employeeId);
    return readEmployeeStats(userClient, employeeId);
  }
}
```

Implement the helpers in the same file with fixed behavior:

```ts
async function readAllPages(
  page: (from: number, to: number) => Promise<unknown[]>,
): Promise<unknown[]> {
  const all: unknown[] = [];
  const size = 500;
  for (let offset = 0;; offset += size) {
    const rows = await page(offset, offset + size - 1);
    all.push(...rows);
    if (rows.length < size) return all;
  }
}

async function readEmployeeStats(userClient: any, employeeId: string) {
  const [debts, payments] = await Promise.all([
    readAllPages((from, to) =>
      unwrap(userClient.from("debts")
        .select("amount")
        .eq("created_by", employeeId)
        .is("deleted_at", null)
        .range(from, to))),
    readAllPages((from, to) =>
      unwrap(userClient.from("payments")
        .select("amount")
        .eq("created_by", employeeId)
        .range(from, to))),
  ]);
  return {
    total_debts_created: debts.reduce(
      (sum, row: any) => sum + Number(row.amount ?? 0),
      0,
    ),
    total_payments_collected: payments.reduce(
      (sum, row: any) => sum + Number(row.amount ?? 0),
      0,
    ),
  };
}
```

`readAdminDebts` must first page tenant customer IDs from `profiles` in batches of 500, then query `debts` in customer-ID chunks of 50 with the fixed `DEBT_SELECT`, optional `created_at >= from`, optional `created_at < to`, and page size 500; sort the final array by `created_at DESC, id DESC`. No caller-provided table name, select clause, filter expression, or tenant ID is accepted.

- [ ] **Step 5: Preserve normalized payment allocations**

For `debt_payments` and customer timeline, return existing `public.payments` rows after live freshness validation. Do not convert one Daftar PAYMENT transaction into one client payment row; existing ZHIROX allocation rows remain the client contract.

Add the explicit test:

```ts
Deno.test("one Daftar payment can materialize as multiple ZHIROX allocations", async () => {
  const data = await localReadFixture("debt_payments", {
    normalizedPayments: [
      { id: "p1", amount: 60000 },
      { id: "p2", amount: 40000 },
    ],
  });
  assertEquals(data.length, 2);
  assertEquals(data.reduce((sum, row) => sum + row.amount, 0), 100000);
});
```

- [ ] **Step 6: Implement fallback and telemetry**

Runtime order must be:

```text
validate user
-> resolve tenant + account-28 source
-> validate operation/params
-> if live_read_mode == off: local read as mirror
-> else ensureDaftarFresh()
   -> success: local read, source=live
   -> transient failure + fallback enabled: local read, source=mirror
   -> non-transient failure: structured error
-> write service-only telemetry event
-> return envelope
```

Use `source.last_success_at ?? source.mirror_last_full_at` as mirror `as_of`.

Telemetry failure must be best-effort and must not turn a successful read into an error.

- [ ] **Step 7: Add the thin HTTP entrypoint and config**

`index.ts` should only construct dependencies and delegate:

```ts
Deno.serve((req) =>
  handleDaftarLiveRead(req, {
    supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
    anonKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    serviceCredential: resolveServiceCredential(),
    fetcher: fetch,
  })
);
```

Add to `supabase/config.toml`:

```toml
[functions.daftar-live-read]
verify_jwt = false
```

- [ ] **Step 8: Verify GREEN**

```bash
deno test supabase/functions/_shared/daftar_live_read
deno test supabase/functions/daftar-live-read
deno check supabase/functions/daftar-live-read/index.ts
```

Expected: PASS with no secret values printed.

- [ ] **Step 9: Commit**

```bash
git add supabase/functions/_shared/daftar_live_read         supabase/functions/daftar-live-read         supabase/config.toml
git commit -m "feat(sync): add authenticated Daftar live-read gateway"
```

---

### Task 5: Add the Flutter live-read client without changing screen contracts

**Files:**
- Create: `lib/services/daftar_live_read_service.dart`
- Test: `test/daftar_live_read_service_test.dart`

**Interfaces:**
- Produces:
  - `enum DaftarReadSource { live, mirror }`
  - `class DaftarReadMeta`
  - `class DaftarReadResponse<T>`
  - `DaftarLiveReadService.invokeMap(operation, params)`
  - `DaftarLiveReadService.lastMeta`

- [ ] **Step 1: Write failing Dart parsing tests**

```dart
test('parses live envelope and metadata', () {
  final result = DaftarLiveReadService.parseMapEnvelope({
    'ok': true,
    'source': 'live',
    'as_of': '2026-09-20T00:00:00Z',
    'stale': false,
    'fallback_reason': null,
    'data': {'total_remaining_iqd': 125000},
  });

  expect(result.meta.source, DaftarReadSource.live);
  expect(result.meta.stale, isFalse);
  expect(result.data['total_remaining_iqd'], 125000);
});

test('parses mirror fallback without losing data', () {
  final result = DaftarLiveReadService.parseMapEnvelope({
    'ok': true,
    'source': 'mirror',
    'as_of': '2026-09-19T23:59:00Z',
    'stale': false,
    'fallback_reason': 'source_timeout',
    'data': {'items': []},
  });

  expect(result.meta.source, DaftarReadSource.mirror);
  expect(result.meta.fallbackReason, 'source_timeout');
});
```

Also test malformed envelope -> `FormatException`.

- [ ] **Step 2: Verify RED**

```bash
flutter test test/daftar_live_read_service_test.dart
```

Expected: FAIL because the service/types do not exist.

- [ ] **Step 3: Implement the service**

Use only Supabase Functions:

```dart
final response = await PBService.client.functions.invoke(
  'daftar-live-read',
  body: {
    'operation': operation,
    'params': params,
  },
);
```

The service must never contain the Daftar host or a Daftar credential.

Expose the latest metadata with:

```dart
static final ValueNotifier<DaftarReadMeta?> lastMeta =
    ValueNotifier<DaftarReadMeta?>(null);
```

Update `lastMeta` after every successful envelope parse.

- [ ] **Step 4: Verify GREEN**

```bash
flutter test test/daftar_live_read_service_test.dart
flutter analyze
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/daftar_live_read_service.dart         test/daftar_live_read_service_test.dart
git commit -m "feat(sync): add Flutter Daftar live-read client"
```

---

### Task 6: Move customer-facing financial reads to live-primary

**Files:**
- Modify: `lib/services/pb_service.dart`
- Test: `test/daftar_live_read_service_test.dart`
- Create: `scripts/verify_daftar_customer_live_reads.py`

**Interfaces:**
- Consumes: `DaftarLiveReadService.invokeMap`.
- Preserves current PBService public method signatures so screens do not need a broad rewrite.

- [ ] **Step 1: Write the failing static integration contract**

`verify_daftar_customer_live_reads.py` must assert the customer-facing methods reference the live-read service:

```python
from pathlib import Path

pb = Path('lib/services/pb_service.dart').read_text()
required_operations = (
    "'customer_directory'",
    "'customer_finance_snapshot'",
    "'customer_timeline'",
    "'customer_debts_page'",
    "'debt_detail'",
    "'debt_payments'",
    "'customer_all_debts'",
)

assert "DaftarLiveReadService" in pb
for operation in required_operations:
    assert operation in pb, f"missing live-read operation {operation}"
```

Run it before changes; expected FAIL.

- [ ] **Step 2: Route customer directory through `customer_directory`**

Replace direct `get_customer_directory_page` invocation inside `PBService.getCustomerDirectoryPage` with:

```dart
final envelope = await DaftarLiveReadService.invokeMap(
  'customer_directory',
  params,
);
final data = envelope.data;
```

Keep existing `RecordModel` conversion and return keys unchanged.

- [ ] **Step 3: Route finance snapshot and timeline**

Use:

```dart
await DaftarLiveReadService.invokeMap(
  'customer_finance_snapshot',
  {'customer_id': customerId},
);

await DaftarLiveReadService.invokeMap(
  'customer_timeline',
  {
    'customer_id': customerId,
    'limit': limit.clamp(1, 100),
    if (cursor != null) 'cursor': cursor,
  },
);
```

Keep the current `openDebts`, `debts`, `payments`, `financialEvents`, pagination, and totals shapes unchanged.

- [ ] **Step 4: Route customer debt-page/detail/payment reads**

For the customer-specific branch of `getDebtsPaginated`, use `customer_debts_page`.

Change `getDebt` from a direct PocketBase compatibility read to `debt_detail`.

Change `getPayments` debt/customer branches to `debt_payments` or `customer_timeline`-backed fixed operations; keep the `RecordModel` shape and expansions exactly as before.

- [ ] **Step 5: Route full customer statement reads**

Change `getAllCustomerDebtsLive` to `customer_all_debts` and preserve the sorted list of `RecordModel`.

- [ ] **Step 6: Run focused tests and static contract**

```bash
python3 scripts/verify_daftar_customer_live_reads.py
flutter test test/daftar_live_read_service_test.dart
flutter analyze
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/services/pb_service.dart         scripts/verify_daftar_customer_live_reads.py         test/daftar_live_read_service_test.dart
git commit -m "feat(sync): make customer reads Daftar-live primary"
```

---

### Task 7: Move admin/report financial reads to live-primary

**Files:**
- Modify: `lib/services/pb_service.dart`
- Create: `scripts/verify_daftar_admin_live_reads.py`

**Interfaces:**
- Consumes: Task 4 operations `admin_dashboard`, `admin_all_debts`, `employee_stats`.
- Preserves current return types for admin dashboard, statements, and employee stats.

- [ ] **Step 1: Write the failing admin integration contract**

```python
from pathlib import Path

pb = Path('lib/services/pb_service.dart').read_text()

for operation in (
    "'admin_dashboard'",
    "'admin_all_debts'",
    "'employee_stats'",
):
    assert operation in pb, f"missing {operation}"

assert "static Future<Map<String, dynamic>> getDashboardStats" in pb
assert "static Future<List<RecordModel>> getAllAdminDebts" in pb
assert "static Future<Map<String, double>> getEmployeeStats" in pb
```

Run before edits; expected FAIL.

- [ ] **Step 2: Route admin dashboard snapshot**

Replace direct `get_admin_dashboard_snapshot` with `admin_dashboard`, while preserving:

```dart
{
  'totalCustomers': ...,
  'totalDebt': ...,
  'totalRemaining': ...,
  'totalPayments': ...,
  'totalDebtUsd': ...,
  'totalRemainingUsd': ...,
  'totalPaymentsUsd': ...,
  'pendingDebts': ...,
  'pendingRequests': ...,
  'recentActivity': ...,
}
```

- [ ] **Step 3: Route complete admin debt statement**

`getAllAdminDebts` must call `admin_all_debts` with `admin_id`, optional `from`, and optional `to`, then retain the existing date-descending sorting and customer expansion contract.

The Edge Function must reject a caller-supplied `admin_id` that differs from the resolved tenant.

- [ ] **Step 4: Route employee stats**

`getEmployeeStats(employeeId)` calls `employee_stats` with the employee ID and preserves:

```dart
{
  'totalDebtsCreated': double,
  'totalPaymentsCollected': double,
}
```

Server-side authorization must allow an admin to inspect an employee in the same tenant and allow an employee only their own ID.

- [ ] **Step 5: Verify**

```bash
python3 scripts/verify_daftar_admin_live_reads.py
flutter analyze
flutter test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/services/pb_service.dart         scripts/verify_daftar_admin_live_reads.py
git commit -m "feat(sync): make admin financial reads Daftar-live primary"
```

---

### Task 8: Lock the security and CI contract

**Files:**
- Create: `scripts/verify_daftar_live_primary_read.py`
- Modify: `scripts/verify_daftar_read_path_independence.py`
- Modify: `.github/workflows/ios-unsigned-ipa.yml`

**Interfaces:**
- Produces a build-breaking contract that prevents direct client access, secret leakage, operation bypass, or accidental removal of fallback protections.

- [ ] **Step 1: Write the new static verifier**

It must assert:

```python
from pathlib import Path

root = Path('.')
dart = '\n'.join(p.read_text(errors='ignore') for p in (root / 'lib').rglob('*.dart'))
runtime = (root / 'supabase/functions/_shared/daftar_live_read/runtime.ts').read_text()
policy = (root / 'supabase/functions/_shared/daftar_live_read/policy.ts').read_text()
config = (root / 'supabase/config.toml').read_text()

assert 'api-daftar-qarz.kasbkar.net' not in dart
assert 'x-daftar-sync-secret' not in dart
assert 'SUPABASE_SERVICE_ROLE_KEY' not in dart
assert "functions.invoke(\n  'daftar-live-read'" in dart or "'daftar-live-read'" in dart

assert 'isFallbackEligible' in runtime
assert 'customer_directory' in runtime
assert 'customer_finance_snapshot' in runtime
assert 'admin_dashboard' in runtime
assert '[functions.daftar-live-read]\nverify_jwt = false' in config
assert 'admin.auth.getUser' in runtime
assert 'legacy_user_id' in runtime
assert 'live_read_mode' in runtime

for code in ('authentication', 'authorization', 'integrity', 'unsupported'):
    assert code in policy
```

- [ ] **Step 2: Update the old independence verifier**

Keep the original rule that no Dart file may contain the Daftar host or call `daftar-sync` / `daftar-sync-gateway` directly.

Change its success condition from “all user-facing reads come directly from ZHIROX/Supabase RPCs” to:

```text
Flutter -> daftar-live-read Edge Function -> live Daftar validation / mirror materialization
```

The script must explicitly allow `daftar-live-read` because it is the approved server gateway.

- [ ] **Step 3: Add CI steps**

After the existing Daftar verification steps, add:

```yaml
- name: Verify Daftar live-primary reads
  if: github.ref_name == 'user-source'
  run: |
    python3 scripts/verify_daftar_live_primary_read.py
    python3 scripts/verify_daftar_customer_live_reads.py
    python3 scripts/verify_daftar_admin_live_reads.py

- name: Test Daftar live-read Edge Function
  if: github.ref_name == 'user-source'
  run: |
    deno test supabase/functions/_shared/daftar_live_read
    deno test supabase/functions/daftar-live-read
    deno test supabase/functions/daftar-sync

- name: Check Daftar live-read Edge Function
  if: github.ref_name == 'user-source'
  run: |
    deno check supabase/functions/daftar-live-read/index.ts
```

Keep all existing Daftar lock/mirror/reconciliation/rehearsal/failover/outage checks.

- [ ] **Step 4: Run the complete suite locally/CI-equivalent**

```bash
python3 scripts/verify_daftar_sync_lock.py
python3 scripts/verify_daftar_mirror.py
python3 scripts/verify_daftar_reconciliation.py
python3 scripts/verify_daftar_cutover_rehearsal.py
python3 scripts/verify_daftar_failover_ready.py
python3 scripts/verify_daftar_outage_qualification.py
python3 scripts/verify_daftar_read_path_independence.py
python3 scripts/verify_daftar_live_primary_read.py
python3 scripts/verify_daftar_customer_live_reads.py
python3 scripts/verify_daftar_admin_live_reads.py
deno test supabase/functions/_shared/daftar_live_read
deno test supabase/functions/daftar-live-read
deno test supabase/functions/daftar-sync
deno check supabase/functions/daftar-live-read/index.ts
flutter analyze
flutter test
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts         .github/workflows/ios-unsigned-ipa.yml
git commit -m "ci(sync): lock Daftar live-primary read contract"
```

---

### Task 9: Deploy in off -> shadow -> live stages and prove fallback without cutover

**Files:**
- No product-code changes unless verification exposes a bug; any bug must start a new RED test before a fix.

**Interfaces:**
- Consumes all previous tasks.
- Produces production state `live_read_mode = 'live'` only after server, shadow, fallback, and CI checks pass.

- [ ] **Step 1: Verify current Supabase documentation before deployment**

Check current Supabase changelog and Edge Function/Auth documentation for breaking changes affecting:

```text
verify_jwt
manual auth.getUser(token)
Edge Function environment keys
supabase-js Edge runtime
```

If current docs contradict the planned runtime behavior, stop and update the plan/spec before deployment.

- [ ] **Step 2: Apply schema with live mode still off**

After applying Task 1 migration, verify:

```sql
select live_read_mode, live_read_fallback_enabled, live_read_stale_after_seconds
from public.daftar_sync_sources
where legacy_user_id = 28
  and source_fingerprint = 'daftar-live-account-28-v1';
```

Expected:

```text
off | true | 300
```

- [ ] **Step 3: Deploy server code with client still effectively mirror-only**

Deploy:

```text
daftar-sync (updated internal auth)
daftar-live-read (new)
```

Both must be ACTIVE. `daftar-live-read` uses `verify_jwt = false` at the platform layer and manually rejects missing/invalid user bearer tokens.

- [ ] **Step 4: Enable shadow mode**

Run:

```sql
update public.daftar_sync_sources
set live_read_mode = 'shadow',
    updated_at = now()
where legacy_user_id = 28
  and source_fingerprint = 'daftar-live-account-28-v1';
```

In shadow mode, exercise the supported operations through a real signed-in ZHIROX session. Do not impersonate the user by weakening function auth.

Verify telemetry:

```sql
select operation, result_source, status, fallback_reason,
       live_status, live_latency_ms, total_latency_ms, mirror_age_ms
from public.daftar_live_read_events
where sync_source_id = (
  select id from public.daftar_sync_sources
  where legacy_user_id = 28
    and source_fingerprint = 'daftar-live-account-28-v1'
  limit 1
)
order by created_at desc
limit 50;
```

Expected: live validations succeed and existing reconciliation/rehearsal stay clean.

- [ ] **Step 5: Re-run financial safety checks before live mode**

Run:

```sql
select
  reconciliation_status,
  reconciliation_missing_contacts,
  reconciliation_missing_transactions,
  cutover_rehearsal_status,
  cutover_rehearsal_mismatches,
  failover_ready,
  outage_status,
  sync_mode,
  enabled
from public.daftar_sync_sources
where legacy_user_id = 28
  and source_fingerprint = 'daftar-live-account-28-v1';
```

Required:

```text
reconciliation_status = clean
reconciliation_missing_contacts = 0
reconciliation_missing_transactions = 0
cutover_rehearsal_status = pass
cutover_rehearsal_mismatches = 0
failover_ready = true
outage_status = healthy
sync_mode = mirror
enabled = true
```

- [ ] **Step 6: Enable live mode**

Only after Step 5 passes:

```sql
update public.daftar_sync_sources
set live_read_mode = 'live',
    updated_at = now()
where legacy_user_id = 28
  and source_fingerprint = 'daftar-live-account-28-v1';
```

Use the signed-in app to load:

```text
customer directory
customer finance snapshot
customer financial timeline
debt detail + payments
customer statement
admin dashboard
admin statement/report reads
```

Verify telemetry reports `result_source = live` under healthy Daftar conditions.

- [ ] **Step 7: Prove transient live failure falls back without source-of-truth cutover**

Use the deterministic `runtime_test.ts` dependency-injection path; do **not** mutate the production Daftar URL or production failure counters. Run this exact integration test after deployment code is finalized:

```ts
Deno.test("live timeout serves mirror and never activates primary mode", async () => {
  const state = { syncMode: "mirror", primaryActivated: false };
  const response = await runFixture({
    liveFailure: { kind: "timeout" },
    mirrorData: { items: [{ id: "normalized-zhirox-id" }] },
    sourceState: state,
  });

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.source, "mirror");
  assertEquals(body.fallback_reason, "source_timeout");
  assertEquals(body.data.items[0].id, "normalized-zhirox-id");
  assertEquals(state.syncMode, "mirror");
  assertEquals(state.primaryActivated, false);
});
```

Then query production state immediately after the test suite to prove no deployment step changed source-of-truth state.

Required response:

```json
{
  "ok": true,
  "source": "mirror",
  "stale": false,
  "fallback_reason": "source_timeout",
  "data": {}
}
```

Immediately verify production source-of-truth state is unchanged:

```sql
select sync_mode, enabled, primary_activated_at, outage_status
from public.daftar_sync_sources
where legacy_user_id = 28
  and source_fingerprint = 'daftar-live-account-28-v1';
```

Required:

```text
sync_mode = mirror
enabled = true
primary_activated_at = null
outage_status = healthy
```

Do not simulate production outage by persisting fake failure counters outside a transaction.

- [ ] **Step 8: Verify non-fallback failures**

Run the Deno integration fixtures for 401, 403, malformed payload, unsupported operation, and wrong tenant.

Required: each returns structured error and **does not** return `source = mirror`.

- [ ] **Step 9: Verify GitHub Actions and iOS artifact**

Wait for the `iOS Unsigned IPA` run on the final commit.

Required successful steps:

```text
Verify Daftar Qarz connection lock
Verify Daftar raw mirror
Verify Daftar shadow reconciliation
Verify Daftar cutover rehearsal
Verify Daftar failover readiness
Verify Daftar outage qualification
Verify Daftar read-path independence
Verify Daftar live-primary reads
Test Daftar live-read Edge Function
Check Daftar live-read Edge Function
Analyze strictly
Run tests
Build iOS without signing
Publish permanent IPA download
```

Do not report completion until the workflow conclusion is `success`.

- [ ] **Step 10: Final production verification**

Query:

```sql
select
  live_read_mode,
  sync_mode,
  enabled,
  health_status,
  consecutive_failures,
  reconciliation_status,
  reconciliation_missing_contacts,
  reconciliation_missing_transactions,
  cutover_rehearsal_status,
  cutover_rehearsal_mismatches,
  failover_ready,
  outage_status
from public.daftar_sync_sources
where legacy_user_id = 28
  and source_fingerprint = 'daftar-live-account-28-v1';
```

Required final state:

```text
live_read_mode = live
sync_mode = mirror
enabled = true
health_status = healthy
consecutive_failures = 0
reconciliation_status = clean
reconciliation_missing_contacts = 0
reconciliation_missing_transactions = 0
cutover_rehearsal_status = pass
cutover_rehearsal_mismatches = 0
failover_ready = true
outage_status = healthy
```

Document the final commit SHA, Edge Function versions, GitHub Actions run number/ID, IPA asset name, and live/fallback telemetry evidence in the completion message.
