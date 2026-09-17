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
    // Keep the token in the current URL until subscription succeeds so that
    // iOS Add to Home Screen can reopen the same one-time onboarding link.
    return queryToken;
  }

  const savedToken = localStorage.getItem(LINK_TOKEN_KEY) || '';
  return TOKEN_PATTERN.test(savedToken) ? savedToken : '';
}

let activeToken = '';
let vapidPublicKey = '';

async function initialize() {
  activeToken = resolveLinkToken();
  if (!activeToken) {
    setStatus('ئەم لینکە بەردەست نییە یان ماوەکەی تەواو بووە.', 'err');
    return;
  }

  try {
    const data = await api({ action: 'validate', token: activeToken });
    const customerName = typeof data.customer_name === 'string' ? data.customer_name : '';
    const marketName = typeof data.market_name === 'string' ? data.market_name : '';
    vapidPublicKey = typeof data.vapid_public_key === 'string' ? data.vapid_public_key : '';
    if (!vapidPublicKey) throw new Error('request_failed');

    customerNameEl.textContent = customerName;
    marketNameEl.textContent = marketName;
    identityEl.hidden = false;

    if (isIos() && !isStandalone()) {
      iosHelpEl.hidden = false;
      setStatus('سەرەتا ئەم پەڕەیە زیاد بکە بۆ Home Screen.');
      return;
    }

    enableButton.hidden = false;
    setStatus('لینکەکە دروستە. دەتوانیت ئاگادارکردنەوە چالاک بکەیت.');
  } catch (_) {
    localStorage.removeItem(LINK_TOKEN_KEY);
    setStatus('ئەم لینکە بەردەست نییە یان ماوەکەی تەواو بووە.', 'err');
  }
}

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
    localStorage.removeItem(LINK_TOKEN_KEY);
    activeToken = '';

    setStatus('پەیوەستکرا.', 'ok');
    setResult('ئاگادارکردنەوە بە سەرکەوتوویی چالاک کرا.', 'ok');
    enableButton.hidden = true;
  } catch (error) {
    const reason = error instanceof Error ? error.message : 'request_failed';
    if (reason === 'permission_denied') {
      setResult('مۆڵەتی ئاگادارکردنەوە نەدرا. لە ڕێکخستنەکانی ئامێرەکەت مۆڵەت بدە و دووبارە هەوڵ بدە.', 'err');
    } else if (reason === 'ios_not_standalone') {
      setResult('سەرەتا لە Safari زیادیکە بۆ Home Screen و لەوێوە بیکەرەوە.', 'err');
    } else if (reason === 'push_unsupported') {
      setResult('ئەم وێبگەڕە پشتگیری ئاگادارکردنەوە ناکات.', 'err');
    } else {
      setResult('چالاککردن سەرکەوتوو نەبوو؛ QR ـێکی نوێ دروست بکە و دووبارە هەوڵ بدە.', 'err');
    }
    enableButton.disabled = false;
  }
});

initialize();
