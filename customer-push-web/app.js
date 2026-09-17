'use strict';

const API_URL = 'https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/customer-push';
const LINK_TOKEN_KEY = 'zhirox_push_link_token';
const DEVICE_SECRET_KEY = 'zhirox_push_device_secret';
const ENDPOINT_KEY = 'zhirox_push_endpoint';
const TOKEN_PATTERN = /^[a-f0-9]{64}$/;

const statusEl = document.getElementById('status');
const identityEl = document.getElementById('identity');
const customerNameEl = document.getElementById('customerName');
const marketNameEl = document.getElementById('marketName');
const iosHelpEl = document.getElementById('iosHelp');
const enableButton = document.getElementById('enable');
const resultEl = document.getElementById('result');
const manifestEl = document.getElementById('appManifest');
const missingLinkHelpEl = document.getElementById('missingLinkHelp');
const portalEl = document.getElementById('portal');
const totalsEl = document.getElementById('totals');
const ledgerEl = document.getElementById('ledger');
const loadMoreButton = document.getElementById('loadMore');

function setStatus(message, kind = 'muted') {
  statusEl.textContent = message;
  statusEl.className = kind;
}

function setResult(message, kind = '') {
  resultEl.textContent = message;
  resultEl.className = kind;
}

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
  const queryToken = new URL(window.location.href).searchParams.get('token') || '';
  if (queryToken) {
    if (!TOKEN_PATTERN.test(queryToken)) return '';
    localStorage.setItem(LINK_TOKEN_KEY, queryToken);
    if (manifestEl) {
      manifestEl.href = `/install-manifest.webmanifest?token=${encodeURIComponent(queryToken)}`;
    }
    return queryToken;
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

function renderTotals(totals) {
  totalsEl.replaceChildren();
  if (!Array.isArray(totals) || totals.length === 0) {
    addText(totalsEl, 'p', 'هیچ قەرزێک تۆمار نەکراوە.', 'empty');
    return;
  }
  for (const item of totals) {
    const currency = typeof item.currency === 'string' ? item.currency : 'IQD';
    addText(totalsEl, 'div', currency, 'currency');
    const grid = document.createElement('div');
    grid.className = 'totals';
    for (const [label, value] of [
      ['کۆی قەرز', item.total_debt],
      ['پارەدراو', item.paid],
      ['ماوە', item.remaining],
    ]) {
      const card = document.createElement('div');
      card.className = 'total';
      addText(card, 'strong', money(value, currency));
      addText(card, 'span', label);
      grid.appendChild(card);
    }
    totalsEl.appendChild(grid);
  }
}

function renderRows(rows, append = false) {
  if (!append) ledgerEl.replaceChildren();
  if (!Array.isArray(rows) || rows.length === 0) {
    if (!append) addText(ledgerEl, 'p', 'هیچ مامەڵەیەک تۆمار نەکراوە.', 'empty');
    return;
  }
  for (const item of rows) {
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
    ledgerEl.appendChild(entry);
  }
}

async function loadPortal(offset = 0, append = false) {
  const credentials = portalCredentials(offset);
  if (!credentials) throw new Error('link_unavailable');
  const data = await api(credentials);
  customerNameEl.textContent = typeof data.customer_name === 'string' ? data.customer_name : '';
  marketNameEl.textContent = typeof data.market_name === 'string' ? data.market_name : '';
  vapidPublicKey = typeof data.vapid_public_key === 'string' ? data.vapid_public_key : '';
  identityEl.hidden = false;
  portalEl.hidden = false;
  renderTotals(data.totals);
  renderRows(data.rows, append);
  nextOffset = offset + (Array.isArray(data.rows) ? data.rows.length : 0);
  loadMoreButton.hidden = data.has_more !== true;
  return data;
}

async function initialize() {
  activeToken = resolveLinkToken();
  if (!activeToken && !portalCredentials()) {
    setStatus('ئەم لینکە بەردەست نییە یان ڕاگیراوە.', 'err');
    missingLinkHelpEl.hidden = false;
    return;
  }

  try {
    const data = await loadPortal();

    if (data.can_subscribe === true && isIos() && !isStandalone()) {
      iosHelpEl.hidden = false;
      setStatus('هەژمارەکەت ئامادەیە؛ بۆ ئاگادارکردنەوە زیادیکە بۆ Home Screen.');
      return;
    }

    if (data.can_subscribe === true) {
      enableButton.hidden = false;
      setStatus('قەرز و پارەدانەکانت لێرە دەبینیت؛ ئاگادارکردنەوەش چالاک بکە.');
    } else {
      setStatus('هەژماری کڕیار نوێکرایەوە.', 'ok');
    }
  } catch (_) {
    setStatus('ئەم لینکە بەردەست نییە یان ڕاگیراوە.', 'err');
    missingLinkHelpEl.hidden = false;
  }
}

loadMoreButton.addEventListener('click', async () => {
  loadMoreButton.disabled = true;
  try {
    await loadPortal(nextOffset, true);
  } catch (_) {
    setResult('نەتوانرا مامەڵەی زیاتر بهێنرێت.', 'err');
  } finally {
    loadMoreButton.disabled = false;
  }
});

enableButton.addEventListener('click', async () => {
  enableButton.disabled = true;
  setResult('');

  try {
    if (!activeToken || !TOKEN_PATTERN.test(activeToken)) throw new Error('link_unavailable');
    if (!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window)) {
      throw new Error('push_unsupported');
    }
    if (isIos() && !isStandalone()) throw new Error('ios_not_standalone');

    const permission = await Notification.requestPermission();
    if (permission !== 'granted') throw new Error('permission_denied');

    const registration = await navigator.serviceWorker.register('/sw.js', { scope: '/' });
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
    activeToken = '';

    setStatus('پەیوەستکرا.', 'ok');
    setResult('ئاگادارکردنەوە بە سەرکەوتوویی چالاک کرا.', 'ok');
    enableButton.hidden = true;
    await loadPortal();
  } catch (error) {
    const reason = error instanceof Error ? error.message : 'request_failed';
    if (reason === 'permission_denied') {
      setResult('مۆڵەتی ئاگادارکردنەوە نەدرا. لە ڕێکخستنەکانی ئامێرەکەت مۆڵەت بدە و دووبارە هەوڵ بدە.', 'err');
    } else if (reason === 'ios_not_standalone') {
      setResult('سەرەتا لە Safari زیادیکە بۆ Home Screen و لەوێوە بیکەرەوە.', 'err');
    } else if (reason === 'push_unsupported') {
      setResult('ئەم وێبگەڕە پشتگیری ئاگادارکردنەوە ناکات.', 'err');
    } else {
      setResult('چالاککردن سەرکەوتوو نەبوو؛ دووبارە هەوڵ بدە.', 'err');
    }
    enableButton.disabled = false;
  }
});

initialize();
