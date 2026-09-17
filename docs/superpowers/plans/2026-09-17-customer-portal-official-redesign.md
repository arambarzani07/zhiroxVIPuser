# Official Customer Portal Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the existing customer push page into a formal market-branded financial portal with Home, Transactions, and Notifications views while preserving permanent QR links and the current Web Push security model.

**Architecture:** Keep the current static PWA and Supabase `customer-push` JSON API. Split presentation into semantic HTML + a dedicated stylesheet, keep financial and push state transitions in `app.js`, and preserve the existing token/device-secret/service-worker contracts unchanged. Regression protection is added to the existing `scripts/verify_customer_push.py` policy verifier before production code changes.

**Tech Stack:** Static HTML5, CSS, vanilla JavaScript, Service Worker/Web Push, Netlify static hosting, Supabase Edge Functions, Python policy verifier.

**Spec:** `docs/superpowers/specs/2026-09-17-customer-portal-official-redesign.md`

## Global Constraints

- Kurdish-first (`lang="ku"`) and RTL (`dir="rtl"`).
- Permanent QR/link access remains valid until the manager revokes it.
- Preserve the existing `portal` and `subscribe` JSON API contract.
- Preserve token/device-secret local-storage keys and never render or log those values.
- Preserve same-origin service-worker notification click normalization.
- Do not add customer-side financial mutation.
- Do not add external fonts, analytics, UI frameworks, or tracking.
- Mobile controls must remain usable at narrow iPhone widths without horizontal overflow.
- Market name returned by the backend is the primary customer-facing brand.

---

### Task 1: Lock the official portal contract in the policy verifier

**Files:**
- Modify: `scripts/verify_customer_push.py`

**Interfaces:**
- Consumes: static assets under `customer-push-web/`.
- Produces: policy assertions that fail until the official portal shell and stylesheet exist.

- [ ] **Step 1: Add failing verifier assertions**

Add these checks after the existing `web = ROOT / 'customer-push-web'` block:

```python
for name in ('styles.css',):
    assert (web / name).exists(), f'missing official portal asset: {name}'

index_html = (web / 'index.html').read_text(errors='ignore')
for marker in (
    'id="portalShell"',
    'id="homeView"',
    'id="transactionsView"',
    'id="notificationsView"',
    'id="marketBrand"',
    'id="primaryRemaining"',
    'id="notificationState"',
    'data-portal-tab="home"',
    'data-portal-tab="transactions"',
    'data-portal-tab="notifications"',
):
    assert marker in index_html, f'official customer portal marker missing: {marker}'

assert '<style>' not in index_html, 'official customer portal CSS must live in styles.css'
assert 'aria-live="polite"' in index_html, 'portal needs a scoped polite status region'

styles_text = (web / 'styles.css').read_text(errors='ignore')
for marker in (
    '.portal-shell',
    '.balance-card',
    '.portal-nav',
    '@media (max-width: 420px)',
    'prefers-reduced-motion',
):
    assert marker in styles_text, f'official portal style missing: {marker}'

assert 'overflow-x: hidden' in styles_text, 'portal must guard narrow-screen horizontal overflow'
```

Extend the `app_js` checks with:

```python
for marker in (
    "setActiveView('home')",
    "setActiveView('transactions')",
    "setActiveView('notifications')",
    'renderNotificationState',
    'renderPrimaryBalance',
):
    assert marker in app_js, f'official portal behavior missing: {marker}'
```

- [ ] **Step 2: Run the verifier and confirm RED**

Run:

```bash
python3 scripts/verify_customer_push.py
```

Expected: FAIL on `missing official portal asset: styles.css` or the first new official-portal marker.

- [ ] **Step 3: Commit the RED verifier**

```bash
git add scripts/verify_customer_push.py
git commit -m "test(push): define official customer portal contract"
```

---

### Task 2: Build the formal financial portal shell and responsive visual system

**Files:**
- Modify: `customer-push-web/index.html`
- Create: `customer-push-web/styles.css`

**Interfaces:**
- Consumes: existing DOM values populated by `app.js` (`customerName`, `marketName`, `totals`, `ledger`, `enable`, `loadMore`).
- Produces: stable DOM IDs and tab buttons consumed by Task 3 JavaScript.

- [ ] **Step 1: Replace the setup-card HTML with the official portal shell**

`index.html` must keep the current manifest bootstrap and `/app.js`, add `/styles.css`, and define these structural elements:

```html
<body>
  <main id="portalShell" class="portal-shell">
    <header class="portal-header">
      <div class="brand-lockup">
        <div class="brand-mark" aria-hidden="true">Z</div>
        <div>
          <p class="eyebrow">پۆرتالی کڕیار</p>
          <h1 id="marketBrand">ZHIROX</h1>
          <p id="customerGreeting" class="muted"></p>
        </div>
      </div>
      <div id="accountBadge" class="status-badge">پشکنین...</div>
    </header>

    <p id="status" class="sr-status" aria-live="polite">پشکنینی لینک...</p>

    <section id="lockedState" class="state-card" hidden>
      <div class="state-icon" aria-hidden="true">!</div>
      <h2>دەستگەیشتن بەردەست نییە</h2>
      <p>ئەم لینکە بەردەست نییە یان ڕاگیراوە. تکایە QR ـێکی چالاک لە سوپەرمارکێتەکە وەربگرە.</p>
    </section>

    <div id="portalApp" hidden>
      <nav class="portal-nav" aria-label="بەشەکانی پۆرتال">
        <button type="button" class="nav-item is-active" data-portal-tab="home">سەرەکی</button>
        <button type="button" class="nav-item" data-portal-tab="transactions">مامەڵەکان</button>
        <button type="button" class="nav-item" data-portal-tab="notifications">ئاگادارکردنەوە</button>
      </nav>

      <section id="homeView" class="portal-view">
        <article class="balance-card">
          <p>قەرزی ماوە</p>
          <strong id="primaryRemaining">0 IQD</strong>
          <span id="primaryCurrency" class="balance-caption">IQD</span>
        </article>
        <div id="summaryMetrics" class="summary-grid"></div>
        <section class="panel">
          <div class="section-heading">
            <div><p class="eyebrow">دوایین چالاکی</p><h2>مامەڵە نوێیەکان</h2></div>
            <button id="openTransactions" class="text-action" type="button">هەمووی ببینە</button>
          </div>
          <div id="recentLedger" class="ledger compact-ledger"></div>
        </section>
      </section>

      <section id="transactionsView" class="portal-view" hidden>
        <div class="section-heading"><div><p class="eyebrow">کەشفی حیساب</p><h2>قەرز و پارەدانەکان</h2></div></div>
        <div id="ledger" class="ledger"></div>
        <button id="loadMore" class="secondary-action" type="button" hidden>بینینی زیاتر</button>
      </section>

      <section id="notificationsView" class="portal-view" hidden>
        <div class="section-heading"><div><p class="eyebrow">Web Push</p><h2>ئاگادارکردنەوەکان</h2></div></div>
        <article class="notification-card">
          <div id="notificationState" class="notification-state">پشکنین...</div>
          <p>ئاگادارکردنەوەکان بە ناوی سوپەرمارکێتەکەت دەنێردرێن.</p>
          <button id="enable" class="primary-action" type="button" hidden>چالاککردنی ئاگادارکردنەوە</button>
          <button id="showIosHelp" class="secondary-action" type="button" hidden>ڕێنمایی iPhone / iPad</button>
          <p id="result" aria-live="polite"></p>
        </article>
      </section>
    </div>

    <dialog id="iosHelpDialog" class="help-dialog">
      <form method="dialog">
        <button class="dialog-close" aria-label="داخستن">×</button>
        <h2>Add to Home Screen</h2>
        <ol>
          <li>پۆرتالەکە لە Safari بکەرەوە.</li>
          <li>Share بکە و Add to Home Screen هەڵبژێرە.</li>
          <li>لە Home Screen پۆرتالەکە بکەرەوە و ئاگادارکردنەوە چالاک بکە.</li>
        </ol>
      </form>
    </dialog>
  </main>
</body>
```

Keep `id="customerName"`, `id="marketName"`, and `id="identity"` as visually hidden compatibility nodes if Task 3 has not yet migrated all references; remove them only when JavaScript no longer requires them.

- [ ] **Step 2: Create the dedicated formal stylesheet**

Create `customer-push-web/styles.css` with:

```css
:root {
  color-scheme: light;
  font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  --bg: #f4f6fa;
  --surface: #ffffff;
  --text: #171b2e;
  --muted: #697086;
  --line: #e4e8f0;
  --brand: #2457d6;
  --brand-soft: #edf3ff;
  --danger: #b72f3d;
  --danger-soft: #fff1f2;
  --success: #087a55;
  --success-soft: #eaf8f2;
  --shadow: 0 16px 44px rgba(20, 31, 61, .08);
}

* { box-sizing: border-box; }
html { background: var(--bg); overflow-x: hidden; }
body {
  margin: 0;
  min-height: 100vh;
  overflow-x: hidden;
  background: var(--bg);
  color: var(--text);
  padding: max(16px, env(safe-area-inset-top)) 14px max(88px, env(safe-area-inset-bottom));
}
button { min-height: 44px; font: inherit; }
button:focus-visible { outline: 3px solid rgba(36, 87, 214, .28); outline-offset: 2px; }
[hidden] { display: none !important; }
.portal-shell { width: min(100%, 920px); margin: 0 auto; }
.portal-header { display: flex; align-items: center; justify-content: space-between; gap: 16px; margin-bottom: 18px; }
.brand-lockup { min-width: 0; display: flex; align-items: center; gap: 12px; }
.brand-mark { width: 48px; height: 48px; border-radius: 14px; display: grid; place-items: center; background: var(--brand); color: white; font-weight: 900; font-size: 24px; box-shadow: var(--shadow); }
.eyebrow { margin: 0 0 3px; color: var(--muted); font-size: 12px; font-weight: 800; letter-spacing: .02em; }
h1, h2, p { overflow-wrap: anywhere; }
h1 { margin: 0; font-size: clamp(22px, 5vw, 32px); }
h2 { margin: 0; font-size: 18px; }
.muted { margin: 4px 0 0; color: var(--muted); }
.status-badge { flex: 0 0 auto; padding: 8px 11px; border-radius: 999px; background: var(--brand-soft); color: var(--brand); font-size: 12px; font-weight: 800; }
.portal-nav { position: sticky; top: max(10px, env(safe-area-inset-top)); z-index: 5; display: grid; grid-template-columns: repeat(3, 1fr); gap: 6px; padding: 6px; margin-bottom: 16px; border: 1px solid var(--line); border-radius: 16px; background: rgba(255,255,255,.94); backdrop-filter: blur(16px); box-shadow: 0 8px 24px rgba(20,31,61,.05); }
.nav-item { border: 0; border-radius: 11px; background: transparent; color: var(--muted); font-weight: 800; cursor: pointer; }
.nav-item.is-active { background: var(--brand); color: white; }
.portal-view { display: grid; gap: 14px; }
.balance-card { padding: 24px; border-radius: 24px; background: var(--text); color: white; box-shadow: var(--shadow); }
.balance-card p { margin: 0 0 10px; opacity: .72; }
.balance-card strong { display: block; font-size: clamp(32px, 10vw, 48px); line-height: 1.05; }
.balance-caption { display: block; margin-top: 8px; opacity: .68; font-size: 12px; }
.summary-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px; }
.metric-card, .panel, .notification-card, .state-card { border: 1px solid var(--line); border-radius: 20px; background: var(--surface); box-shadow: 0 8px 26px rgba(20,31,61,.04); }
.metric-card { padding: 16px; }
.metric-card span { display: block; color: var(--muted); font-size: 12px; margin-bottom: 6px; }
.metric-card strong { font-size: 20px; }
.panel, .notification-card, .state-card { padding: 18px; }
.section-heading { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 12px; }
.text-action { border: 0; background: transparent; color: var(--brand); font-weight: 800; cursor: pointer; }
.ledger { display: grid; gap: 10px; }
.entry { padding: 14px; border: 1px solid var(--line); border-radius: 16px; background: var(--surface); }
.entry-head { display: flex; justify-content: space-between; align-items: center; gap: 12px; }
.entry-meta { margin-top: 7px; color: var(--muted); font-size: 13px; }
.debt-label { color: var(--danger); }
.payment-label { color: var(--success); }
.primary-action, .secondary-action { width: 100%; border-radius: 14px; padding: 12px 16px; font-weight: 800; cursor: pointer; }
.primary-action { border: 0; background: var(--brand); color: white; }
.secondary-action { border: 1px solid var(--line); background: white; color: var(--text); }
.notification-state { margin-bottom: 10px; padding: 12px; border-radius: 14px; background: var(--brand-soft); color: var(--brand); font-weight: 800; }
.state-card { text-align: center; padding-block: 32px; }
.state-icon { width: 52px; height: 52px; margin: 0 auto 12px; border-radius: 16px; display: grid; place-items: center; background: var(--danger-soft); color: var(--danger); font-weight: 900; }
.help-dialog { width: min(calc(100% - 28px), 480px); border: 0; border-radius: 22px; padding: 0; box-shadow: 0 24px 70px rgba(20,31,61,.22); }
.help-dialog::backdrop { background: rgba(15,20,35,.48); }
.help-dialog form { padding: 22px; }
.dialog-close { float: left; width: 44px; border: 0; border-radius: 12px; background: var(--bg); font-size: 24px; cursor: pointer; }
.sr-status { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); clip-path: inset(50%); white-space: nowrap; }

@media (max-width: 420px) {
  body { padding-inline: 10px; }
  .portal-header { align-items: flex-start; }
  .brand-mark { width: 44px; height: 44px; border-radius: 13px; }
  .status-badge { max-width: 105px; white-space: normal; text-align: center; }
  .portal-nav { position: fixed; inset-inline: 10px; bottom: max(8px, env(safe-area-inset-bottom)); top: auto; margin: 0; }
  .nav-item { font-size: 12px; padding-inline: 4px; }
  .balance-card { padding: 20px; }
  .summary-grid { grid-template-columns: 1fr 1fr; }
  .section-heading { align-items: flex-start; }
}

@media (min-width: 720px) {
  body { padding-inline: 24px; }
  .summary-grid { grid-template-columns: repeat(4, minmax(0, 1fr)); }
  .portal-view { gap: 18px; }
}

@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after { scroll-behavior: auto !important; transition: none !important; animation: none !important; }
}
```

- [ ] **Step 3: Run the verifier**

Run:

```bash
python3 scripts/verify_customer_push.py
```

Expected: still FAIL on Task 3 JavaScript markers, proving the visual shell exists but behavior is not yet wired.

- [ ] **Step 4: Commit the portal shell**

```bash
git add customer-push-web/index.html customer-push-web/styles.css
git commit -m "feat(push): build official customer portal shell"
```

---

### Task 3: Wire financial dashboard, tab navigation, and formal notification states

**Files:**
- Modify: `customer-push-web/app.js`

**Interfaces:**
- Consumes: existing `api(payload)`, `portalCredentials(offset)`, `loadPortal`, Web Push subscription contract, and the DOM IDs created in Task 2.
- Produces: `setActiveView(name)`, `renderPrimaryBalance(totals)`, `renderSummaryMetrics(totals)`, `renderNotificationState(state, message)`, recent-ledger rendering, and formal access-state behavior.

- [ ] **Step 1: Add tab navigation helpers**

Add element references:

```javascript
const portalAppEl = document.getElementById('portalApp');
const lockedStateEl = document.getElementById('lockedState');
const marketBrandEl = document.getElementById('marketBrand');
const customerGreetingEl = document.getElementById('customerGreeting');
const accountBadgeEl = document.getElementById('accountBadge');
const primaryRemainingEl = document.getElementById('primaryRemaining');
const primaryCurrencyEl = document.getElementById('primaryCurrency');
const summaryMetricsEl = document.getElementById('summaryMetrics');
const recentLedgerEl = document.getElementById('recentLedger');
const notificationStateEl = document.getElementById('notificationState');
const showIosHelpButton = document.getElementById('showIosHelp');
const iosHelpDialog = document.getElementById('iosHelpDialog');
const openTransactionsButton = document.getElementById('openTransactions');
const tabButtons = [...document.querySelectorAll('[data-portal-tab]')];
const views = {
  home: document.getElementById('homeView'),
  transactions: document.getElementById('transactionsView'),
  notifications: document.getElementById('notificationsView'),
};
```

Add:

```javascript
function setActiveView(name) {
  if (!Object.hasOwn(views, name)) return;
  for (const [viewName, element] of Object.entries(views)) {
    element.hidden = viewName !== name;
  }
  for (const button of tabButtons) {
    const active = button.dataset.portalTab === name;
    button.classList.toggle('is-active', active);
    button.setAttribute('aria-current', active ? 'page' : 'false');
  }
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

tabButtons.forEach((button) => {
  button.addEventListener('click', () => setActiveView(button.dataset.portalTab));
});
openTransactionsButton.addEventListener('click', () => setActiveView('transactions'));
```

- [ ] **Step 2: Add formal summary rendering**

Add:

```javascript
function renderPrimaryBalance(totals) {
  const first = Array.isArray(totals) && totals.length > 0 ? totals[0] : null;
  const currency = typeof first?.currency === 'string' ? first.currency : 'IQD';
  primaryRemainingEl.textContent = money(first?.remaining ?? 0, currency);
  primaryCurrencyEl.textContent = currency;
}

function metric(label, value, currency) {
  const card = document.createElement('article');
  card.className = 'metric-card';
  addText(card, 'span', label);
  addText(card, 'strong', money(value, currency));
  return card;
}

function renderSummaryMetrics(totals) {
  summaryMetricsEl.replaceChildren();
  const first = Array.isArray(totals) && totals.length > 0 ? totals[0] : null;
  const currency = typeof first?.currency === 'string' ? first.currency : 'IQD';
  summaryMetricsEl.append(
    metric('کۆی قەرز', first?.total_debt ?? 0, currency),
    metric('کۆی پارەدان', first?.paid ?? 0, currency),
  );
  if (Array.isArray(totals) && totals.length > 1) {
    for (const extra of totals.slice(1)) {
      const extraCurrency = typeof extra.currency === 'string' ? extra.currency : 'IQD';
      summaryMetricsEl.append(metric(`ماوە — ${extraCurrency}`, extra.remaining, extraCurrency));
    }
  }
}
```

- [ ] **Step 3: Reuse safe transaction rendering for recent activity**

Refactor the current renderer into:

```javascript
function buildLedgerEntry(item) {
  const isPayment = item.kind === 'payment';
  const entry = document.createElement('article');
  entry.className = 'entry';
  const head = document.createElement('div');
  head.className = 'entry-head';
  addText(head, 'strong', isPayment ? 'پارەدان' : 'قەرز', isPayment ? 'payment-label' : 'debt-label');
  addText(head, 'strong', money(item.amount, item.currency));
  entry.appendChild(head);
  const date = new Date(item.occurred_at);
  const dateText = Number.isNaN(date.getTime()) ? '' : date.toLocaleDateString('ku-IQ');
  const detail = [dateText, typeof item.note === 'string' ? item.note : ''].filter(Boolean).join(' — ');
  if (detail) addText(entry, 'div', detail, 'entry-meta');
  if (!isPayment) addText(entry, 'div', `ماوە: ${money(item.remaining, item.currency)}`, 'entry-meta');
  return entry;
}
```

Then make `renderRows(rows, append)` append `buildLedgerEntry(item)` and add:

```javascript
function renderRecentRows(rows) {
  recentLedgerEl.replaceChildren();
  const recent = Array.isArray(rows) ? rows.slice(0, 4) : [];
  if (recent.length === 0) {
    addText(recentLedgerEl, 'p', 'هێشتا هیچ مامەڵەیەک تۆمار نەکراوە.', 'empty');
    return;
  }
  for (const item of recent) recentLedgerEl.appendChild(buildLedgerEntry(item));
}
```

- [ ] **Step 4: Formalize identity, access, and notification status**

Add:

```javascript
function renderNotificationState(state, message) {
  notificationStateEl.dataset.state = state;
  notificationStateEl.textContent = message;
}

function showLockedPortal() {
  portalAppEl.hidden = true;
  lockedStateEl.hidden = false;
  accountBadgeEl.textContent = 'ڕاگیراو / نادروست';
  setStatus('ئەم لینکە بەردەست نییە یان ڕاگیراوە.', 'err');
}
```

Update `loadPortal()` after the API response:

```javascript
marketBrandEl.textContent = typeof data.market_name === 'string' && data.market_name.trim()
  ? data.market_name.trim()
  : 'ZHIROX';
customerGreetingEl.textContent = typeof data.customer_name === 'string' && data.customer_name.trim()
  ? `بەخێربێیت، ${data.customer_name.trim()}`
  : 'هەژماری کڕیار';
accountBadgeEl.textContent = 'هەژماری چالاک';
lockedStateEl.hidden = true;
portalAppEl.hidden = false;
renderPrimaryBalance(data.totals);
renderSummaryMetrics(data.totals);
renderRows(data.rows, append);
if (!append) renderRecentRows(data.rows);
```

Update `initialize()` so successful account loading always leaves the financial portal visible and sets one of these notification states:

```javascript
if (data.can_subscribe === true && isIos() && !isStandalone()) {
  showIosHelpButton.hidden = false;
  enableButton.hidden = true;
  renderNotificationState('install-required', 'بۆ iPhone سەرەتا پۆرتال زیاد بکە بۆ Home Screen');
  setStatus('هەژمارەکەت ئامادەیە.');
  return;
}

if (data.can_subscribe === true) {
  enableButton.hidden = false;
  showIosHelpButton.hidden = true;
  renderNotificationState('ready', 'ئاگادارکردنەوە هێشتا چالاک نەکراوە');
  setStatus('هەژمارەکەت ئامادەیە.');
} else {
  enableButton.hidden = true;
  showIosHelpButton.hidden = true;
  renderNotificationState('active', 'ئاگادارکردنەوە چالاکە');
  setStatus('هەژمارەکەت نوێکرایەوە.', 'ok');
}
setActiveView('home');
```

Use `showLockedPortal()` in the missing/invalid-link and initialization failure paths instead of exposing setup copy.

- [ ] **Step 5: Wire the iOS help dialog and push result states**

Add:

```javascript
showIosHelpButton.addEventListener('click', () => {
  if (typeof iosHelpDialog.showModal === 'function') iosHelpDialog.showModal();
});
```

After successful subscription, add:

```javascript
renderNotificationState('active', 'ئاگادارکردنەوە چالاک کرا');
enableButton.hidden = true;
showIosHelpButton.hidden = true;
```

In permission-denied/unsupported error handling, keep the portal visible and call `renderNotificationState('error', ...)` with the relevant Kurdish explanation.

- [ ] **Step 6: Run policy verification**

Run:

```bash
python3 scripts/verify_customer_push.py
```

Expected: PASS and print `customer push policy verified`.

- [ ] **Step 7: Commit behavior wiring**

```bash
git add customer-push-web/app.js
git commit -m "feat(push): wire official customer financial portal"
```

---

### Task 4: Align install metadata and static-host security with the customer portal

**Files:**
- Modify: `customer-push-web/manifest.webmanifest`
- Review/modify only if necessary: `customer-push-web/manifest-bootstrap.js`
- Review/modify only if necessary: `customer-push-web/_headers`
- Review only: `customer-push-web/sw.js`

**Interfaces:**
- Consumes: token-aware dynamic install manifest path from `manifest-bootstrap.js` and existing service-worker scope `/`.
- Produces: customer-portal PWA identity without changing security/authentication semantics.

- [ ] **Step 1: Rename the static manifest to the customer portal**

Replace `manifest.webmanifest` with:

```json
{
  "name": "ZHIROX Customer Portal",
  "short_name": "ZHIROX",
  "start_url": "/",
  "scope": "/",
  "display": "standalone",
  "theme_color": "#f4f6fa",
  "background_color": "#f4f6fa",
  "lang": "ku",
  "dir": "rtl"
}
```

- [ ] **Step 2: Verify token-aware manifest bootstrap is still intact**

Confirm `manifest-bootstrap.js` still contains all of:

```javascript
const validToken = /^[a-f0-9]{64}$/.test(token);
const manifestHref = validToken
  ? `/install-manifest.webmanifest?token=${encodeURIComponent(token)}`
  : '/manifest.webmanifest';
```

Do not alter it if those lines remain correct.

- [ ] **Step 3: Verify the service worker security invariants remain untouched**

Confirm `sw.js` still uses:

```javascript
candidate.origin === self.location.origin
self.clients.matchAll({ type: 'window', includeUncontrolled: true })
customerPortal.navigate(target)
self.clients.openWindow(target)
```

No production change is required if these invariants remain present.

- [ ] **Step 4: Verify static host headers already permit the stylesheet and API**

Run:

```bash
cat customer-push-web/_headers
```

Confirm the existing Content-Security-Policy allows same-origin styles/scripts and `connect-src` contains `https://hsoyfbtpvwfmjokudznx.supabase.co`. If CSS is already covered by `'self'`, do not weaken CSP.

- [ ] **Step 5: Run verifier and Edge Function tests**

Run:

```bash
python3 scripts/verify_customer_push.py
deno test --allow-env supabase/functions/customer-push/index_test.ts supabase/functions/customer-push-admin/index_test.ts supabase/functions/customer-push-worker/index_test.ts supabase/functions/customer-push-events/index_test.ts
```

Expected: policy verifier PASS; all Deno tests PASS.

- [ ] **Step 6: Commit manifest metadata if changed**

```bash
git add customer-push-web/manifest.webmanifest customer-push-web/manifest-bootstrap.js customer-push-web/_headers customer-push-web/sw.js
git commit -m "chore(push): align portal PWA identity"
```

Only include files that actually changed.

---

### Task 5: Final regression verification and production delivery

**Files:**
- No new source files expected.
- Verify workflow: `.github/workflows/ios-unsigned-ipa.yml`

**Interfaces:**
- Consumes: all changes from Tasks 1-4.
- Produces: verified branch state suitable for the existing Netlify customer portal and existing iOS CI pipeline.

- [ ] **Step 1: Run the complete push policy verifier**

```bash
python3 scripts/verify_customer_push.py
```

Expected: `customer push policy verified`.

- [ ] **Step 2: Run all customer-push Edge Function tests**

```bash
deno test --allow-env supabase/functions/customer-push/index_test.ts supabase/functions/customer-push-admin/index_test.ts supabase/functions/customer-push-worker/index_test.ts supabase/functions/customer-push-events/index_test.ts
```

Expected: zero failed tests.

- [ ] **Step 3: Run Flutter analyze/tests through the existing CI workflow**

Push the final commit to `user-source` and inspect the `iOS Unsigned IPA` workflow run for that exact head SHA. Require these steps to report `success` before calling the branch verified:

```text
Verify customer QR web push policy
Test customer push Edge Functions
Analyze strictly
Run tests
Build iOS without signing
```

- [ ] **Step 4: Verify static-host deployment**

Inspect the existing Netlify project `zhirox-push` after the final branch commit. Confirm the current deploy contains `/styles.css`, the new `portalShell` markup, and the updated manifest title `ZHIROX Customer Portal`.

- [ ] **Step 5: Smoke-test without financial mutation**

Use an invalid test token only to verify the locked-state UI:

```text
https://push.zhirox.com/?token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

Expected: formal `دەستگەیشتن بەردەست نییە` state; no sensitive identifiers displayed; no financial write occurs.

For a real valid QR, verify on a manager-controlled test customer/device:

```text
Valid QR -> market-branded Home -> balance summary -> Transactions tab -> Notifications tab -> existing push state
```

No debt/payment creation is required for this smoke test.

- [ ] **Step 6: Final commit only if verification-related source corrections were needed**

```bash
git status --short
```

Expected: clean working tree after all intended changes are committed.
