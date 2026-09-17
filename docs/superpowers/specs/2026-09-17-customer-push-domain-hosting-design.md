# Customer Push Custom Domain Hosting Design

Date: 2026-09-17
Branch: `user-source`
Target domain: `https://push.zhirox.com`

## Goal

Move the customer QR/Web Push onboarding UI away from the Supabase Edge Function HTML response and host it on a normal HTTPS web origin so Safari and iOS render the page correctly and Web Push can register a same-origin service worker. Keep Supabase as the secure backend/API and keep the existing QR token, subscription, outbox, delivery, VAPID, and worker model unchanged.

## Root cause being addressed

The current `customer-push` Edge Function returns onboarding HTML with `text/html`, but the public Supabase Edge gateway currently exposes the response as `text/plain` with a restrictive sandbox CSP. Safari therefore displays the HTML source instead of rendering the onboarding page. Changing only the function header is not a reliable fix at that gateway boundary.

## Architecture

### Public web origin

Create a new Netlify site dedicated to the customer notification onboarding PWA. Its canonical production URL will be:

`https://push.zhirox.com`

The static site owns:

- `/` — Kurdish RTL onboarding page.
- `/manifest.webmanifest` — installable PWA manifest.
- `/sw.js` — same-origin service worker for Web Push.
- Static CSS/JS required for onboarding.

The site will not contain Supabase service-role credentials, VAPID private keys, worker secrets, or customer data at rest.

### Supabase backend

Supabase remains the authority for:

- validating short-lived QR tokens,
- returning the public VAPID key,
- redeeming a token into a browser push subscription,
- unsubscribing a device,
- staff status / QR generation,
- debt/payment event enqueue,
- worker delivery and retries,
- VAPID private key and worker secrets in Vault.

The public static page will call the existing `customer-push` Edge Function only as a JSON API over HTTPS.

## QR URL change

`customer-push-admin` will generate QR links with the new public base URL:

`https://push.zhirox.com/?token=<64-lowercase-hex-token>`

The token remains valid for 15 minutes. The raw token remains only in the QR/link and is not stored in plaintext in the database.

Any token visible in prior screenshots is considered exposed and should not be reused. A new QR link must be generated after the deployment.

## PWA and iOS behavior

On iPhone/iPad, the page will continue to instruct the customer to use Safari → Share → Add to Home Screen before requesting notification permission. Once opened from the Home Screen, `/sw.js` registers with scope `/`, the browser subscribes with the public VAPID key, and the resulting subscription is sent to Supabase.

The service worker will display only the existing minimized notification payload. Notification clicks will open the generic `https://push.zhirox.com/` page and will not expose `customer_id` in the URL.

## Backend changes

1. `supabase/functions/customer-push-admin/index.ts`
   - Change the public QR base URL from the Supabase function URL to `https://push.zhirox.com/`.

2. `supabase/functions/customer-push/index.ts`
   - Keep JSON API actions (`validate`, `subscribe`, `unsubscribe`) and CORS.
   - Remove dependence on Edge-hosted HTML/manifest/service-worker for the supported production flow.
   - Existing GET HTML handling may remain temporarily for backward compatibility, but new QR links must not point there.

3. `supabase/functions/customer-push-worker/index.ts`
   - Ensure notification click target is `https://push.zhirox.com/` rather than the old Supabase path.

## Netlify deployment

Create a new Netlify project, separate from unrelated existing sites, for this PWA. The preferred project name is `zhirox-push` (or the closest available Netlify-safe name).

Deploy the static assets from the repository. Then bind the custom domain `push.zhirox.com` and enable the normal Netlify-managed TLS certificate.

If the connected Netlify tooling cannot directly bind a custom domain, complete the site deployment first and use the exact Netlify DNS target required for a `push` CNAME. The final production state is not considered complete until `https://push.zhirox.com` resolves over HTTPS.

## Security

- No service-role key in frontend code.
- No VAPID private key in frontend code.
- Only the VAPID public key is returned by the public API.
- QR token remains 64 lowercase hex and 15-minute expiry.
- Existing rate limiting remains enforced server-side.
- CSP on the static site permits only its own scripts/assets plus HTTPS requests to the specific Supabase project API.
- `Referrer-Policy: no-referrer` and `Cache-Control: no-store` are preserved for onboarding.

## Error handling

- Expired/invalid QR: show a generic Kurdish unavailable/expired message.
- Permission denied: show the existing Kurdish retry guidance without exposing backend details.
- Unsupported browser: show a generic unsupported message.
- API/network failure: do not expose tokens or raw server errors.
- Subscription failure must not change financial data or transaction success.

## Verification

The change is complete only when all of the following are verified fresh:

1. `https://push.zhirox.com` returns rendered HTML, not source text.
2. Response has an HTML content type and HTTPS certificate is valid.
3. A newly generated QR points to `https://push.zhirox.com/?token=...`.
4. Invalid/expired token handling is generic.
5. `/manifest.webmanifest` loads successfully.
6. `/sw.js` loads as JavaScript and registers under `/`.
7. iPhone Add to Home Screen flow reaches notification permission.
8. A real device can create a push subscription and the staff card shows the active device count.
9. A test `debt_created` or `payment_created` event reaches the linked device without exposing unrelated PII.
10. Existing GitHub CI and Flutter tests stay green.

## Non-goals

- No SMS, Telegram, Viber, email, or third-party push provider.
- No marketing/broadcast notifications.
- No change to the financial transaction model.
- No change to the 15-minute QR lifetime or multi-device design.
