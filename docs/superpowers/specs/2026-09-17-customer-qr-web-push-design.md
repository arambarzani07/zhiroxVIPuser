# Customer QR Web Push Notifications — Design

Date: 2026-09-17
Branch: `user-source`
Project: `arambarzani07/zhiroxVIPuser`

## 1. Goal

Add a secure opt-in notification channel for customers without Viber, Telegram, SMS, or KYC requirements.

Each customer can receive automatic Web Push notifications after linking a browser/device to their customer record through a customer-specific QR flow. The first release sends notifications only for:

1. a newly created debt (`debt_created`), and
2. a newly recorded payment (`payment_created`).

Debt/payment edits, deletions, reminders, marketing messages, and other activity types are explicitly out of scope.

## 2. Core user flow

### Admin / market staff

1. Open a customer profile.
2. Tap **QR ـی ئاگادارکردنەوە**.
3. The backend creates a short-lived, one-time link token.
4. The app renders a QR containing only an HTTPS onboarding URL with the opaque token.
5. The admin can see current push status, linked device count, latest delivery status, regenerate a QR, or revoke all linked devices.

### Customer

1. Scan the QR once.
2. Open the ZHIROX Notifications onboarding page.
3. Confirm the market/customer association shown by the server.
4. Enable browser notifications.
5. The browser/device push subscription is attached to that customer.
6. Future new-debt and new-payment events automatically generate notifications for every active linked device.

For iPhone/iPad Web Push, onboarding must explain that the customer needs to add the web app to the Home Screen and then enable notifications from the installed web app. The token remains redeemable during this onboarding sequence until the first subscription registration succeeds or the token expires.

## 3. Architectural boundaries

The feature is split into small units with clear responsibilities.

### 3.1 Link-token service

Purpose: create and redeem secure customer-device linking tokens.

Responsibilities:
- create cryptographically random tokens;
- persist only a token hash, never the raw token;
- bind each token to `market_id` and `customer_id`;
- enforce expiration and one-time use;
- reject revoked, expired, already-used, wrong-market, or malformed tokens;
- return only the minimum customer/market display information needed by onboarding.

The raw token appears only in the HTTPS QR URL and is never stored in plaintext in the database.

### 3.2 Push subscription service

Purpose: attach Web Push subscriptions to an already validated customer link.

Responsibilities:
- validate a redeemable QR token;
- register the browser endpoint plus its Web Push public keys;
- allow multiple active devices per customer;
- prevent duplicate active subscriptions for the same browser endpoint;
- mark the token used only after successful subscription registration;
- allow a subscription to deactivate itself;
- allow authorized market staff to revoke all subscriptions for one customer.

### 3.3 Notification outbox

Purpose: decouple financial transactions from delivery.

Responsibilities:
- create exactly one logical notification event for each eligible debt/payment transaction;
- assign a unique idempotency key derived from event type plus financial record ID;
- store the customer, market, event type, event record ID, immutable payload snapshot, status, and timestamps;
- never block or roll back the financial transaction because push delivery fails.

### 3.4 Delivery worker

Purpose: deliver pending outbox events to active customer subscriptions.

Responsibilities:
- fan out one outbox event to every active device for that customer;
- sign Web Push requests with server-side VAPID credentials;
- record one delivery row per device;
- retry transient failures with bounded exponential backoff;
- deactivate permanently invalid/expired browser subscriptions;
- make repeated processing safe through idempotency and delivery uniqueness constraints.

### 3.5 Flutter customer-profile integration

Purpose: give staff a small management surface inside the existing customer profile.

It shows:
- Push status: active/inactive;
- number of active linked devices;
- latest delivery state/time;
- **QR ـی ئاگادارکردنەوە** action;
- **بڕینی هەموو device ـەکان** action.

This UI must not contain VAPID private keys or any server credential.

### 3.6 Web onboarding/PWA surface

Purpose: complete customer linking and request Web Push permission.

It contains:
- ZHIROX/market branding;
- server-confirmed customer display name;
- a clear **چالاککردنی ئاگادارکردنەوە** action;
- iOS-specific Add-to-Home-Screen guidance when required;
- success/failure/retry states;
- no exposed internal customer ID.

## 4. Database design

### 4.1 `customer_push_link_tokens`

Fields:
- `id uuid primary key`
- `market_id uuid not null`
- `customer_id uuid not null`
- `token_hash text not null unique`
- `expires_at timestamptz not null`
- `used_at timestamptz null`
- `revoked_at timestamptz null`
- `created_by uuid not null`
- `created_at timestamptz not null default now()`

Rules:
- default lifetime: 15 minutes;
- one successful subscription registration consumes the token;
- raw token is never persisted;
- staff may invalidate an unused token by creating a replacement or explicitly revoking it.

### 4.2 `customer_push_subscriptions`

Fields:
- `id uuid primary key`
- `market_id uuid not null`
- `customer_id uuid not null`
- `endpoint text not null`
- `p256dh text not null`
- `auth text not null`
- `user_agent text null`
- `platform text null`
- `active boolean not null default true`
- `last_success_at timestamptz null`
- `last_failure_at timestamptz null`
- `failure_count integer not null default 0`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Constraints:
- unique active identity for an endpoint;
- one customer may have multiple active devices;
- subscription secrets are readable only by trusted backend/service-role paths, not ordinary clients.

### 4.3 `notification_outbox`

Fields:
- `id uuid primary key`
- `market_id uuid not null`
- `customer_id uuid not null`
- `event_type text not null check (event_type in ('debt_created','payment_created'))`
- `event_record_id uuid not null`
- `idempotency_key text not null unique`
- `payload jsonb not null`
- `status text not null check (status in ('pending','processing','sent','failed'))`
- `attempt_count integer not null default 0`
- `next_attempt_at timestamptz not null default now()`
- `last_error text null`
- `created_at timestamptz not null default now()`
- `processed_at timestamptz null`

The payload is an immutable delivery snapshot so later debt/payment edits cannot silently rewrite the notification that was originally generated.

### 4.4 `notification_deliveries`

Fields:
- `id uuid primary key`
- `outbox_id uuid not null`
- `subscription_id uuid not null`
- `status text not null check (status in ('pending','sent','failed','expired'))`
- `attempt_count integer not null default 0`
- `provider_status integer null`
- `last_error text null`
- `sent_at timestamptz null`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Constraint:
- unique (`outbox_id`, `subscription_id`) to prevent duplicate delivery to the same device for the same event.

## 5. Event production

Push events must be created only from the canonical successful financial transaction paths, never from UI-only callbacks.

### Debt created

After a new debt is successfully committed by the production debt-creation path, enqueue one `debt_created` outbox event with idempotency key:

`debt_created:<debt_id>`

Payload snapshot contains only notification-safe data required to render the message, including amount/currency, resulting customer balance when available, market display name, and event timestamp.

### Payment created

After `record-payment` successfully commits the payment transaction, enqueue one `payment_created` outbox event with idempotency key:

`payment_created:<payment_id>`

This enqueue step belongs inside the trusted backend transaction boundary or immediately after a committed transaction through an idempotent backend operation. Client-side notification code is not the source of truth.

### Import/sync safety

Historical imports, legacy synchronization, restore flows, debt edits, and payment edits/deletions must not enqueue push events unless they explicitly use the real-time production create path. This prevents historical data from generating unexpected customer notifications.

## 6. Delivery semantics

1. A successful financial transaction is authoritative even if push delivery fails.
2. The outbox worker processes events independently.
3. Each event fans out to all currently active subscriptions for that customer.
4. A successful delivery updates subscription `last_success_at` and the delivery row.
5. HTTP responses that indicate a permanently invalid subscription deactivate that subscription and mark the delivery `expired`.
6. Transient failures are retried with bounded exponential backoff.
7. Retry is capped; after the cap the delivery/outbox becomes `failed` and remains auditable.
8. Re-running the worker cannot create duplicate deliveries because both event and event-device pairs are unique.

Initial retry policy:
- attempt 1: immediate;
- attempt 2: +1 minute;
- attempt 3: +5 minutes;
- attempt 4: +30 minutes;
- attempt 5: +2 hours;
- then permanent `failed` until a future explicit admin retry feature is designed.

An admin retry UI is out of scope for the first release.

## 7. Security model

- HTTPS only for onboarding and service-worker delivery.
- Raw QR tokens are high-entropy random values and are not customer IDs.
- Database stores only token hashes.
- Link tokens are scoped to one market and one customer.
- Link tokens expire after 15 minutes and are single-use.
- VAPID private key exists only in backend secret storage.
- Ordinary Flutter/web clients cannot read subscription secrets, outbox internals, or VAPID credentials.
- RLS/privilege rules deny cross-market reads and writes.
- Token redemption endpoints use rate limiting and generic failure responses so they do not become a customer-enumeration oracle.
- Revoke-all immediately deactivates every subscription belonging to the selected customer and market.
- Financial payloads are minimized: no password, authentication token, hidden internal note, or unnecessary PII is sent in a push body.

## 8. Notification copy

### New debt

Title:
`🧾 قەرزی نوێ تۆمارکرا`

Body example:
`بڕ: 50,000 د.ع • کۆی ماوە: 125,000 د.ع • مارکێت: [ناوی مارکێت]`

### New payment

Title:
`💰 پارەدانەوە تۆمارکرا`

Body example:
`بڕی دراو: 25,000 د.ع • ماوە: 100,000 د.ع • مارکێت: [ناوی مارکێت]`

Tapping a notification opens a protected customer-facing route using a server-issued scoped reference. It must not expose a raw `customer_id` in the URL.

## 9. iPhone/iPad behavior

The onboarding page must detect the iOS Web Push prerequisites and guide the customer through them.

Required behavior:
- QR opens the onboarding URL in Safari.
- If the page is not running as a Home Screen web app, show concise Add-to-Home-Screen instructions and preserve the still-valid association token.
- When opened from the Home Screen, the customer taps **چالاککردنی ئاگادارکردنەوە**.
- Only that explicit user action requests notification permission.
- On successful browser subscription, the backend consumes the one-time link token.

If the token expires before registration completes, the page shows a safe expired-link state and the admin generates a fresh QR.

## 10. Error handling and UX states

Onboarding states:
- validating link;
- valid link / ready to enable;
- iOS Add-to-Home-Screen required;
- permission denied;
- subscription registration in progress;
- linked successfully;
- expired/used/revoked link;
- temporary network error with retry.

Customer-profile states:
- no linked device;
- linked with device count;
- latest delivery succeeded;
- latest delivery failed;
- generating QR;
- revoke-all confirmation and completion.

No push error is surfaced as a financial transaction failure.

## 11. Testing strategy

### Database/security tests

Cover:
- valid token creation and redemption;
- token reuse rejection;
- expired token rejection;
- revoked token rejection;
- wrong-market access rejection;
- subscription secrets inaccessible to ordinary users;
- multi-device registration;
- duplicate endpoint handling;
- revoke-all scoping;
- outbox event uniqueness;
- delivery uniqueness.

### Event tests

Cover:
- new debt produces exactly one `debt_created` event;
- new payment produces exactly one `payment_created` event;
- debt edit produces no push event;
- payment edit/delete produces no new push event;
- historical import/restore produces no push event;
- push failure does not roll back a debt/payment transaction.

### Delivery worker tests

Cover:
- fan-out to multiple devices;
- success updates audit fields;
- transient failure schedules retry;
- permanent invalid subscription deactivates device;
- duplicate worker execution is idempotent;
- retry cap produces auditable failure.

### Flutter/web tests

Cover:
- customer profile push-status presentation;
- QR generation state;
- revoke confirmation;
- onboarding valid/invalid/expired states;
- iOS Home Screen guidance;
- notification permission denial;
- successful subscription linking.

### CI verification

Before release:
- migration/security checks;
- backend/Edge Function tests;
- Flutter analyze;
- Flutter tests;
- existing online-only/payment security checks;
- iOS unsigned IPA build must remain green.

## 12. Files/components expected to change

Implementation is expected to touch focused areas only:
- new Supabase migration(s) for push link/subscription/outbox/delivery tables and RLS;
- new Edge Function(s) for link creation/redemption/subscription management and push delivery;
- canonical debt/payment backend paths for idempotent enqueue;
- a small Flutter service/model layer for QR/status actions;
- customer profile UI for QR/status/revoke controls;
- a web/PWA onboarding surface plus service worker and manifest changes as needed;
- regression/security tests;
- CI policy checks only where required by the new files/flows.

Unrelated financial, dashboard, customer-list, import, receipt, and synchronization behavior must remain unchanged.

## 13. Explicit non-goals

The first release does not include:
- Viber;
- Telegram;
- SMS fallback;
- email;
- marketing/broadcast notifications;
- due-date reminders;
- debt/payment edit or delete notifications;
- admin manual resend/retry UI;
- native APNs/FCM push as a replacement for Web Push;
- KYC/business-provider onboarding.

## 14. Acceptance criteria

The feature is complete only when all of the following are true:

1. Staff can generate a short-lived customer-specific QR from the customer profile.
2. QR does not expose a raw customer ID and cannot be reused after successful linking.
3. A customer can link at least one supported browser/device through the onboarding flow.
4. A customer can link multiple devices using separate QR sessions.
5. iPhone/iPad onboarding correctly handles the Home Screen Web Push requirement.
6. New debt and new payment events create one idempotent outbox event each.
7. No other financial event type creates a push event.
8. All active devices receive the eligible notification independently.
9. Invalid subscriptions are retired automatically; transient failures retry without affecting finance transactions.
10. Staff can see linked-device count/latest delivery status and revoke all customer devices.
11. Cross-market access is blocked and server secrets remain server-side.
12. Regression, security, Flutter, backend, and CI/iOS build checks pass before release.
