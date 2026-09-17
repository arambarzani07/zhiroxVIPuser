# Customer Push Custom Domain Hosting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the customer Web Push onboarding PWA to `https://push.zhirox.com` on Netlify while keeping Supabase as the secure JSON API/backend.

**Architecture:** A small static PWA will live under `customer-push-web/` and be deployed to a dedicated Netlify project. It will call `https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/customer-push` only for JSON actions. `customer-push-admin` will generate QR links for `https://push.zhirox.com/?token=...`, and the worker will open the generic `https://push.zhirox.com/` URL when a notification is tapped.

**Tech Stack:** Static HTML/CSS/JavaScript, Service Worker API, Push API, Netlify static hosting, Supabase Edge Functions (Deno), Flutter/Dart tests, Python policy verification, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-17-customer-push-domain-hosting-design.md`

## Global Constraints

- Work only on branch `user-source`.
- Canonical public origin is exactly `https://push.zhirox.com`.
- Supabase project URL remains `https://hsoyfbtpvwfmjokudznx.supabase.co`.
- No service-role key, VAPID private key, worker secret, rate-limit salt, subscription key material, or customer database data may be embedded in static frontend files.
- QR token remains 64 lowercase hex, valid for exactly 15 minutes, and only its SHA-256 hash is persisted server-side.
- On iPhone/iPad, notification permission is requested only after the site is opened from Add to Home Screen.
- Notification click target is the generic `https://push.zhirox.com/` page and contains no `customer_id`.
- Existing debt/payment push semantics, retry policy, Telegram behavior, and financial transaction semantics remain unchanged.
- `customer-push` remains `verify_jwt = false` because it implements token-based public access and server-side rate limiting.
- `customer-push-worker` remains `verify_jwt = false` because it uses the existing private worker header secret.
- Existing Flutter analyze/tests, Deno tests, customer-push verifier, and iOS unsigned IPA workflow must stay green.

---

## File Structure

### Create
- `customer-push-web/index.html` — Kurdish RTL onboarding shell only.
- `customer-push-web/app.js` — token validation, iOS/PWA gating, Push API subscription, and Supabase JSON calls.
- `customer-push-web/sw.js` — push display and generic notification click handling.
- `customer-push-web/manifest.webmanifest` — standalone PWA metadata with `/` scope.
- `customer-push-web/_headers` — Netlify security/cache/content-type headers.

### Modify
- `supabase/functions/customer-push-admin/index.ts` — production QR base URL.
- `supabase/functions/customer-push-admin/index_test.ts` — assert canonical domain and 15-minute token behavior.
- `supabase/functions/customer-push-worker/index.ts` — generic notification click URL.
- `supabase/functions/customer-push-worker/index_test.ts` — assert generic click URL.
- `supabase/functions/customer-push/index.ts` — keep supported production path JSON-only; preserve backward-compatible GET response temporarily if desired, but frontend no longer depends on it.
- `supabase/functions/customer-push/index_test.ts` — assert JSON API behavior and CORS remain intact.
- `scripts/verify_customer_push.py` — enforce custom-domain/static-PWA policy.
- `.github/workflows/ios-unsigned-ipa.yml` — no new workflow; existing customer-push gate must cover new static-PWA policy.

---

### Task 1: Static onboarding PWA

**Files:**
- Create: `customer-push-web/index.html`
- Create: `customer-push-web/app.js`
- Create: `customer-push-web/sw.js`
- Create: `customer-push-web/manifest.webmanifest`
- Create: `customer-push-web/_headers`
- Modify: `scripts/verify_customer_push.py`

**Interfaces:**
- Consumes: query parameter `token=<64 lowercase hex>`.
- Calls: `POST https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/customer-push` with actions `validate`, `subscribe`, `unsubscribe`.
- Produces: a same-origin service worker at `/sw.js` with scope `/` and a standalone PWA at `/`.

- [ ] **Step 1: Extend the policy verifier first**

Add exact assertions like:

```python
web = ROOT / 'customer-push-web'
for name in ('index.html', 'app.js', 'sw.js', 'manifest.webmanifest', '_headers'):
    assert (web / name).exists(), f'missing customer push web asset: {name}'

app_js = (web / 'app.js').read_text(errors='ignore')
assert 'https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/customer-push' in app_js
assert 'SUPABASE_SERVICE_ROLE_KEY' not in app_js
assert 'VAPID_PRIVATE_KEY' not in app_js
assert 'customer_id' not in (web / 'sw.js').read_text(errors='ignore')

manifest = (web / 'manifest.webmanifest').read_text(errors='ignore')
assert '"scope": "/"' in manifest
assert '"start_url": "/"' in manifest
```

- [ ] **Step 2: Run verifier and confirm RED**

Run:

```bash
python3 scripts/verify_customer_push.py
```

Expected: FAIL because `customer-push-web/` assets do not exist yet.

- [ ] **Step 3: Create the minimal static PWA**

`index.html` must contain no backend secrets and must only reference same-origin assets:

```html
<!doctype html>
<html lang="ku" dir="rtl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
  <meta name="theme-color" content="#ffffff">
  <title>ZHIROX Notifications</title>
  <link rel="manifest" href="/manifest.webmanifest">
  <script defer src="/app.js"></script>
</head>
<body>
  <main class="card">
    <h1>ئاگادارکردنەوەی ZHIROX</h1>
    <p id="status">پشکنینی لینک...</p>
    <section id="identity" hidden>
      <p><strong>کڕیار:</strong> <span id="customerName"></span></p>
      <p><strong>مارکێت:</strong> <span id="marketName"></span></p>
    </section>
    <section id="iosHelp" hidden>
      <p>لە Safari دوگمەی Share بکە، Add to Home Screen هەڵبژێرە، پاشان لە Home Screen بکەرەوە.</p>
    </section>
    <button id="enable" hidden>چالاککردنی ئاگادارکردنەوە</button>
    <p id="result"></p>
  </main>
</body>
</html>
```

`app.js` must:
- reject any token not matching `/^[a-f0-9]{64}$/` before contacting Supabase,
- call `validate` first,
- display only customer/market display fields returned by the API,
- on iOS, require standalone display mode before revealing the enable button,
- register `/sw.js` with scope `/`,
- subscribe with the returned public VAPID key,
- send the browser subscription to `subscribe`,
- store only `device_secret` and endpoint in localStorage,
- show generic Kurdish errors without rendering raw backend messages.

`sw.js` must display `{title, body}` and open exactly `/` on click:

```js
self.addEventListener('push', (event) => {
  const data = event.data ? event.data.json() : {};
  event.waitUntil(self.registration.showNotification(data.title || 'ZHIROX', {
    body: data.body || '',
    data: { url: '/' },
  }));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(clients.openWindow('/'));
});
```

`manifest.webmanifest` must use `/` for both `start_url` and `scope` and `display: "standalone"`.

`_headers` must include:

```text
/*
  Referrer-Policy: no-referrer
  X-Content-Type-Options: nosniff
  Cache-Control: no-store
  Content-Security-Policy: default-src 'self'; connect-src 'self' https://hsoyfbtpvwfmjokudznx.supabase.co; worker-src 'self'; manifest-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'

/sw.js
  Content-Type: application/javascript; charset=utf-8
  Service-Worker-Allowed: /

/manifest.webmanifest
  Content-Type: application/manifest+json; charset=utf-8
```

- [ ] **Step 4: Run verifier and confirm GREEN**

```bash
python3 scripts/verify_customer_push.py
```

Expected: `customer push policy verified`.

- [ ] **Step 5: Commit Task 1**

```bash
git add customer-push-web scripts/verify_customer_push.py
git commit -m "feat(user): add customer push onboarding PWA"
```

---

### Task 2: Point QR generation and notification clicks to the custom domain

**Files:**
- Modify: `supabase/functions/customer-push-admin/index.ts`
- Modify: `supabase/functions/customer-push-admin/index_test.ts`
- Modify: `supabase/functions/customer-push-worker/index.ts`
- Modify: `supabase/functions/customer-push-worker/index_test.ts`

**Interfaces:**
- Produces QR URL: `https://push.zhirox.com/?token=<64 lowercase hex>`.
- Produces push click URL: `https://push.zhirox.com/`.

- [ ] **Step 1: Make admin test fail on the old Supabase URL**

Change the create-link test to require:

```ts
assertEquals(
  response.url,
  `https://push.zhirox.com/?token=${"a".repeat(64)}`,
);
```

Run:

```bash
deno test --allow-env supabase/functions/customer-push-admin
```

Expected: FAIL because production code still uses the Supabase function URL.

- [ ] **Step 2: Change admin production base URL**

In `customer-push-admin/index.ts`, set:

```ts
publicBaseUrl: "https://push.zhirox.com/",
```

Keep token generation, SHA-256 storage, and 15-minute expiry unchanged.

- [ ] **Step 3: Add worker click-target test first**

Capture the message passed to `sendPush` and assert:

```ts
assertEquals(observedMessage?.url, "https://push.zhirox.com/");
```

Run:

```bash
deno test --allow-env supabase/functions/customer-push-worker
```

Expected: FAIL while the worker still sends `/functions/v1/customer-push`.

- [ ] **Step 4: Change worker click target**

In `processOutboxEvent`, send:

```ts
url: "https://push.zhirox.com/",
```

Do not change retry, fanout, delivery, or reconciliation logic.

- [ ] **Step 5: Run focused Deno tests**

```bash
deno test --allow-env \
  supabase/functions/customer-push-admin \
  supabase/functions/customer-push-worker
```

Expected: PASS.

- [ ] **Step 6: Commit Task 2**

```bash
git add supabase/functions/customer-push-admin supabase/functions/customer-push-worker
git commit -m "feat(user): route customer push through custom domain"
```

---

### Task 3: Keep the Supabase public function JSON-only for the supported production flow

**Files:**
- Modify: `supabase/functions/customer-push/index.ts`
- Modify: `supabase/functions/customer-push/index_test.ts`

**Interfaces:**
- `POST /functions/v1/customer-push` with `validate`, `subscribe`, `unsubscribe` remains unchanged.
- CORS continues to allow the static PWA to call the endpoint from `https://push.zhirox.com`.

- [ ] **Step 1: Add a regression test for JSON API and CORS**

For `validate`, assert:

```ts
assertEquals(res.status, 200);
assertEquals(res.headers.get("content-type")?.includes("application/json"), true);
assertEquals(res.headers.get("access-control-allow-origin"), "*");
```

For `OPTIONS`, assert status `200` and that POST is included in `Access-Control-Allow-Methods`.

- [ ] **Step 2: Run test before edits**

```bash
deno test --allow-env supabase/functions/customer-push
```

Expected: current JSON tests pass; any new CORS assertion that exposes a gap must fail before the smallest production fix.

- [ ] **Step 3: Remove production dependency on Edge-hosted PWA assets**

Keep the POST route and public rate limiting exactly as-is. The GET fallback may return a small generic migration notice or remain for backward compatibility, but new QR links must never rely on the Edge-hosted manifest or service worker.

- [ ] **Step 4: Run customer-push Deno tests**

```bash
deno test --allow-env supabase/functions/customer-push
```

Expected: PASS.

- [ ] **Step 5: Commit Task 3**

```bash
git add supabase/functions/customer-push
git commit -m "refactor(user): keep customer push edge endpoint api focused"
```

---

### Task 4: Full repository verification before deployment

**Files:**
- Modify only if a failing existing gate requires a minimal compatibility fix: `.github/workflows/ios-unsigned-ipa.yml`

- [ ] **Step 1: Run customer push policy**

```bash
python3 scripts/verify_customer_push.py
```

Expected: PASS.

- [ ] **Step 2: Run all customer push Deno tests**

```bash
deno test --allow-env \
  supabase/functions/_shared/customer_push \
  supabase/functions/customer-push-admin \
  supabase/functions/customer-push \
  supabase/functions/customer-push-worker \
  supabase/functions/customer-push-events \
  supabase/functions/record-payment
```

Expected: PASS.

- [ ] **Step 3: Run Flutter focused tests**

```bash
flutter test test/customer_push_service_test.dart test/customer_push_card_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run full analyze and tests**

```bash
flutter analyze
flutter test
```

Expected: PASS with no analyzer errors.

- [ ] **Step 5: Push `user-source` and wait for the existing iOS workflow**

The existing workflow must execute its customer-push policy/Deno gates and produce the unsigned User IPA without changing owner-source behavior.

---

### Task 5: Production deployment and domain cutover

**Production resources:**
- Supabase project: `hsoyfbtpvwfmjokudznx`.
- Netlify project: create new dedicated project named `zhirox-push` if available.
- Canonical domain: `push.zhirox.com`.

- [ ] **Step 1: Create the dedicated Netlify project**

Use the connected Netlify account and create a new site named `zhirox-push`. Do not reuse the unrelated `daftarqarzsafeen-*` sites.

- [ ] **Step 2: Deploy `customer-push-web/` as the site publish directory**

The deployed Netlify URL must serve:

```text
/                    -> text/html
/app.js              -> JavaScript
/sw.js               -> application/javascript
/manifest.webmanifest -> application/manifest+json
```

- [ ] **Step 3: Bind `push.zhirox.com`**

If the connected Netlify connector exposes custom-domain management, bind the domain directly and let Netlify provision TLS. If it does not expose domain/DNS mutation, record the exact Netlify site hostname and required CNAME target, then use the domain's DNS provider to create:

```text
Type: CNAME
Name: push
Target: <the exact Netlify hostname for the new zhirox-push site>
```

Do not claim production cutover complete until `https://push.zhirox.com` resolves over HTTPS.

- [ ] **Step 4: Deploy changed Supabase functions**

Deploy from `user-source`:
- `customer-push-admin` with `verify_jwt=true`.
- `customer-push` with `verify_jwt=false`.
- `customer-push-worker` with `verify_jwt=false`.

Do not redeploy unrelated Edge Functions.

- [ ] **Step 5: Verify fresh production state**

Verify all of the following with fresh evidence:

```text
GET https://push.zhirox.com/                         -> 200 text/html
GET https://push.zhirox.com/sw.js                    -> 200 application/javascript
GET https://push.zhirox.com/manifest.webmanifest     -> 200 application/manifest+json
```

Generate a new customer QR and verify its URL starts with:

```text
https://push.zhirox.com/?token=
```

The token must be exactly 64 lowercase hex characters and have a 15-minute expiry.

- [ ] **Step 6: Verify runtime and worker remain healthy**

Confirm the existing customer-push worker cron still runs every minute and returns HTTP 200 with a JSON body such as:

```json
{"ok":true,"reconciled":0,"processed":0}
```

- [ ] **Step 7: Real-device acceptance test**

On iPhone/iPad:
1. Generate a fresh QR.
2. Scan it in Safari.
3. Confirm the page renders normally rather than showing HTML source.
4. Share -> Add to Home Screen.
5. Open from Home Screen.
6. Enable notifications.
7. Confirm staff status shows at least one active device.
8. Create one explicit test debt or payment only with user approval.
9. Confirm the push arrives and tapping it opens `https://push.zhirox.com/` without a customer ID in the URL.

- [ ] **Step 8: Final verification record**

Report:
- final `user-source` commit SHA,
- GitHub Actions run ID and conclusion,
- final IPA download URL and SHA-256,
- Netlify site ID and production hostname,
- `push.zhirox.com` HTTPS status,
- deployed Supabase function versions,
- worker cron status,
- real-device push status (pass / not yet performed).
