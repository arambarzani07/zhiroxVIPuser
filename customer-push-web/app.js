'use strict';

const API_URL = 'https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/customer-push';
const LINK_TOKEN_KEY = 'zhirox_push_link_token';
const DEVICE_SECRET_KEY = 'zhirox_push_device_secret';
const ENDPOINT_KEY = 'zhirox_push_endpoint';
const TOKEN_PATTERN = /^[a-f0-9]{64}$/;

const statusEl = document.getElementById('status');
const enableButton = document.getElementById('enable');
const resultEl = document.getElementById('result');
const manifestEl = document.getElementById('appManifest');
const portalAppEl = document.getElementById('portalApp');
const lockedStateEl = document.getElementById('lockedState');
const marketBrandEl = document.getElementById('marketBrand');
const customerGreetingEl = document.getElementById('customerGreeting');
const accountBadgeEl = document.getElementById('accountBadge');
const primaryRemainingEl = document.getElementById('primaryRemaining');
const primaryCurrencyEl = document.getElementById('primaryCurrency');
const summaryMetricsEl = document.getElementById('summaryMetrics');
const recentLedgerEl = document.getElementById('recentLedger');
const ledgerEl = document.getElementById('ledger');
const loadMoreButton = document.getElementById('loadMore');
const notificationStateEl = document.getElementById('notificationState');
const showIosHelpButton = document.getElementById('showIosHelp');
const iosHelpDialog = document.getElementById('iosHelpDialog');
const openTransactionsButton = document.getElementById('openTransactions');
const homeTab = document.getElementById('homeTab');
const transactionsTab = document.getElementById('transactionsTab');
const notificationsTab = document.getElementById('notificationsTab');
const tabButtons = [...document.querySelectorAll('[data-portal-tab]')];
const views = {
  home: document.getElementById('homeView'),
  transactions: document.getElementById('transactionsView'),
  notifications: document.getElementById('notificationsView'),
};

function setStatus(message, kind = 'muted') {
  statusEl.textContent = message;
  statusEl.className = `sr-status ${kind}`;
}

function setResult(message, kind = '') {
  resultEl.textContent = message;
  resultEl.className = `action-result ${kind}`.trim();
}

function setActiveView(name) {
  if (!views[name]) return;
  for (const [viewName, element] of Object.entries(views)) {
    element.hidden = viewName !== name;
  }
  for (const button of tabButtons) {
    const active = button.dataset.portalTab === name;
    button.classList.toggle('is-active', active);
    if (active) {
      button.setAttribute('aria-current', 'page');
    } else {
      button.removeAttribute('aria-current');
    }
  }
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  window.scrollTo({ top: 0, behavior: reduceMotion ? 'auto' : 'smooth' });
}

homeTab.addEventListener('click', () => setActiveView('home'));
transactionsTab.addEventListener('click', () => setActiveView('transactions'));
notificationsTab.addEventListener('click', () => setActiveView('notifications'));
openTransactionsButton.addEventListener('click', () => setActiveView('transactions'));

function isIos() {
  const ua = navigator.userAgent || '';
  const classicIos = /iPad|iPhone|iPod/.test(ua);
  const modernIpad = navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1;
  return classicIos || modernIpad;
}

function isStandalone() {
  return window.navigator.standalone === true ||
    window.matchMedia('(display-mode: standalone)').matches;
}

function supportsPush() {
  return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
}

function decodeVapidKey(value) {
  const padding = '='.repeat((4 - (value.length % 4)) % 4);
  const normalized = (value + padding).replace(/-/g, '+').replace(/_/g, '/');
  const raw = atob(normalized);
  return Uint8Array.from([...raw].map((character) => character.charCodeAt(0)));
}

async function api(payload) {
  const response = await fetch(API_URL, {
    method: 'POST',
    mode: 'cors',
    credentials: 'omit',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });

  const body = await response.json().catch(() => null);
  if (!response.ok || !body || typeof body !== 'object') {
    throw new Error('request_failed');
  }
  return body;
}

function resolveLinkToken() {
  const currentUrl = new URL(window.location.href);
  const queryToken = currentUrl.searchParams.get('token') || '';
  const fragmentToken = new URLSearchParams(
    currentUrl.hash.startsWith('#') ? currentUrl.hash.slice(1) : currentUrl.hash,
  ).get('token') || '';
  const linkToken = queryToken || fragmentToken;

  if (linkToken) {
    if (!TOKEN_PATTERN.test(linkToken)) return '';
    localStorage.setItem(LINK_TOKEN_KEY, linkToken);
    if (manifestEl) {
      manifestEl.href = './manifest.webmanifest';
    }
    return linkToken;
  }

  const savedToken = localStorage.getItem(LINK_TOKEN_KEY) || '';
  return TOKEN_PATTERN.test(savedToken) ? savedToken : '';
}

let activeToken = '';
let vapidPublicKey = '';
let nextOffset = 0;

function number(value) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function money(value, currency) {
  return `${new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 }).format(number(value))} ${currency || 'IQD'}`;
}

function portalCredentials(offset = 0) {
  if (activeToken) return { action: 'portal', token: activeToken, offset };
  const endpoint = localStorage.getItem(ENDPOINT_KEY) || '';
  const deviceSecret = localStorage.getItem(DEVICE_SECRET_KEY) || '';
  if (endpoint.startsWith('https://') && TOKEN_PATTERN.test(deviceSecret)) {
    return { action: 'portal', endpoint, device_secret: deviceSecret, offset };
  }
  return null;
}

function addText(parent, tag, text, className = '') {
  const node = document.createElement(tag);
  node.textContent = text;
  if (className) node.className = className;
  parent.appendChild(node);
  return node;
}

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
  if (!Array.isArray(totals) || totals.length === 0) {
    summaryMetricsEl.append(
      metric('کۆی قەرز', 0, 'IQD'),
      metric('کۆی پارەدان', 0, 'IQD'),
    );
    return;
  }

  for (const item of totals) {
    const currency = typeof item.currency === 'string' ? item.currency : 'IQD';
    summaryMetricsEl.append(
      metric(`کۆی قەرز — ${currency}`, item.total_debt, currency),
      metric(`کۆی پارەدان — ${currency}`, item.paid, currency),
    );
    if (totals.length > 1) {
      summaryMetricsEl.append(metric(`قەرزی ماوە — ${currency}`, item.remaining, currency));
    }
  }
}

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

function renderRows(rows, append = false) {
  if (!append) ledgerEl.replaceChildren();
  if (!Array.isArray(rows) || rows.length === 0) {
    if (!append) addText(ledgerEl, 'p', 'هێشتا هیچ مامەڵەیەک تۆمار نەکراوە.', 'empty');
    return;
  }
  for (const item of rows) ledgerEl.appendChild(buildLedgerEntry(item));
}

function renderRecentRows(rows) {
  recentLedgerEl.replaceChildren();
  const recent = Array.isArray(rows) ? rows.slice(0, 4) : [];
  if (recent.length === 0) {
    addText(recentLedgerEl, 'p', 'هێشتا هیچ مامەڵەیەک تۆمار نەکراوە.', 'empty');
    return;
  }
  for (const item of recent) recentLedgerEl.appendChild(buildLedgerEntry(item));
}

function renderNotificationState(state, message) {
  notificationStateEl.dataset.state = state;
  notificationStateEl.textContent = message;
}

function showLockedPortal() {
  portalAppEl.hidden = true;
  lockedStateEl.hidden = false;
  accountBadgeEl.textContent = 'ڕاگیراو / نادروست';
  accountBadgeEl.classList.add('err');
  setStatus('ئەم لینکە بەردەست نییە یان ڕاگیراوە.', 'err');
}

async function loadPortal(offset = 0, append = false) {
  const credentials = portalCredentials(offset);
  if (!credentials) throw new Error('link_unavailable');
  const data = await api(credentials);

  const marketName = typeof data.market_name === 'string' ? data.market_name.trim() : '';
  const customerName = typeof data.customer_name === 'string' ? data.customer_name.trim() : '';
  marketBrandEl.textContent = marketName || 'ZHIROX';
  customerGreetingEl.textContent = customerName ? `بەخێربێیت، ${customerName}` : 'هەژماری کڕیار';
  accountBadgeEl.textContent = 'هەژماری چالاک';
  accountBadgeEl.classList.remove('err');
  vapidPublicKey = typeof data.vapid_public_key === 'string' ? data.vapid_public_key : '';

  lockedStateEl.hidden = true;
  portalAppEl.hidden = false;
  renderPrimaryBalance(data.totals);
  renderSummaryMetrics(data.totals);
  renderRows(data.rows, append);
  if (!append) renderRecentRows(data.rows);

  nextOffset = offset + (Array.isArray(data.rows) ? data.rows.length : 0);
  loadMoreButton.hidden = data.has_more !== true;
  return data;
}

function configureNotificationExperience(data) {
  enableButton.hidden = true;
  showIosHelpButton.hidden = true;
  setResult('');

  if (data.can_subscribe !== true) {
    renderNotificationState('active', 'ئاگادارکردنەوە چالاکە');
    return;
  }

  if (!supportsPush()) {
    renderNotificationState('error', 'ئەم وێبگەڕە پشتگیری Web Push ناکات');
    return;
  }

  if (Notification.permission === 'denied') {
    renderNotificationState('error', 'مۆڵەتی ئاگادارکردنەوە ڕەتکراوەتەوە');
    setResult('لە ڕێکخستنەکانی وێبگەڕ یان ئامێرەکەت مۆڵەتی ئاگادارکردنەوە چالاک بکە.', 'err');
    return;
  }

  if (isIos() && !isStandalone()) {
    showIosHelpButton.hidden = false;
    renderNotificationState('install-required', 'بۆ iPhone سەرەتا پۆرتال زیاد بکە بۆ Home Screen');
    return;
  }

  enableButton.hidden = false;
  renderNotificationState('ready', 'ئاگادارکردنەوە هێشتا چالاک نەکراوە');
}

async function initialize() {
  activeToken = resolveLinkToken();
  if (!activeToken && !portalCredentials()) {
    showLockedPortal();
    return;
  }

  try {
    const data = await loadPortal();
    setActiveView('home');
    configureNotificationExperience(data);
    setStatus('هەژمارەکەت ئامادەیە.', 'ok');
  } catch (_) {
    showLockedPortal();
  }
}

loadMoreButton.addEventListener('click', async () => {
  loadMoreButton.disabled = true;
  try {
    await loadPortal(nextOffset, true);
  } catch (_) {
    setResult('نەتوانرا مامەڵەی زیاتر بهێنرێت. دووبارە هەوڵ بدە.', 'err');
  } finally {
    loadMoreButton.disabled = false;
  }
});

showIosHelpButton.addEventListener('click', () => {
  if (typeof iosHelpDialog.showModal === 'function') {
    iosHelpDialog.showModal();
  } else {
    setResult('لە Safari: Share → Add to Home Screen، پاشان لە Home Screen پۆرتالەکە بکەرەوە.', 'err');
  }
});

enableButton.addEventListener('click', async () => {
  enableButton.disabled = true;
  setResult('');

  try {
    if (!activeToken || !TOKEN_PATTERN.test(activeToken)) throw new Error('link_unavailable');
    if (!supportsPush()) throw new Error('push_unsupported');
    if (isIos() && !isStandalone()) throw new Error('ios_not_standalone');

    const permission = await Notification.requestPermission();
    if (permission !== 'granted') throw new Error('permission_denied');

    const registration = await navigator.serviceWorker.register('./sw.js', { scope: './' });
    await navigator.serviceWorker.ready;

    let subscription = await registration.pushManager.getSubscription();
    if (!subscription) {
      subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: decodeVapidKey(vapidPublicKey),
      });
    }

    const data = await api({
      action: 'subscribe',
      token: activeToken,
      subscription: subscription.toJSON(),
      platform: isIos() ? 'ios' : (/Android/i.test(navigator.userAgent || '') ? 'android' : 'desktop'),
    });

    if (data.linked !== true || typeof data.device_secret !== 'string' || !data.device_secret) {
      throw new Error('request_failed');
    }

    localStorage.setItem(DEVICE_SECRET_KEY, data.device_secret);
    localStorage.setItem(ENDPOINT_KEY, subscription.endpoint);
    localStorage.removeItem(LINK_TOKEN_KEY);
    activeToken = '';
    if (window.location.search || window.location.hash) window.history.replaceState(null, '', window.location.pathname);

    renderNotificationState('active', 'ئاگادارکردنەوە چالاک کرا');
    setStatus('پەیوەستکرا.', 'ok');
    setResult('ئاگادارکردنەوە بە سەرکەوتوویی چالاک کرا و بە ناوی سوپەرمارکێتەکەت دێت.', 'ok');
    enableButton.hidden = true;
    showIosHelpButton.hidden = true;
    await loadPortal();
  } catch (error) {
    const reason = error instanceof Error ? error.message : 'request_failed';
    if (reason === 'permission_denied') {
      renderNotificationState('error', 'مۆڵەتی ئاگادارکردنەوە ڕەتکرایەوە');
      setResult('لە ڕێکخستنەکانی ئامێرەکەت مۆڵەت بدە و دووبارە هەوڵ بدە.', 'err');
    } else if (reason === 'ios_not_standalone') {
      showIosHelpButton.hidden = false;
      renderNotificationState('install-required', 'بۆ iPhone سەرەتا پۆرتال زیاد بکە بۆ Home Screen');
      setResult('لە Safari زیادیکە بۆ Home Screen و لەوێوە بیکەرەوە.', 'err');
    } else if (reason === 'push_unsupported') {
      renderNotificationState('error', 'ئەم وێبگەڕە پشتگیری Web Push ناکات');
      setResult('وێبگەڕێکی پشتگیریکراو بەکاربهێنە.', 'err');
    } else if (reason === 'link_unavailable') {
      renderNotificationState('error', 'لینکی پەیوەستکردن بەردەست نییە');
      setResult('QR ـی چالاکی هەمان هەژمار بەکاربهێنە.', 'err');
    } else {
      renderNotificationState('error', 'چالاککردن سەرکەوتوو نەبوو');
      setResult('دووبارە هەوڵ بدە. زانیاریی دارایییەکانت هەر بەردەستن.', 'err');
    }
    enableButton.disabled = false;
  }
});

initialize();
