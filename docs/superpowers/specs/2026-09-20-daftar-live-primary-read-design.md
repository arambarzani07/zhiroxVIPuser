# Daftar Qarz Live-Primary Read Architecture

Date: 2026-09-20  
Repository: `arambarzani07/zhiroxVIPuser`  
Branch: `user-source`  
Status: Design approved in chat; implementation pending written-spec approval.

## 1. Goal

While Daftar Qarz remains available, ZHIROX should use Daftar Qarz as the **primary live read source** for the data that originates there, without exposing Daftar credentials or coupling the mobile client directly to the external API.

If Daftar Qarz is temporarily unavailable, ZHIROX must continue operating by reading the already-maintained ZHIROX/Supabase mirror. The fallback must not delete, mutate, or reinterpret mirrored data.

The transition must preserve the existing migration path in which ZHIROX can later become the independent source of truth.

## 2. Success Criteria

The design is successful when all of the following are true:

1. Customer, debt, and payment reads that depend on Daftar Qarz prefer the live Daftar API.
2. The Flutter/iOS client never contains Daftar API secrets and never calls the Daftar host directly.
3. Live reads are routed through a server-side Supabase Edge Function.
4. When the Daftar API is unavailable because of transport, timeout, rate-limit, or upstream server failure, the same read transparently falls back to the ZHIROX mirror.
5. Authentication, tenant scoping, and account-28 scoping are enforced server-side.
6. Existing mirror, reconciliation, cutover rehearsal, failover readiness, outage qualification, and guardian protections remain active.
7. Writes are not silently redirected to Daftar. ZHIROX write behavior remains unchanged until a separate, explicitly verified Daftar write API design exists.
8. Every response identifies whether it came from `live` or `mirror` and includes a freshness timestamp.
9. CI prevents future code changes from bypassing the gateway or leaking Daftar credentials into the client.
10. Existing ZHIROX screens continue to work during a Daftar outage.

## 3. Architecture

The read path becomes:

```
Flutter / ZHIROX
      |
      | authenticated Supabase request
      v
Supabase Edge Function: daftar-live-read
      |
      | server-side account/tenant authorization
      |
      +----------------------+
      |                      |
      v                      v
Daftar Qarz Live API      ZHIROX Mirror
(primary)                 (fallback)
      |                      |
      +----------+-----------+
                 |
                 v
          Normalized DTO
                 |
                 v
          Flutter / ZHIROX
```

The client treats `daftar-live-read` as the only interface for Daftar-originated live reads.

The external Daftar host remains private to server-side code.

## 4. Components

### 4.1 `daftar-live-read` Edge Function

Create a new Supabase Edge Function dedicated to authenticated live reads.

Responsibilities:

- validate the caller's Supabase user JWT;
- resolve the caller's admin/market identity;
- verify the caller belongs to the allowed Daftar source;
- resolve the protected Daftar source definition for account 28;
- call the Daftar API server-side;
- normalize Daftar payloads into stable ZHIROX DTOs;
- apply strict timeouts and bounded retries;
- classify errors as fallback-eligible or non-fallback-eligible;
- read the ZHIROX mirror only when fallback is allowed;
- return source/freshness metadata with every response;
- never return secrets, trigger hashes, service keys, or raw server configuration.

The function should use a pinned Supabase client version and the existing server-side secret handling patterns.

### 4.2 Live API Adapter

Keep external Daftar-specific parsing isolated behind a small adapter.

Supported operations in this phase:

- list/search customers;
- fetch one customer snapshot;
- fetch customer transactions;
- read live debt/payment history needed by the ZHIROX customer/account views.

The adapter owns Daftar-specific field names and transforms them into stable ZHIROX field names.

The Flutter client must not know Daftar's raw schema.

### 4.3 Mirror Adapter

The fallback adapter reads only from the existing durable ZHIROX mirror and normalized ZHIROX tables.

It must:

- preserve tenant/admin scoping;
- return the same DTO shape as the live adapter;
- include the mirror's last mirrored timestamp;
- never trigger a cutover;
- never alter balances while serving a fallback read.

### 4.4 Flutter Read Service

Add a focused client service such as `DaftarLiveReadService`.

Responsibilities:

- invoke only `daftar-live-read`;
- expose typed read methods to screens/providers;
- expose `source`, `asOf`, and fallback state;
- map structured backend errors to existing UI error handling.

Screens should depend on this service, not on HTTP URLs or Daftar-specific payloads.

## 5. Data Source Rules

### Primary source

When Daftar is reachable and returns a valid authorized response:

- return the live Daftar result;
- set `source = "live"`;
- set `as_of` to the time of the successful live response.

### Fallback source

Fallback is allowed only for operational upstream failures such as:

- network/connectivity failure;
- request timeout;
- HTTP 408;
- HTTP 425;
- HTTP 429 after bounded retry;
- HTTP 5xx;
- verified upstream unavailability.

Fallback must not hide:

- authentication failures;
- authorization/tenant failures;
- malformed or invalid source configuration;
- unsupported operation errors;
- data-integrity errors that indicate an incompatible Daftar response.

When fallback is used:

- return the most recent mirror data;
- set `source = "mirror"`;
- include `fallback_reason`;
- include `as_of = mirror last-mirrored time`;
- include a boolean `stale` based on a documented freshness threshold.

## 6. Response Contract

Every successful response should have a stable envelope:

```json
{
  "ok": true,
  "source": "live",
  "as_of": "2026-09-20T00:00:00Z",
  "stale": false,
  "fallback_reason": null,
  "data": {}
}
```

Fallback example:

```json
{
  "ok": true,
  "source": "mirror",
  "as_of": "2026-09-19T23:59:00Z",
  "stale": false,
  "fallback_reason": "source_timeout",
  "data": {}
}
```

The DTO inside `data` must be identical for live and mirror reads.

## 7. Security

### Client

The Flutter client may contain:

- Supabase publishable configuration already appropriate for the app;
- authenticated user session/JWT.

The Flutter client must never contain:

- Daftar API secrets;
- service-role keys;
- Vault secrets;
- trigger secrets;
- raw privileged Daftar configuration.

### Server

The server-side function must:

- validate the user JWT;
- authorize the caller against ZHIROX profile/admin ownership;
- lock the request to the configured Daftar source for account 28;
- reject caller-supplied alternate `legacy_user_id`, API base URL, or source ID unless the source ID is resolved server-side from the caller's tenant;
- use constant-time comparison for any dedicated secret comparison that remains necessary;
- keep service credentials in Supabase-managed secrets/Vault;
- return generic structured errors without secret-bearing details.

### Database

Existing RLS and service-only tables remain protected.

No new public table access is required for the mobile client; the client reads through the Edge Function and existing authorized RPCs.

## 8. Reliability

### Timeouts

Use a short live-read deadline appropriate for interactive UI. The implementation plan should target approximately 5–8 seconds total before fallback, with bounded retry only for explicitly transient failures.

### Retry

Retries must be bounded and must not multiply latency excessively. A practical target is:

- initial request;
- at most one quick retry for transient failures;
- then mirror fallback.

### Mirror continuity

The existing one-minute mirror pipeline remains active while `sync_mode = "mirror"`.

The following protections remain unchanged:

- connection lock;
- guardian cron;
- raw mirror;
- shadow reconciliation;
- cutover rehearsal;
- failover readiness;
- outage qualification.

Live reads do not replace the mirror pipeline.

## 9. Read / Write Boundary

This design changes **reads only**.

Writes remain on the current ZHIROX path.

No create/update/payment action will write to Daftar until a separate write architecture proves:

- the Daftar write endpoints are authorized and stable;
- idempotency is supported or safely emulated;
- conflict handling is defined;
- duplicate financial operations cannot occur;
- write acknowledgements can be reconciled with the mirror.

This prevents a read-source change from silently becoming a two-way financial sync.

## 10. UI Behavior

Normal operation should not require a disruptive banner.

The UI may show lightweight status metadata where useful:

- `Live` when the response came from Daftar;
- `Mirror` / `Fallback` when serving cached mirrored data;
- last-updated time when on fallback.

A Daftar outage must not convert ordinary customer/debt/payment screens into a global error page if usable mirror data exists.

If both live and mirror reads fail, use the existing structured backend error UI.

## 11. Observability

Record read-path metrics without storing secrets:

- operation name;
- live success/failure;
- live latency;
- fallback count;
- fallback reason;
- mirror age;
- tenant/source ID;
- timestamp.

Do not log:

- secrets;
- bearer tokens;
- service keys;
- full sensitive payloads.

The admin sync dashboard can later expose aggregate live/fallback health, but that UI enhancement is not required for the initial implementation.

## 12. CI / Regression Contracts

Add regression checks that fail the build if:

1. any Dart file contains the Daftar API host;
2. any Dart file calls Daftar directly;
3. any Dart file contains a Daftar secret/header value;
4. live-read DTOs differ between live and mirror adapters;
5. fallback is triggered for auth/authorization/data-integrity failures;
6. tenant/account-28 scoping is removed;
7. the mirror/guardian/reconciliation/failover protections are removed;
8. the Edge Function fails strict Deno type-checking.

Tests must cover at least:

- live success;
- live timeout -> mirror fallback;
- live 5xx -> mirror fallback;
- live 429 -> bounded retry -> mirror fallback;
- 401/403 -> no fallback;
- wrong tenant/source -> reject;
- malformed live payload -> structured failure, not silent fallback;
- mirror unavailable after live failure -> structured error;
- identical DTO shape for live and mirror responses;
- no secret exposure.

## 13. Rollout

Deploy incrementally.

### Stage A: server-only

- deploy `daftar-live-read`;
- verify live reads against account 28;
- verify mirror fallback with controlled tests;
- do not change production screens yet.

### Stage B: shadow comparison

For selected reads:

- request live data server-side;
- compare normalized live results with mirror results;
- log differences;
- continue returning current production data.

Proceed only when the comparison is clean for the agreed observation window.

### Stage C: live-primary client reads

Move selected customer/debt/payment screens to `DaftarLiveReadService`.

Live becomes primary; mirror becomes operational fallback.

### Stage D: expand coverage

Move remaining Daftar-originated read surfaces only after the earlier surfaces remain stable.

At no point in this rollout does the system automatically switch to `zhirox_primary` merely because live read fallback occurred.

## 14. Interaction With Future Source-of-Truth Cutover

The existing failover/cutover machinery remains a separate concern.

A temporary read fallback means:

```
live read failed -> serve mirror -> keep sync_mode = mirror
```

A real source-of-truth transition requires the existing guarded process:

```
sustained outage
+ outage qualification
+ failover_ready
+ reconciliation clean
+ financial rehearsal pass
+ explicit guarded activation
-> sync_mode = zhirox_primary
```

Therefore normal API instability cannot accidentally promote ZHIROX to primary.

## 15. Non-Goals

This phase does not:

- implement two-way writes to Daftar;
- remove the mirror;
- remove reconciliation;
- remove the guardian;
- automatically cut over on a single API failure;
- expose Daftar credentials to Flutter;
- redesign unrelated screens;
- replace Supabase Auth.

## 16. Acceptance Criteria

Implementation is complete only when:

- all relevant live reads go through the server-side gateway;
- Daftar is demonstrably the primary source for those reads while healthy;
- mirror fallback is demonstrably used on qualified live-read failures;
- Flutter contains no Daftar host or secret;
- live and mirror DTOs are contract-compatible;
- auth and tenant tests pass;
- existing Daftar connection-lock/mirror/reconciliation/rehearsal/failover tests still pass;
- strict Deno checks pass;
- Flutter analyze/tests pass;
- iOS build passes;
- a controlled live-failure test proves the app still returns mirror data without changing `sync_mode`.
