# Customer QR Web Push Notifications — Design

Date: 2026-09-17
Branch: `user-source`
Project: `arambarzani07/zhiroxVIPuser`

## 1. Goal

Add a secure opt-in Web Push notification channel for customers without Viber, Telegram, SMS, email, KYC, or a third-party messaging provider.

Each customer can link one or more browser/devices to their customer record through a customer-specific QR flow. The first release sends notifications only for:

1. a newly created debt (`debt_created`), and
2. a newly recorded payment (`payment_created`).

Debt/payment edits, deletions, reminders, marketing messages, and other activity types are explicitly out of scope.

## 2. Core user flow

### Admin / market staff

1. Open a customer profile.
2. Tap **QR ـی ئاگادارکردنەوە**.
3. The backend creates a short-lived, one-time link token.
4. The app renders a QR containing only an HTTPS onboarding URL with the opaque token.
5. Staff can see push status, linked-device count, latest delivery status, generate a fresh QR, or revoke all linked devices.

### Customer

1. Scan the QR.
2. Open the ZHIROX Notifications onboarding page.
3. Confirm the server-provided market/customer display information.
4. Enable browser notifications.
5. The browser/device push subscription is attached to that customer.
6. Future new-debt and new-payment events automatically generate notifications for every active linked device.

For iPhone/iPad Web Push, onboarding explains that the customer must add the web app to the Home Screen and then enable notifications from the installed web app. The token remains redeemable during this onboarding sequence until the first successful subscription registration or token expiry.

## 3. Architectural boundaries

The feature is split into focused units with clear responsibilities.

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
- prevent duplicate active subscriptions for the same endpoint;
- mark the QR token used only after successful subscription registration;
- allow a subscription to deactivate itself;
- allow authorized market staff to revoke all subscriptions for one customer.

### 3.3 Notification outbox

Purpose: decouple financial transactions from delivery.

Responsibilities:
- create exactly one logical notification event for each eligible debt/payment transaction;
- assign a unique idempotency key derived from event type plus financial record ID;
- store customer, market, event type, event record ID, immutable payload snapshot, status, and timestamps;
- never block or roll back a financial transaction because push delivery fails.

### 3.4 Delivery worker

Purpose: deliver pending outbox events to active customer subscriptions.

Responsibilities:
- fan out one outbox event to every active device for that customer;
- sign Web Push requests with server-side VAPID credentials;
- record one delivery row per device;
- retry transient failures with bounded exponential backoff;
- deactivate permanently invalid/expired browser subscriptions;
- make repeated processing safe through idempotency and delivery uniqueness constraints.

The worker runs as a Supabase Edge Function on a once-per-minute scheduled invocation. It uses service-role access and is never callable as a privileged operation from an ordinary client.

### 3.5 Flutter customer-profile integration

Purpose: give staff a small management surface inside the existing customer profile.

It shows:
- Push status: active/inactive;
- number of active linked devices;
- latest delivery state/time;
- **QR ـی ئاگادارکردنەوە** action;
- **بڕینی هەموو device ـەکان** action.

This UI contains no VAPID private key or other server credential.

### 3.6 Web onboarding/PWA surface

Purpose: complete customer linking and request Web Push permission.

The first release is hosted from a dedicated public Supabase Edge Function route under the existing project HTTPS origin. The same function serves the onboarding HTML, web manifest, service-worker script, and required icon/static responses, so no separate hosting provider is required.

It contains:
- ZHIROX/market branding;
- server-confirmed customer display name;
- a clear **چالاککردنی ئاگادارکردنەوە** action;
- iOS-specific Add-to-Home-Screen guidance when required;
- success/failure/retry states;
- no exposed internal customer ID.

The public route is token-based and performs its own validation. Privileged admin actions remain authenticated and separate from public onboarding routes.

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
- generating a replacement QR revokes any still-unused active QR tokens for that same customer/market.

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
- an endpoint may have only one active subscription row;
- one customer may have multiple active devices;
- endpoint/key material is readable only by trusted backend/service-role paths, not ordinary clients.

### 4.3 `notification_outbox`

Fields:
- `id uuid primary key`
- `market_id uuid not null`
- `customer_id uuid not null`
- `event_type text not null check (event_type in ('debt_created','payment_created'))`
- `event_record_id uuid not null`
- `idempotency_key text not null unique`
- `payload jsonb not null`
- `status text not null check (status in ('pending','processing','completed','failed'))`
- `attempt_count integer not null default 0`
- `next_attempt_at timestamptz not null default now()`
- `last_error text null`
- `created_at timestamptz not null default now()`
- `completed_at timestamptz null`

The payload is an immutable delivery snapshot so later debt/payment edits cannot rewrite the message originally generated.

`completed` means fan-out has finished and no retryable device delivery remains. An event with zero active subscriptions is also completed with zero delivery rows; it is not held for devices linked in the future.

### 4.4 `notification_deliveries`

Fields:
- `id uuid primary key`
- `outbox_id uuid not null`
- `subscription_id uuid not null`
- `status text not null check (status in ('pending','sent','failed','expired'))`
- `attempt_count integer not null default 0`
- `provider_status integer null`
- `last_error text null`
- `next_attempt_at timestamptz null`
- `sent_at timestamptz null`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Constraint:
- unique (`outbox_id`, `subscription_id`) to prevent duplicate delivery to the same device for the same event.

## 5. Event production

Push events are created only from the normal live debt/payment creation paths, never from UI-only notification callbacks.

### Debt created

The existing live application debt-creation path remains the source of the debt itself. After a successful live debt insert, the application invokes a trusted idempotent enqueue endpoint using the authenticated user session and created debt ID. The backend re-reads the debt, verifies that the actor is authorized for that market/customer, verifies that the record is a newly created live debt, and inserts:

`debt_created:<debt_id>`

into the outbox only if it does not already exist.

This enqueue failure is recorded/retryable but does not roll back the already-successful debt transaction. To close the small client-interruption gap between debt creation and enqueue, the delivery subsystem includes a reconciliation query for recent live debts created through the normal application path that have no matching outbox event. Historical/import/sync records are explicitly excluded by their existing import/sync provenance and timestamps.

### Payment created

`record-payment` is already a trusted backend path. After the payment transaction is committed, that backend path performs an idempotent enqueue for:

`payment_created:<payment_id>`

The payment remains successful even if later delivery fails.

### Import/sync/restore safety

Historical imports, legacy synchronization, restore flows, debt edits, and payment edits/deletions do not enqueue customer push events. Reconciliation must use the existing import/sync provenance tables/links to exclude records created by those subsystems rather than relying only on a recent timestamp.

### Payload snapshot

Both event types snapshot only notification-safe fields required for rendering:
- amount and currency;
- resulting customer balance when available;
- market display name;
- event timestamp;
- event type and internal event reference.

Internal notes, passwords, auth tokens, and unrelated customer PII are never copied into the push payload.

## 6. Delivery semantics

1. A successful financial transaction is authoritative even if push delivery fails.
2. The outbox worker processes events independently.
3. Each event fans out to all active subscriptions that exist when the event is processed.
4. A successful device delivery updates subscription `last_success_at` and its delivery row.
5. A permanently invalid browser subscription is deactivated and that delivery becomes `expired`.
6. Transient failures retry with bounded exponential backoff.
7. Retry is capped; after the cap that device delivery becomes `failed`.
8. Once no retryable device delivery remains, the outbox event becomes `completed`.
9. If worker infrastructure itself repeatedly cannot process an event, the outbox event becomes `failed` and remains auditable.
10. Re-running the worker cannot create duplicate deliveries because both event and event-device pairs are unique.

Initial retry policy per device:
- attempt 1: immediate;
- attempt 2: +1 minute;
- attempt 3: +5 minutes;
- attempt 4: +30 minutes;
- attempt 5: +2 hours;
- then permanent `failed`.

An admin manual retry UI is out of scope for the first release.

## 7. Security model

- HTTPS only for onboarding and service-worker delivery.
- Raw QR tokens are high-entropy random values and are not customer IDs.
- Database stores only token hashes.
- Link tokens are scoped to one market and one customer.
- Link tokens expire after 15 minutes and are single-use.
- VAPID private key exists only in Supabase secret storage.
- Ordinary Flutter/web clients cannot read subscription key material, outbox internals, or VAPID credentials.
- RLS/privilege rules deny cross-market reads and writes.
- Public token-validation/subscription endpoints apply rate limiting and generic invalid-link responses so they cannot be used as a customer-enumeration oracle.
- Admin QR generation/status/revoke actions require an authenticated active admin/authorized staff actor belonging to the same market as the customer.
- Revoke-all immediately deactivates every subscription belonging to the selected customer and market.
- Financial push payloads contain no password, auth token, hidden internal note, or unnecessary PII.

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

Tapping a notification opens the ZHIROX Notifications PWA landing page for the already-linked device. The first release does not expose a detailed financial portal from the notification click, and no raw `customer_id` is placed in the URL.

## 9. iPhone/iPad behavior

Required behavior:
- QR opens the onboarding URL in Safari.
- If the page is not running as a Home Screen web app, show concise Add-to-Home-Screen instructions and preserve the still-valid association token in the installed app start URL.
- When opened from the Home Screen, the customer taps **چالاککردنی ئاگادارکردنەوە**.
- Only that explicit user action requests notification permission.
- On successful browser subscription, the backend consumes the one-time link token.

If the token expires before registration completes, the page shows a safe expired-link state and staff generate a fresh QR.

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
- replacement QR revokes prior unused token;
- token reuse rejection;
- expired token rejection;
- revoked token rejection;
- wrong-market access rejection;
- subscription key material inaccessible to ordinary users;
- multi-device registration;
- duplicate endpoint handling;
- revoke-all scoping;
- outbox event uniqueness;
- delivery uniqueness.

### Event tests

Cover:
- new live debt produces exactly one `debt_created` event;
- reconciliation creates a missing live-debt event exactly once;
- legacy import/sync/restore debt produces no push event;
- new payment produces exactly one `payment_created` event;
- debt edit produces no push event;
- payment edit/delete produces no new push event;
- push enqueue/delivery failure does not roll back a debt/payment transaction.

### Delivery worker tests

Cover:
- fan-out to multiple devices;
- zero-subscription event completes without later replay;
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
- successful subscription linking;
- notification click opens the PWA landing page without exposing a customer ID.

### CI verification

Before release:
- migration/security checks;
- backend/Edge Function tests;
- Flutter analyze;
- Flutter tests;
- existing online-only/payment-security checks;
- iOS unsigned IPA build remains green.

## 12. Expected implementation areas

Implementation is expected to touch focused areas only:
- new Supabase migration(s) for push link/subscription/outbox/delivery tables, indexes, RLS, and helper RPCs;
- a public `customer-push` Edge Function for onboarding/static PWA assets/token redemption/subscription registration;
- a privileged scheduled delivery Edge Function;
- an authenticated admin action for QR creation/status/revoke-all;
- the existing live debt creation flow for idempotent enqueue plus recent-live-debt reconciliation;
- the existing `record-payment` backend flow for idempotent payment enqueue;
- a small Flutter service/model layer for QR/status/revoke actions;
- customer profile UI for QR/status/revoke controls;
- regression/security tests and required CI policy updates.

Unrelated financial, dashboard, customer-list, receipt, import, synchronization, and restore behavior remains unchanged except where those subsystems are explicitly checked to suppress customer push events.

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
- a detailed customer financial portal opened from notification taps;
- KYC/business-provider onboarding.

## 14. Acceptance criteria

The feature is complete only when all of the following are true:

1. Staff can generate a 15-minute customer-specific QR from the customer profile.
2. Generating a replacement QR invalidates previous unused QR tokens for that customer.
3. QR does not expose a raw customer ID and cannot be reused after successful linking.
4. A customer can link at least one supported browser/device through onboarding.
5. A customer can link multiple devices using separate QR sessions.
6. iPhone/iPad onboarding correctly handles the Home Screen Web Push requirement.
7. A new live debt creates exactly one idempotent `debt_created` event, including reconciliation if the immediate enqueue was interrupted.
8. A new payment creates exactly one idempotent `payment_created` event.
9. Import/sync/restore and edit/delete flows create no customer push event.
10. All active devices receive an eligible event independently.
11. An event with no active device is completed and is not replayed to a device linked later.
12. Invalid subscriptions are retired automatically; transient failures retry without affecting financial transactions.
13. Staff can see linked-device count/latest delivery status and revoke all customer devices.
14. Cross-market access is blocked and server secrets remain server-side.
15. Regression, security, Flutter, backend, and CI/iOS build checks pass before release.
