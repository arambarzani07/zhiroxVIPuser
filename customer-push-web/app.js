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
lockedStateEl.querySelector('.access-retry')?.addEventListener('click', () => window.location.reload());
const marketBrandEl = document.getElementById('marketBrand');
const customerGreetingEl = document.getElementById('customerGreeting');
const accountBadgeEl = document.getElementById('accountBadge');
const headerRefreshButton = document.getElementById('headerRefresh');
const primaryRemainingEl = document.getElementById('primaryRemaining');
const primaryCurrencyEl = document.getElementById('primaryCurrency');
const summaryMetricsEl = document.getElementById('summaryMetrics');
const dueInsightCardEl = document.getElementById('dueInsightCard');
const dueInsightTitleEl = document.getElementById('dueInsightTitle');
const dueInsightMetaEl = document.getElementById('dueInsightMeta');
const debtLimitCardEl = document.getElementById('debtLimitCard');
const debtLimitTitleEl = document.getElementById('debtLimitTitle');
const debtLimitMetaEl = document.getElementById('debtLimitMeta');
const debtLimitProgressEl = document.getElementById('debtLimitProgress');
const lastUpdatedLabelEl = document.getElementById('lastUpdatedLabel');
const quickTransactionsButton = document.getElementById('quickTransactions');
const quickNotificationsButton = document.getElementById('quickNotifications');
const quickPrintButton = document.getElementById('quickPrint');
const quickRefreshButton = document.getElementById('quickRefresh');
const recentLedgerEl = document.getElementById('recentLedger');
const ledgerEl = document.getElementById('ledger');
const loadMoreButton = document.getElementById('loadMore');
const notificationStateEl = document.getElementById('notificationState');
const notificationHistoryEl = document.getElementById('notificationHistory');
const notificationHistoryRefreshButton = document.getElementById('notificationHistoryRefresh');
const notificationUnreadBadgeEl = document.getElementById('notificationUnreadBadge');
const prefDueRemindersEl = document.getElementById('prefDueReminders');
const prefInstallmentRemindersEl = document.getElementById('prefInstallmentReminders');
const prefMonthlyStatementsEl = document.getElementById('prefMonthlyStatements');
const prefManualMessagesEl = document.getElementById('prefManualMessages');
const saveNotificationPreferencesButton = document.getElementById('saveNotificationPreferences');
const preferenceResultEl = document.getElementById('preferenceResult');
const showIosHelpButton = document.getElementById('showIosHelp');
const iosHelpDialog = document.getElementById('iosHelpDialog');
const receiptDialog = document.getElementById('receiptDialog');
const receiptMarketNameEl = document.getElementById('receiptMarketName');
const receiptNumberEl = document.getElementById('receiptNumber');
const receiptCustomerNameEl = document.getElementById('receiptCustomerName');
const receiptDateEl = document.getElementById('receiptDate');
const receiptTypeEl = document.getElementById('receiptType');
const receiptAmountLabelEl = document.getElementById('receiptAmountLabel');
const receiptAmountEl = document.getElementById('receiptAmount');
const receiptRemainingEl = document.getElementById('receiptRemaining');
const receiptDueRowEl = document.getElementById('receiptDueRow');
const receiptDueDateEl = document.getElementById('receiptDueDate');
const receiptNoteRowEl = document.getElementById('receiptNoteRow');
const receiptNoteEl = document.getElementById('receiptNote');
const receiptItemsSectionEl = document.getElementById('receiptItemsSection');
const receiptItemsEl = document.getElementById('receiptItems');
const receiptFooterEl = document.getElementById('receiptFooter');
const receiptPrintButton = document.getElementById('receiptPrint');
const openTransactionsButton = document.getElementById('openTransactions');
const transactionSearchEl = document.getElementById('transactionSearch');
const transactionFilterButtons = [...document.querySelectorAll('[data-transaction-filter]')];
const transactionResultCountEl = document.getElementById('transactionResultCount');
const clearTransactionSearchButton = document.getElementById('clearTransactionSearch');
const printStatementButton = document.getElementById('printStatement');
const homeTab = document.getElementById('homeTab');
const transactionsTab = document.getElementById('transactionsTab');
const receiptsTab = document.getElementById('receiptsTab');
const notificationsTab = document.getElementById('notificationsTab');
const accountTab = document.getElementById('accountTab');
const receiptHistoryEl = document.getElementById('receiptHistory');
const receiptsRefreshButton = document.getElementById('receiptsRefresh');
const receiptCountEl = document.getElementById('receiptCount');
const latestReceiptDateEl = document.getElementById('latestReceiptDate');
const accountCustomerNameEl = document.getElementById('accountCustomerName');
const accountCustomerPhoneEl = document.getElementById('accountCustomerPhone');
const accountMarketNameEl = document.getElementById('accountMarketName');
const accountMarketPhoneEl = document.getElementById('accountMarketPhone');
const accountMarketAddressEl = document.getElementById('accountMarketAddress');
const accountNotificationsButton = document.getElementById('accountNotifications');
const accountRefreshButton = document.getElementById('accountRefresh');
const tabButtons = [...document.querySelectorAll('[data-portal-tab]')];
const views = {
  home: document.getElementById('homeView'),
  transactions: document.getElementById('transactionsView'),
  receipts: document.getElementById('receiptsView'),
  notifications: document.getElementById('notificationsView'),
  account: document.getElementById('accountView'),
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
receiptsTab.addEventListener('click', () => {
  setActiveView('receipts');
  if (currentNotificationItems.length === 0) void loadNotificationHistory();
});
notificationsTab.addEventListener('click', () => {
  setActiveView('notifications');
  void loadNotificationHistory();
  void loadNotificationPreferences();
});
accountTab.addEventListener('click', () => setActiveView('account'));
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

function persistedPushCredentials() {
  const endpoint = localStorage.getItem(ENDPOINT_KEY) || '';
  const deviceSecret = localStorage.getItem(DEVICE_SECRET_KEY) || '';
  if (!endpoint.startsWith('https://') || !TOKEN_PATTERN.test(deviceSecret)) {
    return null;
  }
  return { endpoint, deviceSecret };
}

function scrubLinkCredentialsFromLocation() {
  const url = new URL(window.location.href);
  url.searchParams.delete('token');
  if (url.hash) {
    const fragment = new URLSearchParams(
      url.hash.startsWith('#') ? url.hash.slice(1) : url.hash,
    );
    fragment.delete('token');
    url.hash = fragment.toString() ? `#${fragment.toString()}` : '';
  }
  const suffix = `${url.search}${url.hash}`;
  window.history.replaceState(null, '', `${url.pathname}${suffix}`);
}

function resolveLinkToken() {
  const persisted = persistedPushCredentials();
  if (isStandalone() && persisted) {
    localStorage.removeItem(LINK_TOKEN_KEY);
    scrubLinkCredentialsFromLocation();
    return '';
  }

  const currentUrl = new URL(window.location.href);
  const queryToken = currentUrl.searchParams.get('token') || '';
  const fragmentToken = new URLSearchParams(
    currentUrl.hash.startsWith('#') ? currentUrl.hash.slice(1) : currentUrl.hash,
  ).get('token') || '';
  const linkToken = queryToken || fragmentToken;

  if (linkToken) {
    if (!TOKEN_PATTERN.test(linkToken)) {
      scrubLinkCredentialsFromLocation();
      return '';
    }
    localStorage.setItem(LINK_TOKEN_KEY, linkToken);
    scrubLinkCredentialsFromLocation();
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
let currentPortalData = null;
let currentNotificationItems = [];
let loadedRows = [];
let transactionFilter = 'all';
let transactionQuery = '';

function number(value) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function money(value, currency) {
  return `${new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 }).format(number(value))} ${currency || 'IQD'}`;
}

function portalCredentials(offset = 0, action = 'portal') {
  if (activeToken) {
    return action === 'portal'
      ? { action, token: activeToken, offset }
      : { action, token: activeToken };
  }
  const persisted = persistedPushCredentials();
  if (persisted) {
    return action === 'portal'
      ? { action, endpoint: persisted.endpoint, device_secret: persisted.deviceSecret, offset }
      : { action, endpoint: persisted.endpoint, device_secret: persisted.deviceSecret };
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

function renderPrimaryBalance(data) {
  if (data?.effective_remaining_iqd != null) {
    primaryRemainingEl.textContent = money(data.effective_remaining_iqd, 'IQD');
    primaryCurrencyEl.textContent = 'IQD';
    return;
  }
  const totals = data?.totals;
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

function renderSummaryMetrics(data) {
  const totals = data?.totals;
  summaryMetricsEl.replaceChildren();
  if (!Array.isArray(totals) || totals.length === 0) {
    summaryMetricsEl.append(
      metric('کۆی قەرز', 0, 'IQD'),
      metric('کۆی پارەدان', 0, 'IQD'),
    );
  } else {
    for (const item of totals) {
      const currency = typeof item.currency === 'string' ? item.currency : 'IQD';
      summaryMetricsEl.append(
        metric(`کۆی قەرز — ${currency}`, item.total_debt, currency),
        metric(`پارەدانەوەی مامەڵە — ${currency}`, item.paid, currency),
      );
      if (totals.length > 1) {
        summaryMetricsEl.append(metric(`قەرزی مامەڵەکان — ${currency}`, item.remaining, currency));
      }
    }
  }

  if (number(data?.general_paid_iqd) > 0) {
    summaryMetricsEl.append(
      metric('پارەدانەوەی گشتی', data.general_paid_iqd, 'IQD'),
      metric('کۆی گشتی ماوە', data.effective_remaining_iqd, 'IQD'),
    );
  }
}

function formatShortDate(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return date.toLocaleDateString('ku-IQ', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

function renderAccountInsights(data) {
  const due = data?.due_summary && typeof data.due_summary === 'object'
    ? data.due_summary
    : {};
  const overdueCount = number(due.overdue_count);
  const dueToday = number(due.due_today_count);
  const nextDue = due.next_due && typeof due.next_due === 'object'
    ? due.next_due
    : null;
  const oldestOverdue = due.oldest_overdue && typeof due.oldest_overdue === 'object'
    ? due.oldest_overdue
    : null;

  dueInsightCardEl?.classList.remove('is-danger', 'is-warning', 'is-ok');
  if (overdueCount > 0) {
    dueInsightCardEl?.classList.add('is-danger');
    dueInsightTitleEl.textContent = `${overdueCount} دانە دواکەوتوو`;
    const pieces = [];
    if (number(due.overdue_iqd) > 0) pieces.push(money(due.overdue_iqd, 'IQD'));
    if (number(due.overdue_usd) > 0) pieces.push(money(due.overdue_usd, 'USD'));
    if (oldestOverdue?.days_overdue != null) {
      pieces.push(`کۆنترین: ${number(oldestOverdue.days_overdue)} ڕۆژ`);
    }
    dueInsightMetaEl.textContent = pieces.join(' • ') || 'پێویستی بە پارەدانەوە هەیە';
  } else if (dueToday > 0) {
    dueInsightCardEl?.classList.add('is-warning');
    dueInsightTitleEl.textContent = 'دانەوەی ئەمڕۆ';
    dueInsightMetaEl.textContent = nextDue
      ? `${money(nextDue.amount, nextDue.currency)} • ${nextDue.kind === 'installment' ? 'قسط' : 'قەرز'}`
      : 'بەرواری دانەوە گەیشتووە';
  } else if (nextDue) {
    dueInsightCardEl?.classList.add('is-ok');
    const days = number(nextDue.days_until_due);
    const kind = nextDue.kind === 'installment'
      ? `قسط${nextDue.installment_no ? `ی ${nextDue.installment_no}` : ''}`
      : 'قەرز';
    dueInsightTitleEl.textContent = days === 1
      ? 'سبەی دانەوەیە'
      : `${days} ڕۆژ ماوە`;
    dueInsightMetaEl.textContent =
      `${kind} • ${money(nextDue.amount, nextDue.currency)} • ${formatShortDate(nextDue.due_date)}`;
  } else {
    dueInsightCardEl?.classList.add('is-ok');
    dueInsightTitleEl.textContent = 'هیچ دانەوەیەکی نزیک نییە';
    dueInsightMetaEl.textContent = 'هەژمارەکەت لە ڕووی بەرواری دانەوە ئارامە';
  }

  const limit = number(data?.debt_limit);
  const iqdTotal = Array.isArray(data?.totals)
    ? data.totals.find((item) => String(item?.currency || '').toUpperCase() !== 'USD')
    : null;
  if (limit > 0 && debtLimitCardEl) {
    const remaining = data?.effective_remaining_iqd != null
      ? number(data.effective_remaining_iqd)
      : number(iqdTotal?.remaining);
    const percent = Math.max(0, (remaining / limit) * 100);
    debtLimitCardEl.hidden = false;
    debtLimitCardEl.classList.toggle('is-danger', percent >= 100);
    debtLimitCardEl.classList.toggle('is-warning', percent >= 80 && percent < 100);
    debtLimitTitleEl.textContent = `${Math.round(percent)}٪ بەکارهاتوو`;
    debtLimitMetaEl.textContent = `${money(remaining, 'IQD')} لە ${money(limit, 'IQD')}`;
    debtLimitProgressEl.style.width = `${Math.min(percent, 100)}%`;
  } else if (debtLimitCardEl) {
    debtLimitCardEl.hidden = true;
  }

  if (lastUpdatedLabelEl) {
    const asOf = new Date(data?.as_of || Date.now());
    lastUpdatedLabelEl.textContent = Number.isNaN(asOf.getTime())
      ? 'نوێکراوە'
      : `نوێکراوە ${asOf.toLocaleTimeString('ku-IQ', {
          hour: '2-digit',
          minute: '2-digit',
        })}`;
  }
}

function isOverdueDebt(item) {
  if (item?.kind !== 'debt' || number(item?.remaining) <= 0 || !item?.due_date) {
    return false;
  }
  const due = new Date(`${item.due_date}T00:00:00`);
  if (Number.isNaN(due.getTime())) return false;
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return due < today;
}

function transactionSearchText(item) {
  const date = new Date(item?.occurred_at);
  const localizedDate = Number.isNaN(date.getTime())
    ? ''
    : date.toLocaleDateString('ku-IQ');
  return [
    item?.kind === 'payment'
      ? (item?.payment_scope === 'general' ? 'پارەدانەوەی گشتی' : 'پارەدانەوەی مامەڵە')
      : 'قەرز',
    item?.amount,
    item?.remaining,
    item?.currency,
    item?.note,
    item?.due_date,
    item?.status,
    localizedDate,
  ].filter((value) => value != null).join(' ').toLowerCase();
}

function filteredTransactionRows() {
  const query = transactionQuery.trim().toLowerCase();
  return loadedRows.filter((item) => {
    const filterMatch =
      transactionFilter === 'all' ||
      transactionFilter === item.kind ||
      (transactionFilter === 'overdue' && isOverdueDebt(item));
    if (!filterMatch) return false;
    if (!query) return true;
    return transactionSearchText(item).includes(query);
  });
}

function updateTransactionFilterUi() {
  for (const button of transactionFilterButtons) {
    button.classList.toggle(
      'is-active',
      button.dataset.transactionFilter === transactionFilter,
    );
  }
  if (clearTransactionSearchButton) {
    clearTransactionSearchButton.hidden =
      !transactionQuery && transactionFilter === 'all';
  }
}

function renderFilteredTransactions() {
  ledgerEl.replaceChildren();
  const rows = filteredTransactionRows();
  if (rows.length === 0) {
    addText(
      ledgerEl,
      'p',
      loadedRows.length === 0
        ? 'هێشتا هیچ مامەڵەیەک تۆمار نەکراوە.'
        : 'هیچ مامەڵەیەک لەم گەڕان/فلتەرەدا نەدۆزرایەوە.',
      'empty',
    );
  } else {
    for (const item of rows) ledgerEl.appendChild(buildLedgerEntry(item));
  }
  if (transactionResultCountEl) {
    transactionResultCountEl.textContent = `${rows.length} مامەڵە`;
  }
  updateTransactionFilterUi();
}

function mergeLoadedRows(rows, append) {
  const incoming = Array.isArray(rows) ? rows : [];
  if (!append) {
    loadedRows = incoming.slice();
    return;
  }
  const byKey = new Map(
    loadedRows.map((item) => [`${item.kind || ''}:${item.id || ''}`, item]),
  );
  for (const item of incoming) {
    byKey.set(`${item.kind || ''}:${item.id || ''}`, item);
  }
  loadedRows = [...byKey.values()];
}

function buildLedgerEntry(item) {
  const isPayment = item.kind === 'payment';
  const entry = document.createElement('article');
  entry.className = 'entry';
  if (item.id) entry.dataset.eventId = String(item.id);
  const head = document.createElement('div');
  head.className = 'entry-head';
  addText(
    head,
    'strong',
    isPayment
      ? (item.payment_scope === 'general' ? 'پارەدانەوەی گشتی' : 'پارەدانەوەی مامەڵە')
      : 'قەرز',
    isPayment ? 'payment-label' : 'debt-label',
  );
  addText(head, 'strong', money(item.amount, item.currency));
  entry.appendChild(head);

  const date = new Date(item.occurred_at);
  const dateText = Number.isNaN(date.getTime()) ? '' : date.toLocaleDateString('ku-IQ');
  const detail = [dateText, typeof item.note === 'string' ? item.note : ''].filter(Boolean).join(' — ');
  if (detail) addText(entry, 'div', detail, 'entry-meta');
  if (!isPayment) {
    addText(entry, 'div', `ماوە: ${money(item.remaining, item.currency)}`, 'entry-meta');
    if (item.due_date) {
      const overdue = isOverdueDebt(item);
      const dueLine = document.createElement('div');
      dueLine.className = overdue ? 'entry-due is-overdue' : 'entry-due';
      dueLine.textContent = overdue
        ? `دواکەوتوو • ${formatShortDate(item.due_date)}`
        : `دانەوە: ${formatShortDate(item.due_date)}`;
      entry.appendChild(dueLine);
    }
  }
  return entry;
}

function renderRows(rows, append = false) {
  mergeLoadedRows(rows, append);
  renderFilteredTransactions();
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

function notificationEventLabel(eventType) {
  switch (eventType) {
    case 'debt_created':
      return 'قەرز';
    case 'payment_created':
      return 'پارەدانەوە';
    case 'manual':
      return 'پەیامی بەڕێوەبەر';
    case 'due_reminder':
      return 'یادخستنەوەی قەرز';
    case 'installment_reminder':
      return 'یادخستنەوەی قسط';
    case 'debt_limit_changed':
      return 'گۆڕانی سنووری قەرز';
    case 'monthly_statement':
      return 'کەشفی حیسابی مانگانە';
    default:
      return 'ئاگادارکردنەوە';
  }
}

function notificationStatusLabel(status) {
  switch (status) {
    case 'sent':
      return 'نێردرا';
    case 'pending':
      return 'لە ڕیزدایە';
    case 'partial':
      return 'بەشێکی نێردرا';
    case 'failed':
      return 'شکست';
    case 'no_device':
      return 'ئامێری چالاک نەبوو';
    default:
      return '';
  }
}

function renderAccountDetails(data) {
  if (!data || typeof data !== 'object') return;
  if (accountCustomerNameEl) {
    accountCustomerNameEl.textContent =
      String(data.customer_name || '').trim() || 'کڕیار';
  }
  if (accountCustomerPhoneEl) {
    accountCustomerPhoneEl.textContent =
      String(data.customer_phone || '').trim() || 'ژمارەی مۆبایل تۆمار نەکراوە';
  }
  if (accountMarketNameEl) {
    accountMarketNameEl.textContent =
      String(data.market_name || '').trim() || 'ZHIROX';
  }
  if (accountMarketPhoneEl) {
    accountMarketPhoneEl.textContent =
      String(data.market_phone || '').trim() || '—';
  }
  if (accountMarketAddressEl) {
    accountMarketAddressEl.textContent =
      String(data.market_address || '').trim() || '—';
  }
}

function renderReceiptHistory(items) {
  if (!receiptHistoryEl) return;
  const receipts = (Array.isArray(items) ? items : [])
    .filter((item) => String(item?.receipt_id || '').trim());

  receiptHistoryEl.replaceChildren();
  if (receiptCountEl) receiptCountEl.textContent = String(receipts.length);
  if (latestReceiptDateEl) {
    latestReceiptDateEl.textContent = receipts.length > 0
      ? formatShortDate(receipts[0].created_at) || '—'
      : '—';
  }

  if (receipts.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'receipt-empty-state';
    addText(empty, 'strong', 'هێشتا پسووڵەیەک نییە');
    addText(
      empty,
      'span',
      'کاتێک قەرز یان پارەدانەوەیەک پسووڵەی هەبێت، لێرە پیشان دەدرێت.',
    );
    receiptHistoryEl.appendChild(empty);
    return;
  }

  for (const item of receipts) {
    const card = document.createElement('button');
    card.type = 'button';
    card.className = 'receipt-history-card';
    card.addEventListener('click', () => void openReceipt(item.receipt_id));

    const icon = document.createElement('span');
    icon.className = 'receipt-history-icon';
    icon.textContent = item.event_type === 'payment_created' ? '✓' : '▤';

    const copy = document.createElement('span');
    copy.className = 'receipt-history-copy';
    addText(
      copy,
      'strong',
      item.event_type === 'payment_created'
        ? 'پسووڵەی پارەدانەوە'
        : 'پسووڵەی قەرز',
    );
    addText(
      copy,
      'small',
      item.receipt_number
        ? `#${item.receipt_number} • ${formatShortDate(item.created_at)}`
        : formatShortDate(item.created_at) || 'پسووڵەی دیجیتاڵ',
    );

    const amount = document.createElement('span');
    amount.className = 'receipt-history-amount';
    amount.textContent = item.amount != null
      ? money(item.amount, item.currency)
      : 'کردنەوە';

    card.append(icon, copy, amount);
    receiptHistoryEl.appendChild(card);
  }
}

function notificationDeepLink(item) {
  const raw = typeof item.deep_link === 'string' ? item.deep_link.trim() : '';
  if (!raw) return null;
  try {
    const url = new URL(raw, window.location.origin);
    if (url.origin !== window.location.origin) return null;
    return url;
  } catch (_) {
    return null;
  }
}

function receiptItemLabel(item, index) {
  if (!item || typeof item !== 'object') return `بابەتی ${index + 1}`;
  return String(
    item.name ??
    item.title ??
    item.item_name ??
    item.product_name ??
    item.description ??
    `بابەتی ${index + 1}`
  ).trim();
}

function receiptItemMeta(item) {
  if (!item || typeof item !== 'object') return '';
  const parts = [];
  const quantity = item.quantity ?? item.qty;
  const price = item.price ?? item.unit_price;
  const total = item.total ?? item.total_price;
  if (quantity != null) parts.push(`ژمارە: ${quantity}`);
  if (price != null) parts.push(`نرخ: ${number(price).toLocaleString('en-US')}`);
  if (total != null) parts.push(`کۆ: ${number(total).toLocaleString('en-US')}`);
  return parts.join(' • ');
}

function renderReceipt(data) {
  const source = data?.source && typeof data.source === 'object'
    ? data.source
    : {};
  const settings = data?.settings && typeof data.settings === 'object'
    ? data.settings
    : {};
  const isPayment = source.kind === 'payment';
  const currency = String(source.currency || 'IQD').toUpperCase();
  const rawAmount = number(source.amount);
  const dollarRate = number(source.dollar_rate);
  const displayAmount = currency === 'USD' && dollarRate > 0
    ? rawAmount / dollarRate
    : rawAmount;
  const displayCurrency = currency === 'USD' && dollarRate > 0 ? 'USD' : 'IQD';

  receiptMarketNameEl.textContent =
    String(data.market_name || settings.receipt_title || 'ZHIROX');
  receiptNumberEl.textContent =
    data.receipt_number ? `#${data.receipt_number}` : '—';
  receiptCustomerNameEl.textContent = String(data.customer_name || '—');
  receiptDateEl.textContent = formatShortDate(source.occurred_at || data.created_at) || '—';
  receiptTypeEl.textContent = isPayment ? 'پارەدانەوە' : 'قەرز';
  receiptAmountLabelEl.textContent = isPayment ? 'بڕی پارەدانەوە' : 'بڕی قەرز';
  receiptAmountEl.textContent = money(displayAmount, displayCurrency);

  if (!isPayment && source.remaining != null) {
    const rawRemaining = number(source.remaining);
    const remaining = currency === 'USD' && dollarRate > 0
      ? rawRemaining / dollarRate
      : rawRemaining;
    receiptRemainingEl.textContent = `ماوە: ${money(remaining, displayCurrency)}`;
  } else {
    receiptRemainingEl.textContent = '';
  }

  const dueDate = String(source.due_date || '').trim();
  receiptDueRowEl.hidden = !dueDate;
  if (dueDate) receiptDueDateEl.textContent = formatShortDate(dueDate);

  const note = String(source.note || '').trim();
  receiptNoteRowEl.hidden = !note;
  if (note) receiptNoteEl.textContent = note;

  receiptItemsEl.replaceChildren();
  const items = Array.isArray(source.items) ? source.items : [];
  receiptItemsSectionEl.hidden = items.length === 0;
  items.forEach((item, index) => {
    const row = document.createElement('div');
    row.className = 'receipt-item';
    const copy = document.createElement('div');
    addText(copy, 'strong', receiptItemLabel(item, index));
    const meta = receiptItemMeta(item);
    if (meta) addText(copy, 'small', meta);
    row.appendChild(copy);
    receiptItemsEl.appendChild(row);
  });

  receiptFooterEl.textContent = String(settings.footer_note || '').trim();
}

async function openReceipt(receiptId) {
  const id = String(receiptId || '').trim();
  if (!id) return false;
  const credentials = portalCredentials(0, 'receipt');
  if (!credentials) return false;
  try {
    const data = await api({ ...credentials, receipt_id: id });
    renderReceipt(data);
    if (typeof receiptDialog?.showModal === 'function') {
      if (!receiptDialog.open) receiptDialog.showModal();
    }
    return true;
  } catch (_) {
    setResult('نەتوانرا پسووڵەکە بکرێتەوە.', 'err');
    return false;
  }
}

async function markNotification(item, acknowledge = false) {
  const id = String(item?.id || '').trim();
  if (!id) return false;
  const action = acknowledge ? 'acknowledge' : 'mark_read';
  const credentials = portalCredentials(0, action);
  if (!credentials) return false;
  try {
    await api({ ...credentials, notification_id: id });
    item.read_at = item.read_at || new Date().toISOString();
    if (acknowledge) item.acknowledged_at = item.acknowledged_at || new Date().toISOString();
    return true;
  } catch (_) {
    return false;
  }
}

async function followNotification(item) {
  await markNotification(item, false);
  const target = notificationDeepLink(item);
  if (!target) {
    setActiveView('notifications');
    await loadNotificationHistory();
    return;
  }

  const view = target.searchParams.get('view') || 'notifications';
  setActiveView(views[view] ? view : 'notifications');
  const eventId = target.searchParams.get('event') || '';
  const receiptId = target.searchParams.get('receipt') || '';
  if (eventId) await focusTransaction(eventId);
  if (receiptId) await openReceipt(receiptId);
  await loadNotificationHistory();
}

function renderNotificationHistory(items) {
  notificationHistoryEl.replaceChildren();
  if (!Array.isArray(items) || items.length === 0) {
    addText(
      notificationHistoryEl,
      'p',
      'هێشتا هیچ ئاگادارکردنەوەیەک تۆمار نەکراوە.',
      'empty',
    );
    return;
  }

  for (const item of items) {
    const card = document.createElement('article');
    card.className = 'notification-history-item';
    if (!item.read_at) card.classList.add('is-unread');
    card.tabIndex = 0;
    card.setAttribute('role', 'button');

    const head = document.createElement('div');
    head.className = 'notification-history-head';
    addText(head, 'strong', notificationEventLabel(item.event_type));

    const stateWrap = document.createElement('div');
    stateWrap.className = 'notification-history-state-wrap';
    if (!item.read_at) addText(stateWrap, 'span', 'نوێ', 'unread-badge');
    addText(
      stateWrap,
      'span',
      notificationStatusLabel(item.status),
      `notification-history-status status-${item.status || 'unknown'}`,
    );
    head.appendChild(stateWrap);
    card.appendChild(head);

    const detail = typeof item.message === 'string' && item.message.trim()
      ? item.message.trim()
      : item.amount != null
        ? money(item.amount, item.currency)
        : item.event_type === 'monthly_statement' && item.period
          ? `کەشفی حیسابی ${item.period}`
          : '';
    if (detail) addText(card, 'div', detail, 'notification-history-body');

    if (item.receipt_number) {
      addText(
        card,
        'div',
        `پسووڵە: ${item.receipt_number}`,
        'notification-receipt-number',
      );
    }

    const date = new Date(item.created_at);
    if (!Number.isNaN(date.getTime())) {
      addText(
        card,
        'div',
        date.toLocaleString('ku-IQ'),
        'notification-history-time',
      );
    }

    if (item.requires_ack === true) {
      const actions = document.createElement('div');
      actions.className = 'notification-history-actions';
      if (item.acknowledged_at) {
        addText(actions, 'span', '✓ بینرا / پەسەندکرا', 'receipt-acked');
      } else {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'receipt-ack';
        button.textContent = 'بینیم / پەسەندم کرد';
        button.addEventListener('click', async (event) => {
          event.stopPropagation();
          button.disabled = true;
          const ok = await markNotification(item, true);
          if (ok) {
            renderNotificationHistory(items);
          } else {
            button.disabled = false;
          }
        });
        actions.appendChild(button);
      }
      card.appendChild(actions);
    }

    const open = () => { void followNotification(item); };
    card.addEventListener('click', open);
    card.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        open();
      }
    });
    notificationHistoryEl.appendChild(card);
  }
}

async function loadNotificationPreferences() {
  const credentials = portalCredentials(0, 'preferences');
  if (!credentials || !prefDueRemindersEl) return;
  try {
    const data = await api(credentials);
    prefDueRemindersEl.checked = data.due_reminders !== false;
    prefInstallmentRemindersEl.checked = data.installment_reminders !== false;
    prefMonthlyStatementsEl.checked = data.monthly_statements !== false;
    prefManualMessagesEl.checked = data.manual_messages !== false;
  } catch (_) {
    if (preferenceResultEl) {
      preferenceResultEl.textContent = 'نەتوانرا هەڵبژاردەکانی ئاگادارکردنەوە باربکرێن.';
      preferenceResultEl.className = 'action-result err';
    }
  }
}

async function saveNotificationPreferences() {
  const credentials = portalCredentials(0, 'update_preferences');
  if (!credentials || !saveNotificationPreferencesButton) return;
  saveNotificationPreferencesButton.disabled = true;
  if (preferenceResultEl) preferenceResultEl.textContent = '';
  try {
    await api({
      ...credentials,
      due_reminders: prefDueRemindersEl.checked,
      installment_reminders: prefInstallmentRemindersEl.checked,
      monthly_statements: prefMonthlyStatementsEl.checked,
      manual_messages: prefManualMessagesEl.checked,
    });
    if (preferenceResultEl) {
      preferenceResultEl.textContent = 'هەڵبژاردەکان پاشەکەوت کران.';
      preferenceResultEl.className = 'action-result ok';
    }
  } catch (_) {
    if (preferenceResultEl) {
      preferenceResultEl.textContent = 'پاشەکەوتکردنی هەڵبژاردەکان سەرکەوتوو نەبوو.';
      preferenceResultEl.className = 'action-result err';
    }
  } finally {
    saveNotificationPreferencesButton.disabled = false;
  }
}

async function focusTransaction(eventId) {
  const id = String(eventId || '').trim();
  if (!id) return false;
  transactionFilter = 'all';
  transactionQuery = '';
  if (transactionSearchEl) transactionSearchEl.value = '';
  renderFilteredTransactions();
  setActiveView('transactions');

  for (let page = 0; page < 10; page += 1) {
    const target = ledgerEl.querySelector(`[data-event-id="${CSS.escape(id)}"]`);
    if (target) {
      target.classList.add('is-targeted');
      target.scrollIntoView({ behavior: 'smooth', block: 'center' });
      window.setTimeout(() => target.classList.remove('is-targeted'), 3500);
      return true;
    }
    if (loadMoreButton.hidden) break;
    await loadPortal(nextOffset, true);
  }
  return false;
}

async function loadNotificationHistory() {
  const credentials = portalCredentials(0, 'notifications');
  if (!credentials) return;

  notificationHistoryRefreshButton.disabled = true;
  try {
    const data = await api({ ...credentials, limit: 50 });
    currentNotificationItems = Array.isArray(data.items) ? data.items : [];
    renderNotificationHistory(currentNotificationItems);
    renderReceiptHistory(currentNotificationItems);
    const unread = Number(data.unread_count || 0);
    notificationsTab.dataset.unread = unread > 0 ? String(unread) : '';
    if (notificationUnreadBadgeEl) {
      notificationUnreadBadgeEl.hidden = unread <= 0;
      notificationUnreadBadgeEl.textContent = unread > 99 ? '99+' : String(unread);
    }
    if (unread > 0) {
      notificationsTab.setAttribute('aria-label', `ئاگادارکردنەوە — ${unread} نەخوێندراو`);
    } else {
      notificationsTab.removeAttribute('aria-label');
    }
  } catch (_) {
    notificationHistoryEl.replaceChildren();
    addText(
      notificationHistoryEl,
      'p',
      'نەتوانرا مێژووی ئاگادارکردنەوەکان باربکرێت.',
      'empty',
    );
  } finally {
    notificationHistoryRefreshButton.disabled = false;
  }
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
  currentPortalData = data;
  renderPrimaryBalance(data);
  renderSummaryMetrics(data);
  renderAccountInsights(data);
  renderAccountDetails(data);
  renderRows(data.rows, append);
  if (!append) renderRecentRows(data.rows);

  nextOffset = offset + (Array.isArray(data.rows) ? data.rows.length : 0);
  loadMoreButton.hidden = data.has_more !== true;
  return data;
}

async function refreshPortal() {
  const buttons = [headerRefreshButton, quickRefreshButton].filter(Boolean);
  for (const button of buttons) button.disabled = true;
  try {
    const data = await loadPortal(0, false);
    configureNotificationExperience(data);
    await Promise.all([
      loadNotificationHistory(),
      loadNotificationPreferences(),
    ]);
    setStatus('هەژمارەکەت نوێکرایەوە.', 'ok');
  } catch (_) {
    setStatus('نوێکردنەوە سەرکەوتوو نەبوو.', 'err');
  } finally {
    for (const button of buttons) button.disabled = false;
  }
}

async function ensureAllTransactionsLoaded() {
  let pages = 0;
  while (!loadMoreButton.hidden && pages < 100) {
    await loadPortal(nextOffset, true);
    pages += 1;
  }
}

async function printStatement() {
  const buttons = [quickPrintButton, printStatementButton].filter(Boolean);
  for (const button of buttons) button.disabled = true;
  try {
    await ensureAllTransactionsLoaded();
    transactionFilter = 'all';
    transactionQuery = '';
    if (transactionSearchEl) transactionSearchEl.value = '';
    renderFilteredTransactions();
    setActiveView('transactions');
    document.body.classList.add('printing-statement');
    window.setTimeout(() => window.print(), 80);
  } catch (_) {
    setResult('نەتوانرا کەشفی حیساب ئامادە بکرێت.', 'err');
  } finally {
    for (const button of buttons) button.disabled = false;
  }
}

function configureNotificationExperience(data) {
  enableButton.hidden = true;
  showIosHelpButton.hidden = true;
  setResult('');

  if (data.can_subscribe !== true) {
    renderNotificationState('active', 'ئاگادارکردنەوە چالاکە');
    return;
  }

  if (isIos() && !isStandalone()) {
    showIosHelpButton.hidden = false;
    renderNotificationState('install-required', 'بۆ iPhone سەرەتا پۆرتال زیاد بکە بۆ Home Screen');
    setResult('لە Safari: Share → Add to Home Screen، پاشان پۆرتالەکە لە Home Screen بکەرەوە و ئاگادارکردنەوە چالاک بکە.', 'err');
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
    configureNotificationExperience(data);
    await Promise.all([
      loadNotificationHistory(),
      loadNotificationPreferences(),
    ]);

    const deepLink = new URL(window.location.href);
    const requestedView = deepLink.searchParams.get('view');
    const notificationId = deepLink.searchParams.get('notification') || '';
    const eventId = deepLink.searchParams.get('event') || '';
    const receiptId = deepLink.searchParams.get('receipt') || '';

    setActiveView(views[requestedView] ? requestedView : (eventId ? 'transactions' : 'home'));
    if (notificationId) {
      const credentials = portalCredentials(0, 'mark_read');
      if (credentials) {
        void api({ ...credentials, notification_id: notificationId }).catch(() => {});
      }
    }
    if (eventId) await focusTransaction(eventId);
    if (receiptId) await openReceipt(receiptId);
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

if (receiptPrintButton) {
  receiptPrintButton.addEventListener('click', () => {
    document.body.classList.add('printing-receipt');
    window.setTimeout(() => window.print(), 80);
  });
}

if (receiptsRefreshButton) {
  receiptsRefreshButton.addEventListener('click', () => void loadNotificationHistory());
}
if (accountNotificationsButton) {
  accountNotificationsButton.addEventListener('click', () => {
    setActiveView('notifications');
    void loadNotificationPreferences();
    void loadNotificationHistory();
  });
}
if (accountRefreshButton) {
  accountRefreshButton.addEventListener('click', () => void refreshPortal());
}

if (headerRefreshButton) {
  headerRefreshButton.addEventListener('click', () => void refreshPortal());
}
if (quickRefreshButton) {
  quickRefreshButton.addEventListener('click', () => void refreshPortal());
}
if (quickTransactionsButton) {
  quickTransactionsButton.addEventListener('click', () => setActiveView('transactions'));
}
if (quickNotificationsButton) {
  quickNotificationsButton.addEventListener('click', () => {
    setActiveView('notifications');
    void loadNotificationHistory();
  });
}
if (quickPrintButton) {
  quickPrintButton.addEventListener('click', () => void printStatement());
}
if (printStatementButton) {
  printStatementButton.addEventListener('click', () => void printStatement());
}
if (transactionSearchEl) {
  transactionSearchEl.addEventListener('input', () => {
    transactionQuery = transactionSearchEl.value || '';
    renderFilteredTransactions();
  });
}
for (const button of transactionFilterButtons) {
  button.addEventListener('click', () => {
    transactionFilter = button.dataset.transactionFilter || 'all';
    renderFilteredTransactions();
  });
}
if (clearTransactionSearchButton) {
  clearTransactionSearchButton.addEventListener('click', () => {
    transactionFilter = 'all';
    transactionQuery = '';
    if (transactionSearchEl) transactionSearchEl.value = '';
    renderFilteredTransactions();
  });
}
window.addEventListener('afterprint', () => {
  document.body.classList.remove('printing-statement');
  document.body.classList.remove('printing-receipt');
});

notificationHistoryRefreshButton.addEventListener('click', () => {
  void loadNotificationHistory();
});
if (saveNotificationPreferencesButton) {
  saveNotificationPreferencesButton.addEventListener('click', () => {
    void saveNotificationPreferences();
  });
}

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
    scrubLinkCredentialsFromLocation();

    renderNotificationState('active', 'ئاگادارکردنەوە چالاک کرا');
    setStatus('پەیوەستکرا.', 'ok');
    setResult('ئاگادارکردنەوە بە سەرکەوتوویی چالاک کرا و بە ناوی سوپەرمارکێتەکەت دێت.', 'ok');
    enableButton.hidden = true;
    showIosHelpButton.hidden = true;
    await loadPortal();
    await Promise.all([
      loadNotificationHistory(),
      loadNotificationPreferences(),
    ]);
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
