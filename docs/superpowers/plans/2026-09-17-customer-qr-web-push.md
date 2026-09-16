# Customer QR Web Push Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add secure customer-specific QR linking and Web Push notifications for newly created debts and newly recorded payments without Viber, SMS, email, KYC, or a third-party messaging provider.

**Architecture:** Supabase stays authoritative. Staff create 15-minute one-time QR links through an authenticated Edge Function; customers open a token-gated PWA that registers a Push API subscription; successful live debt/payment paths enqueue immutable outbox events; a scheduled Deno Edge Function delivers them with VAPID, retry, idempotency, and audit logging. Flutter only manages QR/status/revoke UI and never receives backend secrets.

**Tech Stack:** Flutter/Dart 3.10+, `supabase_flutter`, PostgreSQL/PLpgSQL/RLS, Supabase Edge Functions (Deno), `npm:web-push@3.6.7`, `qr_flutter`, Push API, Service Worker API, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-17-customer-qr-web-push-design.md`

## Global Constraints

- Work only on `user-source`.
- QR lifetime is exactly 15 minutes; raw token is 32 random bytes encoded as 64 lowercase hex characters.
- Store only SHA-256 token hashes in PostgreSQL.
- Only `debt_created` and `payment_created` generate Web Push.
- Debt/payment edit/delete, due reminders, imports, restore flows, legacy sync, broadcasts, and marketing never generate Web Push.
- Existing in-app/local notifications and existing Telegram behavior stay unchanged.
- Push enqueue or delivery failure never turns a successful financial transaction into a failure.
- One customer may link multiple devices; one active push endpoint belongs to only one customer at a time.
- `market_id` in push tables is the existing tenant admin profile UUID.
- Active approved admins may manage customer push; employees need `can_send_notifications = true`.
- VAPID private key, worker secret, rate-limit salt, subscription key material, and device unlink secret hashes remain server-side.
- iPhone/iPad onboarding must support Add to Home Screen before permission is requested.
- Retry sequence per device: initial send immediately; after failed attempts 1,2,3,4 wait 60s, 300s, 1800s, 7200s; after failed attempt 5 mark terminal failure.
- Notification click opens the generic ZHIROX Notifications PWA route and never exposes `customer_id`.
- CI must preserve all existing policy checks, Flutter analyze/tests, and the unsigned iOS IPA release pipeline.

---

## File Structure

### Create
- `supabase/migrations/20260917013000_customer_qr_web_push.sql`
- `supabase/tests/customer_qr_web_push_regression.sql`
- `supabase/functions/_shared/customer_push/crypto.ts`
- `supabase/functions/_shared/customer_push/payload.ts`
- `supabase/functions/_shared/customer_push/payload_test.ts`
- `supabase/functions/customer-push-admin/index.ts`
- `supabase/functions/customer-push-admin/index_test.ts`
- `supabase/functions/customer-push/index.ts`
- `supabase/functions/customer-push/index_test.ts`
- `supabase/functions/customer-push-worker/index.ts`
- `supabase/functions/customer-push-worker/index_test.ts`
- `supabase/functions/customer-push-events/index.ts`
- `supabase/functions/customer-push-events/index_test.ts`
- `supabase/functions/record-payment/index_test.ts`
- `lib/services/customer_push_service.dart`
- `lib/widgets/customer_push_card.dart`
- `test/customer_push_service_test.dart`
- `test/customer_push_card_test.dart`
- `scripts/verify_customer_push.py`

### Modify
- `supabase/functions/record-payment/index.ts`
- `supabase/config.toml`
- `lib/services/pb_service.dart`
- `lib/screens/shared/user_profile_screen.dart`
- `pubspec.yaml`
- `pubspec.lock`
- `.github/workflows/ios-unsigned-ipa.yml`

---

### Task 1: Database model, RPC boundary, and regression tests

**Files:**
- Create: `supabase/migrations/20260917013000_customer_qr_web_push.sql`
- Create: `supabase/tests/customer_qr_web_push_regression.sql`

**Interfaces produced:**

```text
public.manage_customer_push_link(uuid, uuid, text, timestamptz) -> jsonb
public.customer_push_status_service(uuid, uuid) -> jsonb
public.revoke_customer_push_subscriptions_service(uuid, uuid) -> integer
public.inspect_customer_push_link_service(text) -> jsonb
public.redeem_customer_push_subscription_service(text,text,text,text,text,text,text) -> jsonb
public.unsubscribe_customer_push_subscription_service(text,text) -> boolean
public.consume_customer_push_rate_limit(text,integer,integer) -> boolean
public.enqueue_customer_push_event_service(uuid,uuid,text,uuid,text,jsonb) -> uuid
public.claim_customer_push_outbox(integer) -> setof notification_outbox
```

- [ ] **Step 1: Write the failing database regression test**

Use the existing repository style: a transaction plus a `do` block that raises on invariant failure.

```sql
begin;

do $test$
declare
  v_admin_a uuid := '00000000-0000-0000-0000-000000000101';
  v_admin_b uuid := '00000000-0000-0000-0000-000000000201';
  v_employee_ok uuid := '00000000-0000-0000-0000-000000000111';
  v_employee_no uuid := '00000000-0000-0000-0000-000000000112';
  v_customer_a uuid := '00000000-0000-0000-0000-000000000121';
  v_customer_b uuid := '00000000-0000-0000-0000-000000000221';
  v_outbox_a uuid;
  v_outbox_b uuid;
  v_sub uuid;
begin
  if to_regclass('public.customer_push_link_tokens') is null
     or to_regclass('public.customer_push_subscriptions') is null
     or to_regclass('public.notification_outbox') is null
     or to_regclass('public.notification_deliveries') is null
     or to_regclass('public.customer_push_rate_limits') is null then
    raise exception 'customer push schema missing';
  end if;

  insert into public.profiles(id,name,phone,role,market_name,admin_id,created_by,approved,active,can_send_notifications)
  values
    (v_admin_a,'Admin A','push-admin-a','admin','Market A',null,v_admin_a,true,true,true),
    (v_admin_b,'Admin B','push-admin-b','admin','Market B',null,v_admin_b,true,true,true),
    (v_employee_ok,'Employee OK','push-emp-ok','employee','',v_admin_a,v_admin_a,true,true,true),
    (v_employee_no,'Employee NO','push-emp-no','employee','',v_admin_a,v_admin_a,true,true,false),
    (v_customer_a,'Customer A','push-cust-a','customer','',v_admin_a,v_admin_a,true,true,false),
    (v_customer_b,'Customer B','push-cust-b','customer','',v_admin_b,v_admin_b,true,true,false);

  perform public.manage_customer_push_link(v_admin_a, v_customer_a, repeat('a',64), now()+interval '15 minutes');
  perform public.manage_customer_push_link(v_employee_ok, v_customer_a, repeat('b',64), now()+interval '15 minutes');

  begin
    perform public.manage_customer_push_link(v_employee_no, v_customer_a, repeat('c',64), now()+interval '15 minutes');
    raise exception 'employee without notification permission was allowed';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.manage_customer_push_link(v_admin_a, v_customer_b, repeat('d',64), now()+interval '15 minutes');
    raise exception 'cross-tenant push link was allowed';
  exception when insufficient_privilege then null;
  end;

  perform public.manage_customer_push_link(v_admin_a, v_customer_a, repeat('e',64), now()+interval '15 minutes');
  perform public.redeem_customer_push_subscription_service(
    repeat('e',64),'https://push.example/device-a','p256-a','auth-a',repeat('1',64),'ua','ios'
  );

  begin
    perform public.redeem_customer_push_subscription_service(
      repeat('e',64),'https://push.example/device-b','p256-b','auth-b',repeat('2',64),'ua','ios'
    );
    raise exception 'used token was accepted twice';
  exception when no_data_found then null;
  end;

  perform public.manage_customer_push_link(v_admin_a, v_customer_a, repeat('f',64), now()-interval '1 minute');
  begin
    perform public.redeem_customer_push_subscription_service(
      repeat('f',64),'https://push.example/device-c','p256-c','auth-c',repeat('3',64),'ua','android'
    );
    raise exception 'expired token was accepted';
  exception when no_data_found then null;
  end;

  select id into v_sub
  from public.customer_push_subscriptions
  where endpoint='https://push.example/device-a' and active=true;

  v_outbox_a := public.enqueue_customer_push_event_service(
    v_admin_a,v_customer_a,'debt_created','00000000-0000-0000-0000-000000000301',
    'debt_created:00000000-0000-0000-0000-000000000301',
    '{"amount":1000,"currency":"IQD","remaining_iqd":1000,"market_name":"Market A","occurred_at":"2026-09-17T00:00:00Z"}'::jsonb
  );
  v_outbox_b := public.enqueue_customer_push_event_service(
    v_admin_a,v_customer_a,'debt_created','00000000-0000-0000-0000-000000000301',
    'debt_created:00000000-0000-0000-0000-000000000301',
    '{"amount":9999,"currency":"IQD","remaining_iqd":9999,"market_name":"changed","occurred_at":"2026-09-17T00:00:00Z"}'::jsonb
  );

  if v_outbox_a <> v_outbox_b then
    raise exception 'idempotent enqueue returned different event ids';
  end if;
  if (select payload->>'amount' from public.notification_outbox where id=v_outbox_a) <> '1000' then
    raise exception 'duplicate enqueue mutated immutable payload';
  end if;

  begin
    perform public.enqueue_customer_push_event_service(
      v_admin_a,v_customer_a,'debt_updated','00000000-0000-0000-0000-000000000302',
      'debt_updated:00000000-0000-0000-0000-000000000302','{}'::jsonb
    );
    raise exception 'unsupported event type accepted';
  exception when check_violation then null;
  end;

  insert into public.notification_deliveries(outbox_id,subscription_id) values(v_outbox_a,v_sub);
  begin
    insert into public.notification_deliveries(outbox_id,subscription_id) values(v_outbox_a,v_sub);
    raise exception 'duplicate delivery pair accepted';
  exception when unique_violation then null;
  end;

  if has_table_privilege('authenticated','public.customer_push_subscriptions','SELECT')
     or has_table_privilege('authenticated','public.customer_push_subscriptions','INSERT')
     or has_table_privilege('anon','public.customer_push_subscriptions','SELECT') then
    raise exception 'client retained direct subscription table privilege';
  end if;
end
$test$;

rollback;
select 'customer QR web push regression passed' as result;
```

- [ ] **Step 2: Run the regression test and verify RED**

```bash
supabase start
supabase db reset
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -v ON_ERROR_STOP=1 \
  -f supabase/tests/customer_qr_web_push_regression.sql
```

Expected: non-zero exit because the new push tables/RPCs do not exist.

- [ ] **Step 3: Implement the migration**

Create these tables with RLS enabled and no direct `anon`/`authenticated` privileges:

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
  on public.customer_push_subscriptions(endpoint) where active=true;

create table public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  event_type text not null check (event_type in ('debt_created','payment_created')),
  event_record_id uuid not null,
  idempotency_key text not null unique,
  payload jsonb not null,
  status text not null default 'pending' check (status in ('pending','processing','completed','failed')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  next_attempt_at timestamptz not null default now(),
  fanout_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create table public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  outbox_id uuid not null references public.notification_outbox(id) on delete cascade,
  subscription_id uuid not null references public.customer_push_subscriptions(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','sent','failed','expired')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  provider_status integer,
  last_error text,
  next_attempt_at timestamptz,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(outbox_id,subscription_id)
);

create table public.customer_push_rate_limits (
  key_hash text primary key check (key_hash ~ '^[a-f0-9]{64}$'),
  window_started_at timestamptz not null default now(),
  request_count integer not null default 0 check (request_count >= 0),
  expires_at timestamptz not null
);
```

Every service RPC must be `security definer set search_path=''`, revoked from `public, anon, authenticated`, and granted to `service_role` only.

Use this actor rule in staff management RPCs:

```sql
select case
  when actor.role='admin' and actor.id=customer.admin_id then customer.admin_id
  when actor.role='employee'
       and actor.admin_id=customer.admin_id
       and actor.can_send_notifications=true then customer.admin_id
end
into v_market_id
from public.profiles actor
join public.profiles customer on customer.id=p_customer
where actor.id=p_actor
  and actor.active=true and actor.approved=true
  and customer.role='customer' and customer.active=true and customer.approved=true;

if v_market_id is null then
  raise exception 'push_forbidden' using errcode='42501';
end if;
```

`manage_customer_push_link` revokes every previous unused token for the same customer/market before inserting the new hash.

`inspect_customer_push_link_service` returns only `customer_name`, `market_name`, and `expires_at` for an unused/unrevoked/unexpired token; otherwise raise `no_data_found`.

`redeem_customer_push_subscription_service` locks the token row `for update`, validates it again, rejects an endpoint actively owned by another customer, updates the same-customer endpoint or inserts a new row, and only then sets `used_at=now()`.

`revoke_customer_push_subscriptions_service` sets all active subscriptions false **and** revokes unused QR tokens for that customer.

Implement immutable idempotent enqueue without a no-op update:

```sql
with inserted as (
  insert into public.notification_outbox(
    market_id,customer_id,event_type,event_record_id,idempotency_key,payload
  ) values (
    p_market_id,p_customer_id,p_event_type,p_event_record_id,p_idempotency_key,p_payload
  )
  on conflict (idempotency_key) do nothing
  returning id
)
select id into v_id from inserted
union all
select id from public.notification_outbox where idempotency_key=p_idempotency_key
limit 1;
return v_id;
```

`claim_customer_push_outbox` must use `for update skip locked`; when claimed, set `status='processing'` and `next_attempt_at=now()+interval '2 minutes'` as a crash-recovery lease. A crashed worker can therefore be reclaimed after two minutes without duplicate fan-out because `fanout_at` and delivery uniqueness freeze the device set.

- [ ] **Step 4: Run database regression and verify GREEN**

```bash
supabase db reset
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -v ON_ERROR_STOP=1 \
  -f supabase/tests/customer_qr_web_push_regression.sql
```

Expected: prints `customer QR web push regression passed` and exits 0.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260917013000_customer_qr_web_push.sql \
        supabase/tests/customer_qr_web_push_regression.sql
git commit -m "feat(user): add customer push data model"
```

---

### Task 2: Shared crypto/payload helpers and staff QR API

**Files:**
- Create: `supabase/functions/_shared/customer_push/crypto.ts`
- Create: `supabase/functions/_shared/customer_push/payload.ts`
- Create: `supabase/functions/_shared/customer_push/payload_test.ts`
- Create: `supabase/functions/customer-push-admin/index.ts`
- Create: `supabase/functions/customer-push-admin/index_test.ts`

**Interfaces produced:**

```ts
randomHexToken(byteLength?: number): string
sha256Hex(value: string): Promise<string>
retryDelayAfterFailure(attemptCount: number): number | null
classifyPushFailure(status: number): "expired" | "retry" | "failed"
formatPushBody(eventType: "debt_created"|"payment_created", payload: PushPayload): {title:string; body:string}
```

- [ ] **Step 1: Write failing pure tests**

```ts
import { assertEquals, assertMatch } from "jsr:@std/assert@1";
import { randomHexToken, sha256Hex } from "./crypto.ts";
import { formatPushBody, retryDelayAfterFailure } from "./payload.ts";

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
    [1,2,3,4,5].map(retryDelayAfterFailure),
    [60,300,1800,7200,null],
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
      body: "بڕی دراو: 25,000 د.ع • ماوە: 100,000 د.ع • مارکێت: ZHIROX Market",
    },
  );
});
```

- [ ] **Step 2: Run RED**

```bash
deno test supabase/functions/_shared/customer_push/payload_test.ts
```

Expected: module-not-found failure.

- [ ] **Step 3: Implement the helpers**

`crypto.ts`:

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

`payload.ts` uses the fixed retry table above, formats IQD with zero decimals and USD with two decimals, always formats `remaining_iqd` as IQD, and exposes no IDs or notes in title/body.

- [ ] **Step 4: Run GREEN**

```bash
deno test supabase/functions/_shared/customer_push/payload_test.ts
```

Expected: PASS.

- [ ] **Step 5: Write failing staff API tests**

Export `handleAdminAction(body, actorId, deps)`. Use a fake `manageLink/status/revokeAll` dependency and assert:

```ts
Deno.test("create_link passes only the hash to storage", async () => {
  let storedHash = "";
  const response = await handleAdminAction(
    {action:"create_link", customer_id:"00000000-0000-0000-0000-000000000121"},
    "00000000-0000-0000-0000-000000000101",
    {
      now: () => new Date("2026-09-17T00:00:00Z"),
      randomToken: () => "a".repeat(64),
      manageLink: async ({tokenHash}) => { storedHash = tokenHash; },
      status: async () => ({active:false,device_count:0,latest_status:null,latest_at:null}),
      revokeAll: async () => 0,
      publicBaseUrl: "https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/customer-push",
    },
  );
  assertEquals(storedHash, await sha256Hex("a".repeat(64)));
  assertEquals(response.expires_at, "2026-09-17T00:15:00.000Z");
  assertEquals(response.url.endsWith("token=" + "a".repeat(64)), true);
});
```

- [ ] **Step 6: Implement `customer-push-admin`**

Authenticate the bearer with service-role `auth.getUser`. Supported bodies are exactly:

```json
{"action":"create_link","customer_id":"uuid"}
{"action":"status","customer_id":"uuid"}
{"action":"revoke_all","customer_id":"uuid"}
```

`create_link` generates a raw token, hashes it, uses `expires_at = now + 15 minutes`, calls `manage_customer_push_link`, and returns only the public onboarding URL plus expiry. `status` returns active/device count/latest delivery state/time. `revoke_all` returns the integer revoked count. Never log raw token, endpoint, `p256dh`, `auth`, or device secret.

- [ ] **Step 7: Run API tests**

```bash
deno test supabase/functions/customer-push-admin/index_test.ts
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/_shared/customer_push \
        supabase/functions/customer-push-admin
git commit -m "feat(user): add customer push admin API"
```

---

### Task 3: Public onboarding PWA and subscription lifecycle

**Files:**
- Create: `supabase/functions/customer-push/index.ts`
- Create: `supabase/functions/customer-push/index_test.ts`
- Modify: `supabase/config.toml`

**Interfaces consumed:** Task 1 inspect/redeem/unsubscribe/rate-limit RPCs, Task 2 crypto helper.

- [ ] **Step 1: Write failing route tests**

Export `routeCustomerPush(req, deps)` and cover generic landing, token page, invalid subscription body, and unsubscribe auth:

```ts
Deno.test("token page never embeds raw customer id", async () => {
  const res = await routeCustomerPush(
    new Request("https://x/functions/v1/customer-push?token=" + "a".repeat(64)),
    fakeDeps,
  );
  const html = await res.text();
  assertEquals(res.status, 200);
  assertEquals(html.includes("customer_id"), false);
  assertEquals(html.includes("چالاککردنی ئاگادارکردنەوە"), true);
});

Deno.test("subscribe rejects missing PushSubscription keys", async () => {
  const res = await routeCustomerPush(
    new Request("https://x/functions/v1/customer-push", {
      method:"POST",
      headers:{"content-type":"application/json"},
      body:JSON.stringify({action:"subscribe",token:"a".repeat(64),subscription:{}}),
    }),
    fakeDeps,
  );
  assertEquals(res.status, 400);
});
```

- [ ] **Step 2: Run RED**

```bash
deno test supabase/functions/customer-push/index_test.ts
```

Expected: module-not-found failure.

- [ ] **Step 3: Implement public rate limiting and token inspection**

For `validate` and `subscribe`, derive client IP from `cf-connecting-ip`, then first `x-forwarded-for`, then `unknown`; hash `CUSTOMER_PUSH_RATE_LIMIT_SALT + ':' + ip`; call `consume_customer_push_rate_limit(hash,30,60)`. Return 429 on rejection.

All invalid/expired/used/revoked token states return the same response:

```json
{"error":"link_unavailable"}
```

`validate` returns only:

```json
{"customer_name":"...","market_name":"...","expires_at":"ISO","vapid_public_key":"..."}
```

- [ ] **Step 4: Implement subscribe/unsubscribe**

`subscribe` requires:

```json
{
  "action":"subscribe",
  "token":"64-hex",
  "subscription":{
    "endpoint":"https://...",
    "keys":{"p256dh":"...","auth":"..."}
  },
  "platform":"ios|android|desktop"
}
```

Generate a new 32-byte `deviceSecret`, store only `sha256Hex(deviceSecret)` through `redeem_customer_push_subscription_service`, and return:

```json
{"linked":true,"device_secret":"raw-secret-returned-once"}
```

`unsubscribe` requires endpoint plus raw device secret; hash it before calling `unsubscribe_customer_push_subscription_service`.

- [ ] **Step 5: Implement onboarding HTML/manifest/service worker**

Serve everything from the same function origin. Add `Referrer-Policy: no-referrer`, `Cache-Control: no-store`, and a CSP that permits only same-origin connections/workers plus inline script/style used by this page.

The manifest route is `/functions/v1/customer-push/manifest.webmanifest?token=<raw>` and sets:

```json
{
  "name":"ZHIROX Notifications",
  "short_name":"ZHIROX",
  "display":"standalone",
  "start_url":"/functions/v1/customer-push?token=<url-encoded-token>",
  "scope":"/functions/v1/customer-push/",
  "theme_color":"#ffffff",
  "background_color":"#ffffff"
}
```

The page must not call `Notification.requestPermission()` until the user taps **چالاککردنی ئاگادارکردنەوە**. On iOS outside standalone mode, show Add-to-Home-Screen instructions and keep the token in the dynamic `start_url`.

Service worker response must include `Service-Worker-Allowed: /functions/v1/customer-push/` and run:

```js
self.addEventListener('push', event => {
  const data = event.data ? event.data.json() : {};
  event.waitUntil(self.registration.showNotification(data.title || 'ZHIROX', {
    body: data.body || '',
    data: {url: data.url || '/functions/v1/customer-push'}
  }));
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil(clients.openWindow(event.notification.data.url));
});
```

A `GET` without token renders a generic “notifications enabled / scan a fresh QR to relink” landing page and exposes no customer data.

- [ ] **Step 6: Configure public function**

Append only:

```toml
[functions.customer-push]
verify_jwt = false
```

- [ ] **Step 7: Run GREEN**

```bash
deno test supabase/functions/customer-push/index_test.ts
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/customer-push supabase/config.toml
git commit -m "feat(user): add customer push onboarding PWA"
```

---

### Task 4: VAPID worker, frozen fan-out, retry, and cron

**Files:**
- Create: `supabase/functions/customer-push-worker/index.ts`
- Create: `supabase/functions/customer-push-worker/index_test.ts`
- Modify: `supabase/functions/_shared/customer_push/payload.ts`
- Modify: `supabase/functions/_shared/customer_push/payload_test.ts`
- Modify: `supabase/config.toml`

**Interfaces consumed:** outbox/subscription/delivery tables, `claim_customer_push_outbox`, Task 2 payload helpers.

- [ ] **Step 1: Add failing classification tests**

```ts
Deno.test("push status classification", () => {
  assertEquals(classifyPushFailure(410), "expired");
  assertEquals(classifyPushFailure(404), "expired");
  assertEquals(classifyPushFailure(429), "retry");
  assertEquals(classifyPushFailure(503), "retry");
  assertEquals(classifyPushFailure(400), "failed");
});
```

- [ ] **Step 2: Implement and run GREEN**

```ts
export function classifyPushFailure(status: number): "expired"|"retry"|"failed" {
  if (status === 404 || status === 410) return "expired";
  if (status === 408 || status === 425 || status === 429 || status >= 500) return "retry";
  return "failed";
}
```

```bash
deno test supabase/functions/_shared/customer_push/payload_test.ts
```

Expected: PASS.

- [ ] **Step 3: Write failing worker tests with injected sender/repository**

Use `processOutboxEvent(event,deps)` with fake `listActiveSubscriptions`, `insertDeliveryIfMissing`, `listDueDeliveries`, `sendPush`, `updateDelivery`, `updateSubscription`, `updateOutbox`.

```ts
Deno.test("fanout is frozen after first processing", async () => {
  const repo = fakeRepo({fanoutAt:null, activeSubscriptions:[subA, subB]});
  await processOutboxEvent(event, repo.deps);
  repo.event.fanout_at = "2026-09-17T00:00:00Z";
  repo.activeSubscriptions.push(subC);
  await processOutboxEvent(repo.event, repo.deps);
  assertEquals(repo.deliverySubscriptionIds.sort(), [subA.id, subB.id].sort());
});

Deno.test("410 expires subscription without retry", async () => {
  const repo = fakeRepo({sendError:{statusCode:410}});
  await processOutboxEvent(event, repo.deps);
  assertEquals(repo.delivery.status, "expired");
  assertEquals(repo.subscription.active, false);
});
```

- [ ] **Step 4: Implement worker**

Initialize:

```ts
import webpush from "npm:web-push@3.6.7";
webpush.setVapidDetails(
  Deno.env.get("VAPID_SUBJECT")!,
  Deno.env.get("VAPID_PUBLIC_KEY")!,
  Deno.env.get("VAPID_PRIVATE_KEY")!,
);
```

Require exact `x-zhirox-push-worker == CUSTOMER_PUSH_WORKER_SECRET`; otherwise 401.

For each claimed event:
1. If `fanout_at is null`, snapshot currently active subscriptions into `notification_deliveries` with `on conflict do nothing`, then set `fanout_at=now()`. Never add devices on later retries.
2. If zero deliveries exist after first fan-out, set outbox `completed` immediately.
3. Send each due `pending` delivery with `webpush.sendNotification` and JSON `{title,body,url:'/functions/v1/customer-push'}`.
4. Success -> `sent`, increment attempt count, set `sent_at`, reset subscription failure count, set `last_success_at`.
5. 404/410 -> `expired`, deactivate subscription.
6. Retryable -> increment attempt count; if `retryDelayAfterFailure(count)` returns seconds, keep `pending` and set `next_attempt_at`; otherwise `failed`.
7. Non-retryable 4xx -> `failed` immediately.
8. Set outbox `next_attempt_at` to the earliest pending delivery retry. If none remain pending, set `completed`.
9. Only worker/infrastructure exceptions increment outbox `attempt_count`; after five such processing failures set outbox `failed`.

- [ ] **Step 5: Run worker tests**

```bash
deno test supabase/functions/customer-push-worker/index_test.ts
```

Expected: PASS for multi-device fan-out, frozen fan-out, zero-device completion, retry timing, 410 expiry, idempotent second pass, and terminal fifth failure.

- [ ] **Step 6: Configure worker function**

Append:

```toml
[functions.customer-push-worker]
verify_jwt = false
```

The custom worker header remains mandatory inside the function.

- [ ] **Step 7: Generate deployment secrets without committing them**

```bash
WORKER_SECRET="$(openssl rand -hex 32)"
RATE_LIMIT_SALT="$(openssl rand -hex 32)"
deno eval 'import webpush from "npm:web-push@3.6.7"; console.log(JSON.stringify(webpush.generateVAPIDKeys()))'
```

Store these runtime keys in Supabase Edge Function secrets:

```text
CUSTOMER_PUSH_WORKER_SECRET
CUSTOMER_PUSH_RATE_LIMIT_SALT
VAPID_SUBJECT=mailto:notifications@zhirox.com
VAPID_PUBLIC_KEY
VAPID_PRIVATE_KEY
```

- [ ] **Step 8: Configure the one-minute cron at deployment time**

Store `WORKER_SECRET` in Vault under `customer_push_worker_secret`, then execute this SQL against the project database after substituting the runtime secret through the SQL client parameter, not inside a committed file:

```sql
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

select cron.unschedule(jobid)
from cron.job
where jobname='customer-push-worker-every-minute';

select cron.schedule(
  'customer-push-worker-every-minute',
  '* * * * *',
  $job$
  select net.http_post(
    url := 'https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/customer-push-worker',
    headers := jsonb_build_object(
      'content-type','application/json',
      'x-zhirox-push-worker',
      (select decrypted_secret from vault.decrypted_secrets where name='customer_push_worker_secret' limit 1)
    ),
    body := '{}'::jsonb
  );
  $job$
);
```

The secret value itself must never appear in the repository, migration history, Flutter bundle, or CI log.

- [ ] **Step 9: Commit**

```bash
git add supabase/functions/customer-push-worker \
        supabase/functions/_shared/customer_push \
        supabase/config.toml
git commit -m "feat(user): add reliable web push worker"
```

---

### Task 5: Payment event enqueue from the trusted payment gateway

**Files:**
- Modify: `supabase/functions/record-payment/index.ts`
- Create: `supabase/functions/record-payment/index_test.ts`

**Interface produced:** exactly one logical `payment_created` outbox event per successful `record-payment` API call.

**Payment allocation rule:** customer-wide payment can create multiple rows in `payments`; use the first persisted payment row as the canonical event record/idempotency anchor, but payload amount is the total user payment action.

- [ ] **Step 1: Write failing canonical-ID tests**

```ts
Deno.test("canonical payment id handles single and allocated results", () => {
  assertEquals(
    canonicalPaymentId({id:"00000000-0000-0000-0000-000000000401"}),
    "00000000-0000-0000-0000-000000000401",
  );
  assertEquals(
    canonicalPaymentId({payments:[
      {id:"00000000-0000-0000-0000-000000000402"},
      {id:"00000000-0000-0000-0000-000000000403"},
    ]}),
    "00000000-0000-0000-0000-000000000402",
  );
});
```

- [ ] **Step 2: Run RED**

```bash
deno test supabase/functions/record-payment/index_test.ts
```

Expected: missing helper/test target failure.

- [ ] **Step 3: Implement payment enqueue**

After the existing RPC returns success:
- resolve customer ID directly for customer-wide payment or through the debt row for debt-specific payment;
- read tenant admin ID/market name;
- compute total current non-deleted customer `remaining` in IQD;
- derive canonical payment ID;
- for debt-specific USD debt, convert stored payment amount to display USD using `dollar_rate`; customer-wide remains IQD;
- enqueue:

```ts
await admin.rpc("enqueue_customer_push_event_service", {
  p_market_id: marketId,
  p_customer_id: resolvedCustomerId,
  p_event_type: "payment_created",
  p_event_record_id: canonicalId,
  p_idempotency_key: `payment_created:${canonicalId}`,
  p_payload: {
    amount: displayAmount,
    currency: displayCurrency,
    remaining_iqd: totalRemainingIqd,
    market_name: marketName,
    occurred_at: new Date().toISOString(),
  },
});
```

Wrap only the enqueue portion in `try/catch`; sanitize logging and still return the successful payment response if enqueue fails.

- [ ] **Step 4: Test non-blocking failure**

```ts
Deno.test("push enqueue failure does not fail payment response", async () => {
  const result = await handleRecordPayment(validRequest, {
    recordPayment: async () => ({id:"00000000-0000-0000-0000-000000000401",amount:1000}),
    enqueuePush: async () => { throw new Error("push unavailable"); },
    loadContext: async () => paymentContext,
  });
  assertEquals(result.status, 200);
});
```

- [ ] **Step 5: Run GREEN**

```bash
deno test supabase/functions/record-payment/index_test.ts
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/record-payment
git commit -m "feat(user): enqueue payment push events"
```

---

### Task 6: Live debt enqueue and missed-event reconciliation

**Files:**
- Create: `supabase/functions/customer-push-events/index.ts`
- Create: `supabase/functions/customer-push-events/index_test.ts`
- Modify: `lib/services/pb_service.dart`
- Modify: `supabase/functions/customer-push-worker/index.ts`
- Modify: `supabase/functions/customer-push-worker/index_test.ts`

- [ ] **Step 1: Write failing debt eligibility tests**

```ts
Deno.test("reconciliation includes only live debt candidates", () => {
  const now = new Date("2026-09-17T01:00:00Z");
  assertEquals(isLiveDebtEligible({deleted:false,legacyLinked:false,syncLinked:false,createdAt:"2026-09-17T00:30:00Z",now}), true);
  assertEquals(isLiveDebtEligible({deleted:true,legacyLinked:false,syncLinked:false,createdAt:"2026-09-17T00:30:00Z",now}), false);
  assertEquals(isLiveDebtEligible({deleted:false,legacyLinked:true,syncLinked:false,createdAt:"2026-09-17T00:30:00Z",now}), false);
  assertEquals(isLiveDebtEligible({deleted:false,legacyLinked:false,syncLinked:true,createdAt:"2026-09-17T00:30:00Z",now}), false);
  assertEquals(isLiveDebtEligible({deleted:false,legacyLinked:false,syncLinked:false,createdAt:"2026-09-17T00:59:30Z",now}), false);
  assertEquals(isLiveDebtEligible({deleted:false,legacyLinked:false,syncLinked:false,createdAt:"2026-09-15T00:00:00Z",now}), false);
});
```

- [ ] **Step 2: Implement `customer-push-events`**

Authenticate bearer token. Accept only:

```json
{"action":"enqueue_debt","debt_id":"uuid"}
```

Re-read debt/customer/tenant. Require actor active+approved, actor role admin/employee, same tenant, and `debt.created_by == actor.id`. Reject soft-deleted debt. If the debt ID appears as `target_id` for `entity_kind='debt'` in `legacy_import_links` or `daftar_sync_seen`, return `{enqueued:false,reason:'non_live_source'}`.

Build amount from `amount_usd` for USD debts when valid; otherwise IQD `amount`. Compute customer remaining in IQD. Enqueue `debt_created:<debt_id>` idempotently.

- [ ] **Step 3: Run event API tests**

```bash
deno test supabase/functions/customer-push-events/index_test.ts
```

Expected: PASS for live debt, cross-tenant denial, wrong creator denial, import exclusion, sync exclusion, and duplicate enqueue.

- [ ] **Step 4: Add the non-blocking call to `PBService.createDebt`**

Immediately after the existing debt insert succeeds:

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

Keep all existing `createNotification(...)` and local `NotificationService.showDebtCreated(...)` behavior unchanged.

- [ ] **Step 5: Add worker reconciliation**

Before normal claims, reconcile at most 100 debts created between 24 hours ago and 2 minutes ago that:
- are not deleted;
- have no `debt_created:<id>` outbox row;
- have no matching `legacy_import_links` debt target;
- have no matching `daftar_sync_seen` debt target.

For each, build the same payload and call the idempotent enqueue RPC. The two-minute lower bound avoids racing an import/sync write before its provenance link is committed.

- [ ] **Step 6: Extend worker tests**

```ts
Deno.test("reconciliation is idempotent and excludes imported rows", async () => {
  const repo = fakeReconcileRepo({live:[liveDebt], legacy:[importedDebt], sync:[syncedDebt]});
  await reconcileRecentDebts(repo.deps);
  await reconcileRecentDebts(repo.deps);
  assertEquals(repo.enqueuedKeys, [`debt_created:${liveDebt.id}`]);
});
```

Run:

```bash
deno test supabase/functions/customer-push-events/index_test.ts \
          supabase/functions/customer-push-worker/index_test.ts
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/customer-push-events \
        supabase/functions/customer-push-worker \
        lib/services/pb_service.dart
git commit -m "feat(user): enqueue debt push events safely"
```

---

### Task 7: Flutter gateway, QR card, and customer profile integration

**Files:**
- Create: `lib/services/customer_push_service.dart`
- Create: `lib/widgets/customer_push_card.dart`
- Create: `test/customer_push_service_test.dart`
- Create: `test/customer_push_card_test.dart`
- Modify: `lib/screens/shared/user_profile_screen.dart`
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`

**Interfaces produced:**

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
```

- [ ] **Step 1: Add dependency and failing service test**

Add:

```yaml
qr_flutter: ^4.1.0
```

Test strict JSON parsing:

```dart
test('push status parses server response', () {
  final status = CustomerPushStatus.fromJson({
    'active': true,
    'device_count': 2,
    'latest_status': 'sent',
    'latest_at': '2026-09-17T00:00:00Z',
  });
  expect(status.active, isTrue);
  expect(status.deviceCount, 2);
  expect(status.latestAt, DateTime.parse('2026-09-17T00:00:00Z'));
});
```

- [ ] **Step 2: Run RED**

```bash
flutter test test/customer_push_service_test.dart
```

Expected: missing service class failure.

- [ ] **Step 3: Implement `CustomerPushService`**

Use `PBService.ensureInitialized()` and `PBService.client.functions.invoke('customer-push-admin', body: ...)`. Throw `FormatException` on malformed success payloads. Never model or expose subscription endpoints/key material.

- [ ] **Step 4: Run service GREEN**

```bash
flutter test test/customer_push_service_test.dart
```

Expected: PASS.

- [ ] **Step 5: Write failing widget tests**

Inject a fake gateway and verify:

```dart
testWidgets('QR button renders exact onboarding URL', (tester) async {
  final gateway = FakePushGateway(
    status: const CustomerPushStatus(active: false, deviceCount: 0),
    link: CustomerPushLink(
      url: Uri.parse('https://example.test/functions/v1/customer-push?token=${'a' * 64}'),
      expiresAt: DateTime.parse('2026-09-17T00:15:00Z'),
    ),
  );
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: CustomerPushCard(customerId:'c1', gateway:gateway))));
  await tester.pumpAndSettle();
  await tester.tap(find.text('QR ـی ئاگادارکردنەوە'));
  await tester.pumpAndSettle();
  expect(find.byType(QrImageView), findsOneWidget);
});
```

Also test active device count, revoke confirmation, refresh after revoke, and retry UI after a gateway error.

- [ ] **Step 6: Implement `CustomerPushCard`**

```dart
class CustomerPushCard extends StatefulWidget {
  final String customerId;
  final CustomerPushGateway gateway;

  const CustomerPushCard({
    super.key,
    required this.customerId,
    this.gateway = const CustomerPushService(),
  });
}
```

The widget owns only push status loading, QR dialog, revoke confirmation, and refresh. QR dialog uses:

```dart
QrImageView(
  data: link.url.toString(),
  version: QrVersions.auto,
  size: 240,
)
```

Display Sorani text that the QR is one-time and expires in 15 minutes.

- [ ] **Step 7: Integrate into customer overview**

In `UserProfileScreen._buildCustomerBody()`, add the card to the `overview` slivers after `_buildDebtLimitCard()` and only for authorized staff:

```dart
if (auth.canSendNotifications)
  SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: CustomerPushCard(customerId: widget.userId),
    ),
  ),
```

Do not add networking/state methods to `UserProfileScreen` itself.

- [ ] **Step 8: Run focused and full Flutter verification**

```bash
flutter pub get
flutter test test/customer_push_service_test.dart test/customer_push_card_test.dart
flutter test
flutter analyze
```

Expected: all exit 0.

- [ ] **Step 9: Commit**

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

### Task 8: Policy gate, CI, deployment, smoke test, and release evidence

**Files:**
- Create: `scripts/verify_customer_push.py`
- Modify: `.github/workflows/ios-unsigned-ipa.yml`

- [ ] **Step 1: Write the static verifier**

```python
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
required = [
    ROOT / 'supabase/functions/customer-push/index.ts',
    ROOT / 'supabase/functions/customer-push-admin/index.ts',
    ROOT / 'supabase/functions/customer-push-worker/index.ts',
    ROOT / 'supabase/functions/customer-push-events/index.ts',
    ROOT / 'lib/services/customer_push_service.dart',
    ROOT / 'lib/widgets/customer_push_card.dart',
]
for path in required:
    assert path.exists(), f'missing {path.relative_to(ROOT)}'

config = (ROOT / 'supabase/config.toml').read_text()
assert '[functions.customer-push]\nverify_jwt = false' in config
assert '[functions.customer-push-worker]\nverify_jwt = false' in config

flutter_text = '\n'.join(p.read_text(errors='ignore') for p in (ROOT / 'lib').rglob('*.dart'))
for name in ['VAPID_PRIVATE_KEY','CUSTOMER_PUSH_WORKER_SECRET','CUSTOMER_PUSH_RATE_LIMIT_SALT']:
    assert name not in flutter_text, f'server secret leaked to Flutter: {name}'

events_text = (ROOT / 'supabase/functions/customer-push-events/index.ts').read_text()
assert 'legacy_import_links' in events_text
assert 'daftar_sync_seen' in events_text

payment_text = (ROOT / 'supabase/functions/record-payment/index.ts').read_text()
assert 'payment_created' in payment_text
assert 'enqueue_customer_push_event_service' in payment_text

migration_text = '\n'.join(p.read_text() for p in (ROOT / 'supabase/migrations').glob('*.sql'))
assert "event_type in ('debt_created','payment_created')" in migration_text
print('customer push policy verified')
```

- [ ] **Step 2: Run verifier**

```bash
python3 scripts/verify_customer_push.py
```

Expected: prints `customer push policy verified`.

- [ ] **Step 3: Wire Deno/policy tests into existing iOS workflow**

Add before CocoaPods/analyze:

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

Do not remove any existing verification step.

- [ ] **Step 4: Run full pre-release verification**

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

- [ ] **Step 5: Deploy backend in dependency order**

1. Apply the push migration.
2. Deploy `customer-push-admin`, `customer-push`, `customer-push-worker`, `customer-push-events`, and the updated `record-payment`.
3. Generate/set `CUSTOMER_PUSH_WORKER_SECRET`, `CUSTOMER_PUSH_RATE_LIMIT_SALT`, `VAPID_SUBJECT`, `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`.
4. Store the same worker secret in Vault as `customer_push_worker_secret`.
5. Install the one-minute cron SQL from Task 4.
6. Invoke the worker once with the correct header and require HTTP 200 with a non-negative processed count.
7. Query `cron.job` and require exactly one active job named `customer-push-worker-every-minute`.

- [ ] **Step 6: Live smoke test with a dedicated test customer**

Execute in this order and capture row counts after each action:
1. Create QR; confirm expiry = 15 minutes.
2. Validate link; confirm only customer/market display names are returned.
3. Link device A; confirm same token cannot link again.
4. Create a new QR and link device B.
5. Create one live debt; require one `debt_created` outbox row and exactly two delivery rows.
6. Record one customer-wide payment spanning multiple debts; require one `payment_created` outbox row, not one per allocation, and two delivery rows.
7. Confirm both devices receive both notifications.
8. Revoke all; confirm both subscriptions inactive and unused QR tokens revoked.
9. Create another eligible event; require outbox completion with zero delivery rows.
10. Force a test subscription to return 410; confirm delivery `expired`, subscription inactive, financial transaction still successful.

- [ ] **Step 7: Trigger GitHub Actions and collect fresh release evidence**

Require the `iOS Unsigned IPA` run on `user-source` to show PASS for policy, Deno tests, Flutter analyze, Flutter tests, build, package, and release upload. Record:

```text
final commit SHA
workflow run ID
permanent user-latest IPA URL
IPA SHA-256
```

- [ ] **Step 8: Commit CI gate**

```bash
git add scripts/verify_customer_push.py .github/workflows/ios-unsigned-ipa.yml
git commit -m "ci(user): verify customer QR web push"
```

---

## Self-Review Results

- Every accepted spec section maps to a task: QR/token security, multi-device linking, iOS onboarding, server-only secrets, tenant permissions, rate limiting, outbox/idempotency, frozen fan-out, bounded retry, audit states, revoke-all, debt/payment-only event scope, import/sync exclusion, Flutter status/QR UI, CI, and iOS release verification.
- Customer-wide payment ambiguity is resolved: one payment action creates one push event using the first persisted allocation payment row only as the canonical event identifier; message amount is the full payment action.
- `fanout_at` prevents a newly linked device from receiving an old event during a retry pass.
- Claiming an outbox row sets a two-minute lease so a crashed worker can be reclaimed without concurrent immediate reprocessing.
- Existing in-app/local and Telegram paths are preserved.
- No runtime secret is committed to Git.
- No unresolved placeholder or unspecified interface remains in this plan.
