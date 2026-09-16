# Customer QR Web Push Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add secure customer-specific QR linking and Web Push notifications for newly created debts and newly recorded payments without Viber, Telegram, SMS, email, KYC, or a third-party messaging provider.

**Architecture:** Supabase remains the trusted backend. Staff generate short-lived one-time customer QR links through an authenticated Edge Function; a public token-gated PWA endpoint registers browser Push API subscriptions; financial create paths enqueue immutable events into a database outbox; a scheduled Edge Function fans those events out to linked devices with VAPID Web Push, idempotency, retry, and audit logging. Flutter only manages status/QR/revoke UI and never receives server secrets.

**Tech Stack:** Flutter/Dart 3.10+, `supabase_flutter`, PostgreSQL/RLS/PLpgSQL, Supabase Edge Functions on Deno, `npm:web-push@3.6.7`, `qr_flutter`, Web Push API, Service Worker API, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-17-customer-qr-web-push-design.md`

## Global Constraints

- Work only on branch `user-source`.
- QR link lifetime is exactly 15 minutes.
- QR links are one-time use and the database stores only a SHA-256 hash of the raw token.
- New-debt and new-payment are the only Web Push event types in the first release.
- Debt/payment edits, deletions, due reminders, imports, restores, legacy sync, marketing, Viber, SMS, email, and new Telegram behavior must not produce Web Push events.
- Existing in-app/local notifications and existing Telegram behavior must remain unchanged.
- A successful financial transaction must never be rolled back or surfaced as failed because Web Push enqueue or delivery failed.
- One customer may link multiple devices; one browser push endpoint may have only one active customer association.
- `market_id` in the new push tables means the tenant admin profile UUID used by the existing `admin_id` tenancy model.
- Employees may manage customer push links only when `can_send_notifications = true`; active approved admins may always manage them.
- VAPID private key, worker secret, rate-limit salt, subscription `p256dh`, subscription `auth`, and device-secret hashes stay server-side.
- iPhone/iPad onboarding must support the Home Screen web-app requirement before requesting notification permission.
- Retry schedule per device is fixed to immediate, +1 minute, +5 minutes, +30 minutes, +2 hours, then terminal failure.
- Notification click opens the generic ZHIROX Notifications PWA landing page; it must not place a raw `customer_id` in the URL.
- CI must preserve the existing online-only, FIB payment, auto-update, payment-total, Flutter analyze/test, and iOS unsigned IPA checks.

---

## File Structure Map

### New backend files
- `supabase/migrations/20260917013000_customer_qr_web_push.sql` — tables, indexes, RLS, grants, push management RPCs, outbox claim/retry helpers, rate limiting.
- `supabase/tests/customer_qr_web_push_regression.sql` — database security, tenancy, token, outbox, and delivery invariants.
- `supabase/functions/_shared/customer_push/crypto.ts` — token/hash helpers.
- `supabase/functions/_shared/customer_push/payload.ts` — notification copy and pure retry/status classification.
- `supabase/functions/_shared/customer_push/payload_test.ts` — Deno unit tests for pure delivery logic.
- `supabase/functions/customer-push-admin/index.ts` — authenticated create-link/status/revoke-all API.
- `supabase/functions/customer-push/index.ts` — public onboarding HTML/PWA manifest/service worker plus token validation/subscribe/unsubscribe API.
- `supabase/functions/customer-push-worker/index.ts` — privileged outbox worker and live-debt reconciliation.
- `supabase/functions/customer-push-events/index.ts` — authenticated live debt enqueue endpoint.

### New Flutter files
- `lib/services/customer_push_service.dart` — typed gateway for admin push APIs.
- `lib/widgets/customer_push_card.dart` — customer profile status, QR, and revoke UI.
- `test/customer_push_service_test.dart` — response parsing/domain tests.
- `test/customer_push_card_test.dart` — widget behavior with fake gateway.

### Existing files modified
- `supabase/functions/record-payment/index.ts` — enqueue one logical `payment_created` event after successful payment commit.
- `supabase/config.toml` — mark public onboarding and worker functions as `verify_jwt = false` while preserving application-level guards.
- `lib/services/pb_service.dart` — enqueue a live debt event after a successful debt insert without making the financial save depend on push.
- `lib/screens/shared/user_profile_screen.dart` — mount `CustomerPushCard` for authorized staff viewing a customer.
- `pubspec.yaml` / `pubspec.lock` — add `qr_flutter`.
- `scripts/verify_customer_push.py` — static safety checks for secrets, function config, and event scope.
- `.github/workflows/ios-unsigned-ipa.yml` — run customer-push verification and Deno unit tests before Flutter analyze/build.

---

### Task 1: Database schema, tenancy, token redemption, and outbox primitives

**Files:**
- Create: `supabase/migrations/20260917013000_customer_qr_web_push.sql`
- Create: `supabase/tests/customer_qr_web_push_regression.sql`

**Interfaces:**
- Consumes: existing `public.profiles`, `public.debts`, `public.payments`, `public.legacy_import_links`, `public.daftar_sync_seen`.
- Produces:
  - `public.customer_push_link_tokens`
  - `public.customer_push_subscriptions`
  - `public.notification_outbox`
  - `public.notification_deliveries`
  - `public.customer_push_rate_limits`
  - `public.manage_customer_push_link(p_actor uuid, p_customer uuid, p_token_hash text, p_expires_at timestamptz) returns jsonb`
  - `public.customer_push_status_service(p_actor uuid, p_customer uuid) returns jsonb`
  - `public.revoke_customer_push_subscriptions_service(p_actor uuid, p_customer uuid) returns integer`
  - `public.redeem_customer_push_subscription_service(p_token_hash text, p_endpoint text, p_p256dh text, p_auth text, p_device_secret_hash text, p_user_agent text, p_platform text) returns jsonb`
  - `public.unsubscribe_customer_push_subscription_service(p_endpoint text, p_device_secret_hash text) returns boolean`
  - `public.consume_customer_push_rate_limit(p_key_hash text, p_limit integer, p_window_seconds integer) returns boolean`
  - `public.enqueue_customer_push_event_service(p_market_id uuid, p_customer_id uuid, p_event_type text, p_event_record_id uuid, p_idempotency_key text, p_payload jsonb) returns uuid`
  - `public.claim_customer_push_outbox(p_limit integer) returns setof public.notification_outbox`

- [ ] **Step 1: Write the failing SQL regression test**

Create `supabase/tests/customer_qr_web_push_regression.sql` with explicit assertions for the new objects before the migration exists:

```sql
begin;

select plan(14);

select has_table('public', 'customer_push_link_tokens', 'push link token table exists');
select has_table('public', 'customer_push_subscriptions', 'push subscriptions table exists');
select has_table('public', 'notification_outbox', 'notification outbox exists');
select has_table('public', 'notification_deliveries', 'notification deliveries exists');
select has_table('public', 'customer_push_rate_limits', 'public rate limit table exists');

select has_function(
  'public',
  'manage_customer_push_link',
  array['uuid','uuid','text','timestamp with time zone'],
  'push link management RPC exists'
);
select has_function(
  'public',
  'redeem_customer_push_subscription_service',
  array['text','text','text','text','text','text','text'],
  'subscription redemption RPC exists'
);
select has_function(
  'public',
  'enqueue_customer_push_event_service',
  array['uuid','uuid','text','uuid','text','jsonb'],
  'outbox enqueue RPC exists'
);

select col_is_pk('public', 'customer_push_link_tokens', 'id', 'token row has primary key');
select col_not_null('public', 'customer_push_link_tokens', 'token_hash', 'token hash is required');
select col_not_null('public', 'customer_push_subscriptions', 'device_secret_hash', 'device unlink secret hash is required');
select col_not_null('public', 'notification_outbox', 'idempotency_key', 'outbox key is required');
select col_not_null('public', 'notification_deliveries', 'subscription_id', 'delivery subscription is required');
select table_privs_are(
  'public', 'customer_push_subscriptions', 'authenticated', array[]::text[],
  'ordinary authenticated clients have no direct subscription-table privileges'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run the SQL test and verify RED**

Run against a disposable/local Supabase database:

```bash
supabase db reset
psql "$LOCAL_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/customer_qr_web_push_regression.sql
```

Expected: FAIL because the five tables and RPCs do not exist.

- [ ] **Step 3: Implement the schema and hard security boundary**

Create the migration with these concrete table rules:

```sql
create table public.customer_push_link_tokens (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  token_hash text not null unique check (token_hash ~ '^[a-f0-9]{64}$'),
  expires_at timestamptz not null,
  used_at timestamptz,
  revoked_at timestamptz,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.customer_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth text not null,
  device_secret_hash text not null check (device_secret_hash ~ '^[a-f0-9]{64}$'),
  user_agent text,
  platform text,
  active boolean not null default true,
  last_success_at timestamptz,
  last_failure_at timestamptz,
  failure_count integer not null default 0 check (failure_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index customer_push_active_endpoint_uq
  on public.customer_push_subscriptions(endpoint)
  where active = true;

create table public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  event_type text not null check (event_type in ('debt_created','payment_created')),
  event_record_id uuid not null,
  idempotency_key text not null unique,
  payload jsonb not null,
  status text not null default 'pending'
    check (status in ('pending','processing','completed','failed')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  next_attempt_at timestamptz not null default now(),
  last_error text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create table public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  outbox_id uuid not null references public.notification_outbox(id) on delete cascade,
  subscription_id uuid not null references public.customer_push_subscriptions(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','sent','failed','expired')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  provider_status integer,
  last_error text,
  next_attempt_at timestamptz,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (outbox_id, subscription_id)
);

create table public.customer_push_rate_limits (
  key_hash text primary key check (key_hash ~ '^[a-f0-9]{64}$'),
  window_started_at timestamptz not null default now(),
  request_count integer not null default 0 check (request_count >= 0),
  expires_at timestamptz not null
);
```

Enable RLS on all five tables, revoke all table privileges from `public`, `anon`, and `authenticated`, and grant only `service_role` the table privileges the Edge Functions need. Keep all service RPCs `security definer set search_path = ''`, revoke execution from `public/anon/authenticated`, and grant execution only to `service_role`.

Use one shared actor-scope rule in each staff RPC: active approved admin is allowed for its own tenant; active approved employee is allowed only when `admin_id = market_id` and `can_send_notifications = true`.

`manage_customer_push_link` must revoke previous unused/unexpired links for the same `market_id/customer_id`, then insert exactly the provided hash and expiry. It returns only `{customer_id, market_id, expires_at}`.

`redeem_customer_push_subscription_service` must lock the token row with `for update`, reject `used_at`, `revoked_at`, or `expires_at <= now()`, verify the token customer is still active/approved, and then either update an existing active endpoint for the same customer or insert a new subscription. If the endpoint is actively linked to another customer, raise `endpoint_already_linked`. Mark `used_at = now()` only after the subscription write succeeds.

`unsubscribe_customer_push_subscription_service` must match both endpoint and SHA-256 device-secret hash before setting `active=false`.

`enqueue_customer_push_event_service` must reject all event types except the two allowed values and insert with `on conflict (idempotency_key) do update set idempotency_key = excluded.idempotency_key returning id`; this makes repeated enqueue calls return the original event id without changing the immutable payload.

`claim_customer_push_outbox` must use `for update skip locked`, select at most `p_limit` rows whose `status in ('pending','processing')` and `next_attempt_at <= now()`, set them to `processing`, and return the claimed rows.

`consume_customer_push_rate_limit` must atomically reset the window after `p_window_seconds`, increment within an active window, reject after `p_limit`, and opportunistically delete rows with `expires_at < now() - interval '1 day'`.

- [ ] **Step 4: Extend the SQL test with behavioral assertions**

Add fixtures for one admin, one employee with `can_send_notifications=true`, one employee with the permission disabled, and two customers in different tenants. Assert:

```sql
-- Pseudocode only for fixture IDs; use fixed UUID literals in the actual test.
-- 1. permitted actor can create link for same-tenant customer
-- 2. actor without can_send_notifications is rejected
-- 3. cross-tenant customer is rejected
-- 4. token cannot be redeemed twice
-- 5. expired token is rejected
-- 6. second active endpoint for same customer is allowed
-- 7. same active endpoint cannot link to another customer
-- 8. duplicate idempotency key returns one outbox row
-- 9. event_type='debt_updated' is rejected
-- 10. duplicate outbox/subscription delivery pair is rejected
```

Implement those as executable SQL assertions using `lives_ok`, `throws_ok`, and row-count checks rather than comments in the committed test.

- [ ] **Step 5: Run database regression tests and verify GREEN**

```bash
supabase db reset
psql "$LOCAL_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/customer_qr_web_push_regression.sql
```

Expected: all assertions PASS.

- [ ] **Step 6: Commit Task 1**

```bash
git add supabase/migrations/20260917013000_customer_qr_web_push.sql \
        supabase/tests/customer_qr_web_push_regression.sql
git commit -m "feat(user): add customer push data model"
```

---

### Task 2: Pure crypto/payload helpers and authenticated staff API

**Files:**
- Create: `supabase/functions/_shared/customer_push/crypto.ts`
- Create: `supabase/functions/_shared/customer_push/payload.ts`
- Create: `supabase/functions/_shared/customer_push/payload_test.ts`
- Create: `supabase/functions/customer-push-admin/index.ts`

**Interfaces:**
- Consumes: Task 1 service-role RPCs.
- Produces:
  - `randomHexToken(byteLength = 32): string`
  - `sha256Hex(value: string): Promise<string>`
  - `formatPushBody(eventType: 'debt_created'|'payment_created', payload: PushPayload): {title:string, body:string}`
  - authenticated `customer-push-admin` actions `create_link`, `status`, `revoke_all`.

- [ ] **Step 1: Write failing Deno tests for pure helpers**

```ts
import { assertEquals, assertMatch } from "jsr:@std/assert@1";
import { retryDelaySeconds, formatPushBody } from "./payload.ts";
import { randomHexToken, sha256Hex } from "./crypto.ts";

Deno.test("token is 32 random bytes encoded as 64 hex chars", () => {
  assertMatch(randomHexToken(), /^[a-f0-9]{64}$/);
});

Deno.test("sha256 helper is stable", async () => {
  assertEquals(
    await sha256Hex("zhirox"),
    "ae300c4d34a7d750bdb9f63ce0c342d99393690b115f3e5278eb54e497242a49",
  );
});

Deno.test("retry schedule is bounded", () => {
  assertEquals([1,2,3,4,5,6].map(retryDelaySeconds), [0,60,300,1800,7200,null]);
});

Deno.test("payment copy contains total payment and remaining balance", () => {
  assertEquals(
    formatPushBody("payment_created", {
      amount: 25000,
      currency: "IQD",
      remaining: 100000,
      market_name: "ZHIROX Market",
      occurred_at: "2026-09-17T00:00:00Z",
    }),
    {
      title: "💰 پارەدانەوە تۆمارکرا",
      body: "بڕی دراو: 25,000 د.ع • ماوە: 100,000 د.ع • مارکێت: ZHIROX Market",
    },
  );
});
```

- [ ] **Step 2: Run helper tests and verify RED**

```bash
deno test supabase/functions/_shared/customer_push/payload_test.ts
```

Expected: FAIL because helper modules do not exist.

- [ ] **Step 3: Implement minimal helper modules**

`crypto.ts` must use Web Crypto only:

```ts
export function randomHexToken(byteLength = 32): string {
  return Array.from(crypto.getRandomValues(new Uint8Array(byteLength)))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
```

`payload.ts` must define the fixed retry schedule and Sorani copy. Currency formatting accepts IQD and USD, uses thousands separators, and never includes customer IDs or internal notes.

- [ ] **Step 4: Run helper tests and verify GREEN**

```bash
deno test supabase/functions/_shared/customer_push/payload_test.ts
```

Expected: PASS.

- [ ] **Step 5: Implement `customer-push-admin` with exact action contracts**

Use the existing Edge Function auth pattern (`SUPABASE_SECRET_KEYS` fallback to `SUPABASE_SERVICE_ROLE_KEY`, `admin.auth.getUser(bearer)`), then call Task 1 RPCs.

Request/response contracts:

```ts
// create_link request
{ action: "create_link", customer_id: "uuid" }

// create_link response
{
  url: "https://<project>.supabase.co/functions/v1/customer-push?token=<raw-64-hex>",
  expires_at: "ISO-8601"
}

// status request
{ action: "status", customer_id: "uuid" }

// status response
{
  active: true,
  device_count: 2,
  latest_status: "sent",
  latest_at: "ISO-8601-or-null"
}

// revoke_all request
{ action: "revoke_all", customer_id: "uuid" }

// revoke_all response
{ revoked: 2 }
```

For `create_link`, generate `rawToken = randomHexToken()`, hash it with `sha256Hex`, set `expiresAt = new Date(Date.now() + 15 * 60 * 1000)`, call `manage_customer_push_link`, and return the raw token only inside the HTTPS URL. Do not log it.

Use generic `forbidden` for tenancy/permission failures. Do not return subscription endpoints or key material from `status`.

- [ ] **Step 6: Add request-shape tests as pure exported handler tests**

Refactor the function body so `handleAdminAction(body, actorId, deps)` is injectable. Test invalid action, invalid UUID, 15-minute expiry construction, and that returned URL contains the raw token while the RPC receives only its hash.

Run:

```bash
deno test supabase/functions/customer-push-admin
```

Expected: PASS without network access by using fake dependencies.

- [ ] **Step 7: Commit Task 2**

```bash
git add supabase/functions/_shared/customer_push \
        supabase/functions/customer-push-admin
git commit -m "feat(user): add customer push admin API"
```

---

### Task 3: Public onboarding PWA, service worker, subscribe and unsubscribe

**Files:**
- Create: `supabase/functions/customer-push/index.ts`
- Modify: `supabase/config.toml`
- Test: `supabase/functions/customer-push/index_test.ts`

**Interfaces:**
- Consumes: `sha256Hex`, `randomHexToken`, Task 1 `redeem_customer_push_subscription_service`, `unsubscribe_customer_push_subscription_service`, `consume_customer_push_rate_limit`.
- Produces public routes under `/functions/v1/customer-push`:
  - `GET ?token=<raw>` onboarding HTML
  - `GET /manifest.webmanifest?token=<raw>` dynamic PWA manifest
  - `GET /sw.js` service worker
  - `POST {action:"validate", token}`
  - `POST {action:"subscribe", token, subscription, platform}`
  - `POST {action:"unsubscribe", endpoint, device_secret}`

- [ ] **Step 1: Write failing route tests**

Create exported `routeCustomerPush(req, deps)` and test:

```ts
Deno.test("onboarding never embeds a customer id", async () => {
  const response = await routeCustomerPush(
    new Request("https://x/functions/v1/customer-push?token=" + "a".repeat(64)),
    fakeDeps,
  );
  const html = await response.text();
  assertEquals(response.status, 200);
  assertEquals(html.includes("customer_id"), false);
  assertEquals(html.includes("چالاککردنی ئاگادارکردنەوە"), true);
});

Deno.test("subscribe requires endpoint p256dh and auth", async () => {
  const response = await routeCustomerPush(
    new Request("https://x/functions/v1/customer-push", {
      method: "POST",
      headers: {"content-type":"application/json"},
      body: JSON.stringify({action:"subscribe", token:"a".repeat(64), subscription:{}}),
    }),
    fakeDeps,
  );
  assertEquals(response.status, 400);
});
```

- [ ] **Step 2: Run route tests and verify RED**

```bash
deno test supabase/functions/customer-push/index_test.ts
```

Expected: FAIL because the route module does not exist.

- [ ] **Step 3: Implement token-gated validation and rate limiting**

Resolve client IP from `cf-connecting-ip` then first `x-forwarded-for` value. Compute:

```ts
const rateKey = await sha256Hex(`${Deno.env.get("CUSTOMER_PUSH_RATE_LIMIT_SALT")}:${clientIp}`);
```

Call `consume_customer_push_rate_limit(rateKey, 30, 60)` for `validate` and `subscribe`; return `429` with `{error:"rate_limited"}` when rejected. Invalid, expired, used, and revoked tokens must all return the same `{error:"link_unavailable"}` response.

`validate` may return only:

```ts
{
  market_name: string,
  customer_name: string,
  expires_at: string,
  vapid_public_key: string
}
```

- [ ] **Step 4: Implement safe subscription registration**

Accept the browser PushSubscription JSON:

```ts
{
  endpoint: string,
  keys: { p256dh: string, auth: string }
}
```

Generate a new 32-byte raw `deviceSecret`, hash it, call `redeem_customer_push_subscription_service`, and return:

```ts
{ linked: true, device_secret: deviceSecret }
```

The PWA stores `device_secret` in `localStorage` only after the server confirms linking. Never place the secret in notification payloads or URLs.

For `unsubscribe`, require endpoint plus raw device secret, hash it, and call `unsubscribe_customer_push_subscription_service`.

- [ ] **Step 5: Implement onboarding HTML and dynamic manifest**

The HTML must:
- show ZHIROX branding and server-confirmed customer/market names only after `validate` succeeds;
- detect iOS with user agent plus standalone mode;
- when iOS is not standalone, show Add-to-Home-Screen instructions and do not call `Notification.requestPermission()`;
- when standalone or non-iOS, enable the explicit **چالاککردنی ئاگادارکردنەوە** button;
- register `/functions/v1/customer-push/sw.js` with scope `/functions/v1/customer-push/`;
- call `registration.pushManager.subscribe({userVisibleOnly:true, applicationServerKey: ...})` only after explicit button tap;
- POST the subscription to `action=subscribe`;
- show deterministic states for denied permission, expired link, temporary network error, and success.

Serve manifest JSON with the current raw token encoded only in the `start_url`:

```json
{
  "name": "ZHIROX Notifications",
  "short_name": "ZHIROX",
  "display": "standalone",
  "start_url": "/functions/v1/customer-push?token=<url-encoded-token>",
  "scope": "/functions/v1/customer-push/",
  "theme_color": "#ffffff",
  "background_color": "#ffffff"
}
```

Do not add a separate hosting provider.

- [ ] **Step 6: Implement the service worker**

`GET /sw.js` returns JavaScript with `Content-Type: application/javascript`, `Cache-Control: no-store`, and `Service-Worker-Allowed: /functions/v1/customer-push/`.

The script must:

```js
self.addEventListener('push', event => {
  const data = event.data ? event.data.json() : {};
  event.waitUntil(self.registration.showNotification(data.title || 'ZHIROX', {
    body: data.body || '',
    icon: data.icon || '/favicon.ico',
    data: { url: data.url || '/functions/v1/customer-push' }
  }));
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil(clients.openWindow(event.notification.data.url));
});
```

Notification URL must be the generic PWA landing path without customer ID.

- [ ] **Step 7: Configure only this public function as no-JWT**

Append to `supabase/config.toml`:

```toml
[functions.customer-push]
verify_jwt = false
```

Do not change JWT behavior of existing functions.

- [ ] **Step 8: Run route tests and verify GREEN**

```bash
deno test supabase/functions/customer-push/index_test.ts
```

Expected: PASS.

- [ ] **Step 9: Commit Task 3**

```bash
git add supabase/functions/customer-push supabase/config.toml
git commit -m "feat(user): add customer push onboarding PWA"
```

---

### Task 4: Delivery worker, VAPID delivery, retry, and scheduled invocation

**Files:**
- Create: `supabase/functions/customer-push-worker/index.ts`
- Modify: `supabase/functions/_shared/customer_push/payload.ts`
- Modify: `supabase/functions/_shared/customer_push/payload_test.ts`
- Modify: `supabase/config.toml`
- Modify: `supabase/migrations/20260917013000_customer_qr_web_push.sql` only if implementation occurs before the migration is applied; if already applied, create `supabase/migrations/20260917023000_customer_push_worker_schedule.sql` instead.

**Interfaces:**
- Consumes: `claim_customer_push_outbox`, subscriptions/outbox/delivery tables, `formatPushBody`, `retryDelaySeconds`.
- Produces: `customer-push-worker` POST endpoint protected by `x-zhirox-push-worker`, plus once-per-minute schedule.

- [ ] **Step 1: Add failing pure tests for response classification**

```ts
Deno.test("410 retires a subscription", () => {
  assertEquals(classifyPushFailure(410), "expired");
});

Deno.test("429 and 5xx are retryable", () => {
  assertEquals(classifyPushFailure(429), "retry");
  assertEquals(classifyPushFailure(503), "retry");
});

Deno.test("terminal retry schedule ends after five attempts", () => {
  assertEquals(retryDelaySeconds(5), 7200);
  assertEquals(retryDelaySeconds(6), null);
});
```

- [ ] **Step 2: Run tests and verify RED**

```bash
deno test supabase/functions/_shared/customer_push/payload_test.ts
```

Expected: FAIL on missing `classifyPushFailure` behavior.

- [ ] **Step 3: Implement failure classification and re-run GREEN**

Use exactly:

```ts
export type PushFailureClass = "expired" | "retry" | "failed";

export function classifyPushFailure(status: number): PushFailureClass {
  if (status === 404 || status === 410) return "expired";
  if (status === 408 || status === 425 || status === 429 || status >= 500) return "retry";
  return "failed";
}
```

Run the test and require PASS.

- [ ] **Step 4: Implement the worker authentication and VAPID setup**

Use:

```ts
import webpush from "npm:web-push@3.6.7";

webpush.setVapidDetails(
  Deno.env.get("VAPID_SUBJECT")!,
  Deno.env.get("VAPID_PUBLIC_KEY")!,
  Deno.env.get("VAPID_PRIVATE_KEY")!,
);
```

Reject every request whose `x-zhirox-push-worker` header does not exactly equal `CUSTOMER_PUSH_WORKER_SECRET`. Return generic `401` without exposing expected values.

- [ ] **Step 5: Implement one idempotent worker pass**

For each claimed outbox event:

1. Insert delivery rows from all currently active subscriptions using `upsert(..., {onConflict:'outbox_id,subscription_id', ignoreDuplicates:true})`.
2. If there are zero active subscriptions, set outbox `completed`, `completed_at=now()`, and do not replay it when a device links later.
3. Load delivery rows with `status='pending'` and `next_attempt_at <= now()`.
4. For each row, call `webpush.sendNotification({endpoint, keys:{p256dh,auth}}, JSON.stringify({title,body,url:'/functions/v1/customer-push'}), {TTL:300, urgency:'high'})`.
5. On success: set delivery `sent`, increment attempt count, set `sent_at`, reset subscription failure count, set `last_success_at`.
6. On 404/410: set delivery `expired`, deactivate subscription, set `last_failure_at`.
7. On retryable response: increment attempt count; if the next retry delay exists, leave status `pending` and set delivery/outbox `next_attempt_at`; otherwise set delivery `failed`.
8. On non-retryable 4xx: set delivery `failed` immediately.
9. When no delivery remains retryable, set outbox `completed`; reserve outbox `failed` for repeated worker/infrastructure processing failures, not terminal per-device outcomes.

Never return endpoint/key data in the HTTP response. Return only `{processed:number}`.

- [ ] **Step 6: Add worker integration tests with a fake sender**

Export `processOutboxEvent(event, deps)` and test fan-out, zero-subscription completion, 410 deactivation, transient retry time, duplicate delivery upsert, and five-attempt terminal failure. Use an injected `sendPush` function so tests do not access the network.

Run:

```bash
deno test supabase/functions/customer-push-worker
```

Expected: PASS.

- [ ] **Step 7: Configure worker no-JWT plus custom secret guard**

Append:

```toml
[functions.customer-push-worker]
verify_jwt = false
```

No other public action is accepted by this function; the custom worker secret remains mandatory.

- [ ] **Step 8: Configure one-minute invocation without committing secrets**

Generate deployment secrets during execution:

```bash
WORKER_SECRET="$(openssl rand -hex 32)"
RATE_LIMIT_SALT="$(openssl rand -hex 32)"
```

Generate a VAPID key pair with a one-off Node command using `web-push.generateVAPIDKeys()`. Store only these values in Supabase Edge Function secrets:

```text
CUSTOMER_PUSH_WORKER_SECRET
CUSTOMER_PUSH_RATE_LIMIT_SALT
VAPID_SUBJECT=mailto:notifications@zhirox.com
VAPID_PUBLIC_KEY
VAPID_PRIVATE_KEY
```

Store the same `CUSTOMER_PUSH_WORKER_SECRET` in Supabase Vault under `customer_push_worker_secret`. Create a `pg_cron` job named `customer-push-worker-every-minute` with `* * * * *` that calls the deployed function URL using `pg_net`, setting header `x-zhirox-push-worker` from the Vault decrypted secret. The secret value must never appear in a migration file, Git commit, Flutter build, or CI log.

- [ ] **Step 9: Commit Task 4**

```bash
git add supabase/functions/customer-push-worker \
        supabase/functions/_shared/customer_push \
        supabase/config.toml \
        supabase/migrations
git commit -m "feat(user): add reliable web push delivery worker"
```

---

### Task 5: Enqueue exactly one payment notification per successful payment action

**Files:**
- Modify: `supabase/functions/record-payment/index.ts`
- Create: `supabase/functions/record-payment/index_test.ts`

**Interfaces:**
- Consumes: existing `record_payment_service`, `record_customer_payment_service`, Task 1 `enqueue_customer_push_event_service`.
- Produces: one `payment_created` outbox event per API payment action.

**Important mapping:** a customer-wide payment may create multiple allocation rows in `payments`. It still represents one user payment action and therefore produces one Web Push event. Use the first returned persisted payment row ID as the canonical `event_record_id` and idempotency key anchor, while the payload amount is the total payment action amount.

- [ ] **Step 1: Write failing tests around extracted enqueue selection logic**

Export a pure helper:

```ts
export function canonicalPaymentId(data: unknown): string | null;
```

Tests:

```ts
Deno.test("debt-specific payment uses returned row id", () => {
  assertEquals(canonicalPaymentId({id:"11111111-1111-1111-1111-111111111111"}),
    "11111111-1111-1111-1111-111111111111");
});

Deno.test("customer-wide payment uses first allocation id", () => {
  assertEquals(canonicalPaymentId({payments:[
    {id:"22222222-2222-2222-2222-222222222222"},
    {id:"33333333-3333-3333-3333-333333333333"},
  ]}), "22222222-2222-2222-2222-222222222222");
});
```

- [ ] **Step 2: Run test and verify RED**

```bash
deno test supabase/functions/record-payment/index_test.ts
```

Expected: FAIL because helper does not exist.

- [ ] **Step 3: Implement canonical payment selection and backend enqueue**

After either payment RPC succeeds:

1. Determine customer ID: direct `customer_id` input for customer-wide flow; for debt-specific flow query the debt by `debt_id` and read `customer_id`.
2. Resolve tenant `market_id` from the customer profile's `admin_id`.
3. Determine canonical payment ID with `canonicalPaymentId`.
4. Compute the customer's total remaining balance after the payment from active non-deleted debts.
5. Read market display name from the tenant admin profile.
6. Call `enqueue_customer_push_event_service` with:

```ts
{
  p_market_id: marketId,
  p_customer_id: resolvedCustomerId,
  p_event_type: "payment_created",
  p_event_record_id: canonicalId,
  p_idempotency_key: `payment_created:${canonicalId}`,
  p_payload: {
    amount,
    currency: "IQD",
    remaining: totalRemaining,
    market_name: marketName,
    occurred_at: new Date().toISOString(),
  }
}
```

If enqueue fails, log only a sanitized message and still return the successful payment response with HTTP 200. Do not include push failure in the client response.

- [ ] **Step 4: Test non-blocking enqueue failure**

Inject a fake enqueue dependency that throws after the fake payment RPC succeeds. Assert the handler still returns the payment data and status 200.

- [ ] **Step 5: Run tests and verify GREEN**

```bash
deno test supabase/functions/record-payment/index_test.ts
```

Expected: PASS.

- [ ] **Step 6: Commit Task 5**

```bash
git add supabase/functions/record-payment
git commit -m "feat(user): enqueue payment push events"
```

---

### Task 6: Live debt enqueue plus reconciliation without import/sync notifications

**Files:**
- Create: `supabase/functions/customer-push-events/index.ts`
- Create: `supabase/functions/customer-push-events/index_test.ts`
- Modify: `lib/services/pb_service.dart`
- Modify: `supabase/functions/customer-push-worker/index.ts`

**Interfaces:**
- Consumes: existing debt insert path in `PBService.createDebt`, Task 1 outbox RPC, existing import/sync provenance tables.
- Produces: authenticated `POST customer-push-events {action:'enqueue_debt', debt_id}` and worker reconciliation for missed live debt enqueue calls.

- [ ] **Step 1: Write failing Deno tests for debt eligibility**

Export:

```ts
export function isLiveDebtEligible(input: {
  deleted: boolean;
  legacyLinked: boolean;
  syncLinked: boolean;
  createdAt: string;
  now: Date;
}): boolean;
```

Tests must assert:
- active live debt = true;
- deleted debt = false;
- legacy-linked debt = false;
- sync-linked debt = false;
- debt older than 24 hours is false for reconciliation;
- debt younger than 2 minutes is false for reconciliation, preventing races with import/link creation.

- [ ] **Step 2: Run test and verify RED**

```bash
deno test supabase/functions/customer-push-events/index_test.ts
```

Expected: FAIL because the module does not exist.

- [ ] **Step 3: Implement authenticated live debt enqueue endpoint**

The endpoint must:
1. authenticate the bearer token;
2. accept only `{action:'enqueue_debt', debt_id:'uuid'}`;
3. read debt plus customer profile and tenant admin;
4. verify actor is the tenant admin or an active/approved same-tenant employee allowed to add debts;
5. reject soft-deleted debt;
6. check `legacy_import_links(entity_kind='debt', target_id=debt_id)` and `daftar_sync_seen(entity_kind='debt', target_id=debt_id)`; if either exists, return `{enqueued:false, reason:'non_live_source'}`;
7. compute customer total remaining;
8. enqueue `debt_created:<debt_id>` with immutable amount/currency/remaining/market/time payload;
9. return `{enqueued:true}`.

- [ ] **Step 4: Add the non-blocking client call after a successful debt insert**

In `PBService.createDebt`, immediately after `created = await pb.collection('debts').create(...)` and before returning, add a fire-and-wait-but-swallow enqueue call:

```dart
try {
  await client.functions.invoke(
    'customer-push-events',
    body: {'action': 'enqueue_debt', 'debt_id': created.id},
  );
} catch (error) {
  debugPrint('Customer push debt enqueue deferred: $error');
}
```

Keep the existing `createNotification(...)` logic and `NotificationService.showDebtCreated(...)` behavior unchanged. Do not turn the push enqueue error into a thrown save error.

- [ ] **Step 5: Implement worker reconciliation**

At the beginning of each worker pass, query at most 100 debts with:
- `created_at >= now() - 24 hours`
- `created_at <= now() - 2 minutes`
- not soft-deleted
- no `debt_created:<id>` row in `notification_outbox`
- no matching debt target in `legacy_import_links`
- no matching debt target in `daftar_sync_seen`

For each eligible row, compute the same payload and call the same idempotent enqueue RPC. A second reconciliation pass must create zero additional outbox rows.

- [ ] **Step 6: Test interruption recovery and exclusion**

Use fake repositories to prove:
- missing live debt becomes exactly one event;
- second pass is idempotent;
- imported debt is skipped;
- sync debt is skipped;
- deleted debt is skipped.

Run:

```bash
deno test supabase/functions/customer-push-events/index_test.ts \
          supabase/functions/customer-push-worker
```

Expected: PASS.

- [ ] **Step 7: Commit Task 6**

```bash
git add supabase/functions/customer-push-events \
        supabase/functions/customer-push-worker \
        lib/services/pb_service.dart
git commit -m "feat(user): enqueue debt push events safely"
```

---

### Task 7: Flutter push gateway, QR card, and profile integration

**Files:**
- Create: `lib/services/customer_push_service.dart`
- Create: `lib/widgets/customer_push_card.dart`
- Create: `test/customer_push_service_test.dart`
- Create: `test/customer_push_card_test.dart`
- Modify: `lib/screens/shared/user_profile_screen.dart`
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`

**Interfaces:**
- Consumes: `customer-push-admin` actions from Task 2.
- Produces:

```dart
class CustomerPushStatus {
  final bool active;
  final int deviceCount;
  final String? latestStatus;
  final DateTime? latestAt;
}

class CustomerPushLink {
  final Uri url;
  final DateTime expiresAt;
}

abstract interface class CustomerPushGateway {
  Future<CustomerPushStatus> loadStatus(String customerId);
  Future<CustomerPushLink> createLink(String customerId);
  Future<int> revokeAll(String customerId);
}

class CustomerPushService implements CustomerPushGateway { ... }
```

- [ ] **Step 1: Add `qr_flutter` and write failing model/gateway tests**

Add to `pubspec.yaml`:

```yaml
qr_flutter: ^4.1.0
```

Create tests for strict parsing:

```dart
test('status parses device count and nullable latest delivery', () {
  final status = CustomerPushStatus.fromJson({
    'active': true,
    'device_count': 2,
    'latest_status': 'sent',
    'latest_at': '2026-09-17T00:00:00Z',
  });
  expect(status.active, isTrue);
  expect(status.deviceCount, 2);
  expect(status.latestStatus, 'sent');
});
```

- [ ] **Step 2: Run Flutter test and verify RED**

```bash
flutter test test/customer_push_service_test.dart
```

Expected: FAIL because `customer_push_service.dart` does not exist.

- [ ] **Step 3: Implement typed gateway**

`CustomerPushService` calls `PBService.ensureInitialized()` then `PBService.client.functions.invoke('customer-push-admin', body: ...)`.

Map server errors through a local `_requireMap` helper; malformed responses throw `FormatException` instead of silently displaying false status. No raw subscription endpoint/key data exists in these models.

- [ ] **Step 4: Run service tests and verify GREEN**

```bash
flutter test test/customer_push_service_test.dart
```

Expected: PASS.

- [ ] **Step 5: Write failing widget tests for the customer push card**

Use a fake `CustomerPushGateway` and test:
- inactive state shows `Push: ناچالاک` and `0 device`;
- active state shows device count;
- tapping **QR ـی ئاگادارکردنەوە** calls `createLink` and opens a dialog containing a `QrImageView` for exactly the returned URL;
- tapping **بڕینی هەموو device ـەکان** asks confirmation before `revokeAll`;
- successful revoke refreshes status;
- service error shows a retry action without affecting the rest of the profile.

- [ ] **Step 6: Run widget test and verify RED**

```bash
flutter test test/customer_push_card_test.dart
```

Expected: FAIL because the widget does not exist.

- [ ] **Step 7: Implement `CustomerPushCard` as a self-contained widget**

Constructor:

```dart
class CustomerPushCard extends StatefulWidget {
  final String customerId;
  final CustomerPushGateway gateway;

  const CustomerPushCard({
    super.key,
    required this.customerId,
    CustomerPushGateway? gateway,
  }) : gateway = gateway ?? const CustomerPushService();
}
```

The widget owns only push-status loading, QR dialog state, revoke confirmation, and refresh. It does not own customer financial state.

QR dialog renders:

```dart
QrImageView(
  data: link.url.toString(),
  version: QrVersions.auto,
  size: 240,
)
```

Show the expiry time and Sorani instruction that the QR works once and for 15 minutes.

- [ ] **Step 8: Integrate the card into `UserProfileScreen` without enlarging the large screen's responsibilities**

Import `customer_push_card.dart`. In the customer profile overview section, mount:

```dart
if (_isCustomer && auth.canSendNotifications) ...[
  const SizedBox(height: 12),
  CustomerPushCard(customerId: widget.userId),
]
```

Do not add push networking methods to `UserProfileScreen`. Do not show the management card to customer-role sessions or employees without notification permission.

- [ ] **Step 9: Run focused and full Flutter tests**

```bash
flutter test test/customer_push_service_test.dart test/customer_push_card_test.dart
flutter test
flutter analyze
```

Expected: all PASS, analyze exits 0.

- [ ] **Step 10: Commit Task 7**

```bash
git add pubspec.yaml pubspec.lock \
        lib/services/customer_push_service.dart \
        lib/widgets/customer_push_card.dart \
        lib/screens/shared/user_profile_screen.dart \
        test/customer_push_service_test.dart \
        test/customer_push_card_test.dart
git commit -m "feat(user): add customer push QR controls"
```

---

### Task 8: Static policy verification, CI wiring, deployment verification, and release evidence

**Files:**
- Create: `scripts/verify_customer_push.py`
- Modify: `.github/workflows/ios-unsigned-ipa.yml`
- Verify: all files from Tasks 1-7.

**Interfaces:**
- Consumes: complete feature.
- Produces: CI gates and release evidence; no new product behavior.

- [ ] **Step 1: Write the failing policy verifier**

Create a Python verifier that exits non-zero unless all of these are true:

```python
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

required = [
    ROOT / "supabase/functions/customer-push/index.ts",
    ROOT / "supabase/functions/customer-push-admin/index.ts",
    ROOT / "supabase/functions/customer-push-worker/index.ts",
    ROOT / "supabase/functions/customer-push-events/index.ts",
    ROOT / "lib/services/customer_push_service.dart",
    ROOT / "lib/widgets/customer_push_card.dart",
]
for path in required:
    assert path.exists(), f"missing {path.relative_to(ROOT)}"

config = (ROOT / "supabase/config.toml").read_text()
assert "[functions.customer-push]\nverify_jwt = false" in config
assert "[functions.customer-push-worker]\nverify_jwt = false" in config

flutter_text = "\n".join(
    p.read_text(errors="ignore") for p in (ROOT / "lib").rglob("*.dart")
)
for forbidden in ["VAPID_PRIVATE_KEY", "CUSTOMER_PUSH_WORKER_SECRET", "CUSTOMER_PUSH_RATE_LIMIT_SALT"]:
    assert forbidden not in flutter_text, f"server secret name leaked into Flutter: {forbidden}"

migration_text = "\n".join(p.read_text() for p in (ROOT / "supabase/migrations").glob("*.sql"))
assert "debt_created" in migration_text
assert "payment_created" in migration_text
assert "debt_updated" not in migration_text
```

Also assert the event Edge Function checks both import/sync provenance sources and that `record-payment` catches push enqueue failure rather than converting it into payment failure.

- [ ] **Step 2: Run verifier before CI wiring**

```bash
python3 scripts/verify_customer_push.py
```

Expected: PASS once Tasks 1-7 are complete; if any invariant is absent, fix that task before modifying CI.

- [ ] **Step 3: Add Deno and policy gates to the existing iOS workflow**

Insert after existing Python verification steps and before CocoaPods/build:

```yaml
      - name: Verify customer QR web push policy
        run: python3 scripts/verify_customer_push.py

      - name: Setup Deno
        uses: denoland/setup-deno@v2
        with:
          deno-version: v2.x

      - name: Test customer push Edge Functions
        run: |
          deno test supabase/functions/_shared/customer_push \
                    supabase/functions/customer-push-admin \
                    supabase/functions/customer-push \
                    supabase/functions/customer-push-worker \
                    supabase/functions/customer-push-events \
                    supabase/functions/record-payment
```

Do not remove or weaken any existing verification step.

- [ ] **Step 4: Run complete local/static verification**

```bash
python3 scripts/verify_online_only.py
python3 scripts/verify_fib_payment_security.py
python3 scripts/verify_auto_update.py
python3 scripts/verify_customer_payment_totals.py
python3 scripts/verify_customer_push.py
deno test supabase/functions/_shared/customer_push \
          supabase/functions/customer-push-admin \
          supabase/functions/customer-push \
          supabase/functions/customer-push-worker \
          supabase/functions/customer-push-events \
          supabase/functions/record-payment
flutter analyze
flutter test
```

Expected: every command exits 0.

- [ ] **Step 5: Apply backend and secrets in safe order**

Deployment order:
1. Apply Task 1 migration(s).
2. Deploy `customer-push-admin`, `customer-push`, `customer-push-worker`, `customer-push-events`, and updated `record-payment`.
3. Generate/store VAPID keys, worker secret, and rate-limit salt in Supabase secrets.
4. Store the same worker secret in Supabase Vault.
5. Create the once-per-minute `pg_cron` invocation.
6. Invoke `customer-push-worker` once with the correct secret and verify `{processed:0}` or a non-negative count.
7. Query `cron.job` and verify exactly one active `customer-push-worker-every-minute` job.

- [ ] **Step 6: Execute live smoke tests with a test customer**

Use a non-production test customer in one market:
1. Generate QR and verify expiry is 15 minutes.
2. Validate the same token through public onboarding.
3. Link first browser/device and confirm token becomes unusable afterward.
4. Generate a second QR and link a second device.
5. Create one debt: exactly one `debt_created` outbox row and one delivery row per active device.
6. Record one customer-wide payment spanning multiple debts: exactly one `payment_created` outbox row, not one per allocation.
7. Confirm both devices receive both notifications.
8. Revoke all and confirm subsequent eligible event completes with zero delivery rows.
9. Force an invalid subscription endpoint in the test tenant and verify it becomes inactive/`expired` without changing the financial transaction result.

- [ ] **Step 7: Trigger GitHub Actions and collect fresh release evidence**

Push the final commit to `user-source`, wait for the `iOS Unsigned IPA` workflow, and require:
- customer push policy PASS;
- Deno tests PASS;
- Flutter analyze PASS;
- Flutter tests PASS;
- iOS build/package/release PASS.

Record the workflow run ID, final commit SHA, permanent `user-latest` IPA URL, and SHA-256 checksum in the completion report.

- [ ] **Step 8: Commit Task 8**

```bash
git add scripts/verify_customer_push.py .github/workflows/ios-unsigned-ipa.yml
git commit -m "ci(user): verify customer QR web push"
```

---

## Plan Self-Review Results

- Spec coverage: QR creation, 15-minute single-use token, multi-device subscriptions, iOS Home Screen onboarding, server-only secrets, tenant security, rate limiting, debt/payment-only event scope, immutable outbox, idempotency, delivery audit, bounded retry, invalid subscription retirement, revoke-all, push status UI, import/sync exclusion, push failure isolation, and CI/iOS verification are each assigned to a concrete task.
- Type consistency: Flutter gateway types and Edge Function action names are defined once and reused consistently; event types are exactly `debt_created` and `payment_created`; worker terminal states match the design spec.
- Existing behavior protection: current in-app/local and Telegram notification paths are explicitly preserved; financial success remains authoritative.
- Customer-wide payment ambiguity is resolved explicitly: one payment action produces one push event using the first persisted allocation payment row as the canonical event record, while the message amount is the total payment action amount.
- No implementation step depends on a secret committed to Git; all sensitive values are generated and stored only at deployment time.
