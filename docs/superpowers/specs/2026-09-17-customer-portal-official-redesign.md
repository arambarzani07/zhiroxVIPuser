# Official Customer Portal Redesign

## Goal
Transform the existing ZHIROX customer push page into a formal, trustworthy financial customer portal while preserving the current QR, permanent-link, device-secret, Web Push, and Supabase API behavior.

## Product Direction
The approved direction is a **mobile-banking-style financial dashboard with a restrained VIP supermarket identity**. The portal must feel like an official account statement/notification portal rather than a setup page.

The portal remains Kurdish-first (`lang="ku"`, RTL), mobile-first, responsive, installable as a PWA, and usable from Safari/Chrome. It must also remain usable on desktop without a separate desktop application.

## Existing Capabilities That Must Be Preserved
- Permanent QR/link access remains valid until the manager revokes it.
- A connected device can reopen the portal using its endpoint + device secret after the onboarding token is consumed from active state.
- Customer and market identity continue to come from the backend API.
- Financial totals and paginated ledger continue to come from the existing `portal` API action.
- Web Push subscription keeps using the existing `subscribe` action and VAPID public key.
- iOS still requires Add to Home Screen before Web Push permission can be granted.
- Notification clicks open the same-origin protected customer portal.
- No raw customer ID is added to URLs or browser-visible storage.
- No backend financial mutation is added to the customer portal.

## Information Architecture
The single-page portal will expose three clear navigation destinations while remaining one protected PWA:

1. **Home / سەرەکی**
   - Official market header with market name as the primary brand.
   - Customer identity and account status.
   - Large primary balance card for remaining debt.
   - Secondary summary metrics for total debt and total paid.
   - Web Push status and a clear notification activation action when needed.
   - Recent financial activity preview.

2. **Transactions / مامەڵەکان**
   - Full debt/payment timeline.
   - Strong visual distinction between debt and payment entries.
   - Amount, date, note, and remaining balance where applicable.
   - Existing pagination through `loadMore` remains available.
   - Empty, loading, and failure states are formal and human-readable.

3. **Notifications / ئاگادارکردنەوە**
   - Current notification state: active, needs activation, unsupported, denied, or iOS install required.
   - Primary CTA to enable notifications when supported.
   - iPhone/iPad Add to Home Screen guidance in a dedicated modal/panel rather than permanent setup text.
   - Explain that notifications are sent in the supermarket's name.

Navigation may render as bottom navigation on mobile and as a compact segmented/tab navigation on larger widths, but it must not create multiple security contexts or expose credentials in navigation links.

## Visual System
- Formal financial look: white/surface cards, subtle borders, restrained shadows, generous spacing.
- Primary accent remains compatible with the current ZHIROX blue family; avoid decorative gradients that reduce readability.
- Remaining debt is the strongest visual number on the Home screen.
- Debt uses a restrained danger tone; payments use a restrained success tone.
- Typography must use system fonts for speed and platform consistency.
- Layout respects iOS safe areas.
- Minimum interactive target approximately 44px.
- No horizontally overflowing controls at narrow iPhone widths.
- No external font, icon, analytics, or UI framework dependency is required.

## Header and Branding
The portal header must prioritize the **actual supermarket/market name** returned by the API. `ZHIROX` may appear as the technology/platform mark in secondary text, but customer-facing branding should read as the customer's supermarket account.

Before API identity data is available, use neutral loading text and do not invent a market name.

## Home Balance Model
For each API totals entry, preserve currency separation. The Home view should choose the first available total as the primary summary for the large balance card while still showing additional currency groups if present.

Required labels:
- `قەرزی ماوە`
- `کۆی قەرز`
- `کۆی پارەدان`

If there are no totals, show a zero/empty-state account card rather than removing the dashboard structure.

## Transaction Timeline
Each row must use DOM text nodes / `textContent`; backend notes must never be inserted through unsanitized HTML.

Debt row:
- `قەرز`
- amount
- date
- optional note
- remaining amount

Payment row:
- `پارەدان`
- amount
- date
- optional note

The newest records remain first according to backend order. `loadMore` appends without replacing existing entries.

## Notification Experience
- If `can_subscribe=true` and the browser is eligible, show a clear `چالاککردنی ئاگادارکردنەوە` button.
- On iOS outside standalone mode, do not request permission. Show the Add to Home Screen instructions instead.
- On successful subscription, replace setup language with an active status and keep the financial portal visible.
- On denied/unsupported/error cases, show a recoverable explanatory state without hiding the financial account.
- Copy must state that notifications appear under the supermarket name.

## Link and Credential Safety
- The 64-character onboarding token pattern remains enforced.
- A token from the URL may be stored only using the existing local storage key required by the onboarding/install flow.
- Device secret and endpoint remain in the existing keys.
- No token or device secret is rendered in the DOM.
- No token/device secret is logged.
- Existing same-origin notification-click URL normalization remains intact.
- Missing/revoked access displays a dedicated locked/expired-access state with instructions to request a new QR from the supermarket.

## PWA and Install Metadata
- Keep standalone PWA behavior and token-aware install manifest flow.
- Static manifest title should describe the customer portal rather than only notifications.
- Dynamic/token-aware manifest behavior must not be broken.
- Service worker remains same-origin and preserves secure notification click navigation.

## Responsive Behavior
At widths below 420px:
- Summary metrics may stack or use a 2-column/1-column adaptive grid.
- Actions span available width.
- Long market/customer names wrap safely.
- Bottom navigation remains fully visible with safe-area padding.

At tablet/desktop widths:
- Portal is centered with a wider formal dashboard shell.
- Summary cards may render in columns.
- Navigation may appear as a horizontal tab bar.

## Accessibility
- Semantic headings and landmarks.
- `aria-live` only for transient/status messaging, not the entire application shell.
- Visible focus states.
- Buttons have text labels in addition to icons where meaning could be ambiguous.
- Status is not communicated by color alone.
- Respect `prefers-reduced-motion` for optional transitions.

## Error and Loading States
The portal requires dedicated states for:
- initial account loading
- invalid/revoked/missing link
- portal request failure
- no transactions
- load-more failure
- push unsupported
- notification permission denied
- iOS standalone requirement
- successful notification activation

Financial content already loaded must remain visible when a later push setup or pagination operation fails.

## Files in Scope
- `customer-push-web/index.html`
- `customer-push-web/styles.css` (new)
- `customer-push-web/app.js`
- `customer-push-web/manifest.webmanifest`
- `customer-push-web/manifest-bootstrap.js` only if required to preserve/install naming behavior
- `customer-push-web/sw.js` only for compatibility/status improvements; notification security behavior must not regress
- `customer-push-web/_headers` only if the new stylesheet requires policy/header changes
- `scripts/verify_customer_push.py` for static regression checks

## Out of Scope
- Changing debt/payment amounts or backend financial rules.
- Customer-side debt/payment creation.
- Replacing the existing Supabase project or Edge Function API contract.
- Login/password authentication for the portal.
- SMS/Viber fallback.
- External analytics/tracking.

## Acceptance Criteria
1. Opening a valid QR shows a formal market-branded financial portal, not a setup-style card.
2. The customer can see remaining debt, total debt, total payments, and transaction history.
3. Home, Transactions, and Notifications destinations are clearly available on mobile.
4. Push activation still works with the current backend contract.
5. iOS Add to Home Screen guidance remains correct and does not request notification permission prematurely.
6. Invalid/revoked links show a formal access-state screen and do not reveal sensitive identifiers.
7. No token or device secret is written into rendered text or logs.
8. The portal has no horizontal overflow at narrow iPhone widths.
9. Existing service-worker same-origin notification click handling remains verified.
10. Existing customer push verifier and Edge Function tests remain green after the redesign.
