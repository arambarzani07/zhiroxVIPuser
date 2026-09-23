import { createClient } from 'npm:@supabase/supabase-js@2';

const OLD_BASE = 'https://api-daftar-qarz.kasbkar.net';
const API_PREFIX = '/api/v1/';
const LEGACY_USER_ID = 28;
const LEGACY_USER_ALIASES = new Set([
  'EU7q9piahzZ11LNJYu8AhlEUYGd2',
]);
const SOURCE_FINGERPRINT = 'daftar-live-account-28-v1';

function getSecretKey(): string {
  const newKeys = Deno.env.get('SUPABASE_SECRET_KEYS');
  if (newKeys) {
    try {
      const parsed = JSON.parse(newKeys);
      if (typeof parsed?.default === 'string' && parsed.default) {
        return parsed.default;
      }
    } catch (_) {}
  }
  return Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
}

function normalizePath(req: Request): { path: string; query: string } {
  const originalPath = req.headers.get('x-daftar-original-path')?.trim();
  const originalQuery = req.headers.get('x-daftar-original-query') ?? '';
  if (originalPath) {
    const path = originalPath.startsWith('/')
      ? originalPath
      : '/' + originalPath;
    return { path, query: originalQuery.replace(/^\?/, '') };
  }

  const url = new URL(req.url);
  const marker = '/daftar-credit-gateway';
  const idx = url.pathname.indexOf(marker);
  let path = idx >= 0 ? url.pathname.slice(idx + marker.length) : url.pathname;
  if (!path.startsWith('/')) path = '/' + path;
  return { path, query: url.search.replace(/^\?/, '') };
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

function sanitizeOutboundHeaders(req: Request): Headers {
  const headers = new Headers();
  const allowed = [
    'authorization',
    'content-type',
    'accept',
    'accept-language',
    'user-agent',
    'if-none-match',
    'if-modified-since',
  ];
  for (const name of allowed) {
    const value = req.headers.get(name);
    if (value) headers.set(name, value);
  }
  return headers;
}

async function parseTransactionBody(
  req: Request,
  bodyBytes: Uint8Array,
): Promise<Record<string, unknown>> {
  const contentType = (req.headers.get('content-type') ?? '').toLowerCase();
  const text = new TextDecoder().decode(bodyBytes);

  if (contentType.includes('application/json')) {
    try {
      const parsed = JSON.parse(text);
      return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
        ? parsed
        : {};
    } catch (_) {
      return {};
    }
  }

  if (contentType.includes('application/x-www-form-urlencoded')) {
    const out: Record<string, unknown> = {};
    const params = new URLSearchParams(text);
    for (const [k, v] of params.entries()) out[k] = v;
    return out;
  }

  if (contentType.includes('multipart/form-data')) {
    try {
      const clone = new Request(req.url, {
        method: req.method,
        headers: req.headers,
        body: toArrayBuffer(bodyBytes),
      });
      const form = await clone.formData();
      const out: Record<string, unknown> = {};
      for (const [k, v] of form.entries()) {
        if (typeof v === 'string') out[k] = v;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
      ? parsed
      : {};
  } catch (_) {
    return {};
  }
}

function firstValue(obj: Record<string, unknown>, keys: string[]): unknown {
  for (const key of keys) {
    if (
      obj[key] !== undefined && obj[key] !== null &&
      String(obj[key]).trim() !== ''
    ) return obj[key];
  }
  return undefined;
}

function toNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value !== 'string') return null;
  const n = Number(value.replace(/,/g, '').trim());
  return Number.isFinite(n) ? n : null;
}

function extractTransactions(payload: unknown): Record<string, unknown>[] {
  if (Array.isArray(payload)) {
    return payload.filter((x) => x && typeof x === 'object') as Record<
      string,
      unknown
    >[];
  }
  if (!payload || typeof payload !== 'object') return [];
  const obj = payload as Record<string, unknown>;
  for (const key of ['data', 'transactions', 'results', 'items']) {
    const value = obj[key];
    if (Array.isArray(value)) {
      return value.filter((x) => x && typeof x === 'object') as Record<
        string,
        unknown
      >[];
    }
    if (value && typeof value === 'object') {
      const nested = extractTransactions(value);
      if (nested.length) return nested;
    }
  }
  return [];
}

function computeBalance(
  rows: Record<string, unknown>[],
  contactId: string,
  currency: string,
): number {
  let balance = 0;
  for (const row of rows) {
    const rowContactId = String(
      firstValue(row, ['contact_id', 'contactId', 'contact']) ?? '',
    ).trim();
    if (rowContactId !== contactId) continue;
    const rowCurrency = String(firstValue(row, ['currency']) ?? 'IQD').trim()
      .toUpperCase();
    if (rowCurrency !== currency) continue;
    const rawType = firstValue(row, [
      'transaction_type',
      'type',
      'transactionType',
    ]);
    const type = String(rawType ?? '').trim().toUpperCase();
    const amount = Math.abs(
      toNumber(firstValue(row, ['amount', 'net_amount', 'value'])) ?? 0,
    );
    if (!amount) continue;
    if (type === 'LOAN' || type === 'DEBT') balance += amount;
    else if (type === 'PAYMENT' || type === 'PAID') balance -= amount;
  }
  return Math.max(0, Math.round(balance * 100) / 100);
}

async function sha256Hex(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(digest)).map((b) =>
    b.toString(16).padStart(2, '0')
  ).join('');
}

function jsonResponse(
  payload: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      ...extraHeaders,
    },
  });
}

Deno.serve(async (req: Request) => {
  const userAgent = req.headers.get('user-agent') ?? '';
  if (!/^Dart\/3\./i.test(userAgent)) {
    return jsonResponse({
      error: 'unsupported_client',
      message: 'This gateway is reserved for Daftar Qarz 0.2.7.',
    }, 403);
  }

  const normalized = normalizePath(req);
  const path = normalized.path;
  let query = normalized.query;

  if (!path.startsWith(API_PREFIX)) {
    return jsonResponse({
      error: 'invalid_path',
      message: 'Invalid Daftar API path.',
    }, 404);
  }

  const params = new URLSearchParams(query);
  let requestedUserId = params.get('user_id');
  if (requestedUserId && LEGACY_USER_ALIASES.has(requestedUserId)) {
    params.set('user_id', String(LEGACY_USER_ID));
    query = params.toString();
    requestedUserId = String(LEGACY_USER_ID);
  }
  if (requestedUserId && requestedUserId !== String(LEGACY_USER_ID)) {
    return jsonResponse({
      error: 'wrong_account',
      message: 'ئەم وەشانە تەنها بۆ هەژماری دیاریکراوی Daftar Qarz ڕێکخراوە.',
    }, 403);
  }

  const accountScopedGetPaths = new Set([
    '/api/v1/users',
    '/api/v1/users/',
    '/api/v1/contacts',
    '/api/v1/contacts/',
    '/api/v1/contacts/totals-by-currency',
    '/api/v1/transactions',
    '/api/v1/transactions/',
    '/api/v1/transactions/by-contact',
    '/api/v1/transactions/totals-by-currency',
    '/api/v1/search/contacts',
    '/api/v1/search/transactions',
  ]);
  if (
    req.method.toUpperCase() === 'GET' && accountScopedGetPaths.has(path) &&
    !params.has('user_id')
  ) {
    params.set('user_id', String(LEGACY_USER_ID));
    query = params.toString();
  }

  const targetUrl = OLD_BASE + path + (query ? '?' + query : '');
  const bodyBytes = ['GET', 'HEAD'].includes(req.method.toUpperCase())
    ? new Uint8Array()
    : new Uint8Array(await req.arrayBuffer());

  const isTransactionCreate = path === '/api/v1/transactions/' ||
    path === '/api/v1/transactions';
  const isTransactionItemWrite = /^\/api\/v1\/transactions\/\d+\/?$/.test(path);

  const outboundHeaders = sanitizeOutboundHeaders(req);

  if (
    isTransactionItemWrite &&
    ['PUT', 'PATCH'].includes(req.method.toUpperCase())
  ) {
    const editBody = await parseTransactionBody(req, bodyBytes);
    const financialKeys = [
      'amount',
      'net_amount',
      'value',
      'amount_iqd',
      'amount_usd',
      'currency',
      'transaction_type',
      'type',
      'transactionType',
      'contact_id',
      'contactId',
      'contact',
    ];
    if (financialKeys.some((key) => editBody[key] !== undefined)) {
      return jsonResponse({
        error: 'financial_transaction_edit_blocked',
        message:
          'دەستکاری بڕ/دراو/جۆری مامەلە لە Daftar بۆ پاراستنی سنووری قەرز ڕاگیرا؛ تەنها تێبینی دەستکاری بکە.',
      }, 422);
    }
  }

  if (isTransactionCreate && req.method.toUpperCase() === 'POST') {
    const body = await parseTransactionBody(req, bodyBytes);
    const txType = String(
      firstValue(body, ['transaction_type', 'type', 'transactionType']) ?? '',
    ).trim().toUpperCase();
    const userId = String(
      firstValue(body, ['user_id', 'userId', 'user_id_']) ?? LEGACY_USER_ID,
    ).trim();
    const contactId = String(
      firstValue(body, ['contact_id', 'contactId', 'contact']) ?? '',
    ).trim();
    let amount = toNumber(firstValue(body, ['amount', 'net_amount', 'value']));
    let currency = String(firstValue(body, ['currency']) ?? '').trim()
      .toUpperCase();

    // Recovered Daftar Qarz 0.2.7 writes can use amount_iqd / amount_usd
    // instead of the newer amount + currency shape.
    if (amount === null) {
      const amountIqd =
        toNumber(firstValue(body, ['amount_iqd', 'amountIQD'])) ?? 0;
      const amountUsd =
        toNumber(firstValue(body, ['amount_usd', 'amountUSD'])) ?? 0;
      if (amountIqd > 0 && amountUsd > 0) {
        return jsonResponse({
          error: 'ambiguous_transaction_amount',
          message: 'بڕی مامەلە بە دوو دراو دیاریکراوە؛ مامەلە تۆمار نەکرا.',
        }, 422);
      }
      if (amountIqd > 0) {
        amount = amountIqd;
        currency = 'IQD';
      } else if (amountUsd > 0) {
        amount = amountUsd;
        currency = 'USD';
      }
    }
    if (!currency && amount !== null) currency = 'IQD';

    if (userId !== String(LEGACY_USER_ID)) {
      return jsonResponse({
        error: 'wrong_account',
        message: 'ئەم وەشانە تەنها بۆ هەژماری دیاریکراوی Daftar Qarz ڕێکخراوە.',
      }, 403);
    }

    if (!['LOAN', 'DEBT', 'PAYMENT', 'PAID'].includes(txType)) {
      return jsonResponse({
        error: 'unknown_transaction_type',
        message: 'جۆری مامەلە ناسراو نییە؛ مامەلە تۆمار نەکرا.',
      }, 422);
    }

    if (txType === 'LOAN' || txType === 'DEBT') {
      const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
      const secretKey = getSecretKey();
      if (!supabaseUrl || !secretKey) {
        return jsonResponse({
          error: 'credit_limit_service_unavailable',
          message: 'پشکنینی سنووری قەرز بەردەست نییە. مامەلە تۆمار نەکرا.',
        }, 503);
      }

      const admin = createClient(supabaseUrl, secretKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });

      const logDecision = async (
        decision: 'allowed' | 'blocked' | 'error',
        fields: Record<string, unknown>,
      ) => {
        try {
          await admin.from('daftar_credit_limit_gateway_events').insert({
            source_fingerprint: SOURCE_FINGERPRINT,
            legacy_user_id: LEGACY_USER_ID,
            contact_source_id: contactId || null,
            transaction_type: txType || null,
            amount,
            currency: currency || null,
            decision,
            ...fields,
          });
        } catch (e) {
          console.warn('credit_limit_audit_failed', String(e));
        }
      };

      if (!contactId || amount === null || amount <= 0) {
        await logDecision('error', {
          http_status: 422,
          detail: 'missing_contact_or_amount',
        });
        return jsonResponse({
          error: 'credit_limit_check_invalid_request',
          message: 'زانیاری کڕیار یان بڕی قەرز تەواو نییە؛ مامەلە تۆمار نەکرا.',
        }, 422);
      }

      const { data: link, error: linkError } = await admin
        .from('legacy_import_links')
        .select('target_id')
        .eq('source_fingerprint', SOURCE_FINGERPRINT)
        .eq('entity_kind', 'customer')
        .eq('source_id', contactId)
        .maybeSingle();

      if (linkError || !link?.target_id) {
        await logDecision('error', {
          http_status: 409,
          detail: linkError
            ? 'customer_link_lookup_failed'
            : 'customer_link_missing',
        });
        return jsonResponse({
          error: 'customer_link_missing',
          message:
            'پەیوەندی کڕیار لەگەڵ ZHIROX نەدۆزرایەوە؛ بۆ پاراستنی سنووری قەرز مامەلە ڕاگیرا.',
        }, 409);
      }

      const targetCustomerId = String(link.target_id);
      const { data: profile, error: profileError } = await admin
        .from('profiles')
        .select('debt_limit')
        .eq('id', targetCustomerId)
        .maybeSingle();

      if (profileError || !profile) {
        await logDecision('error', {
          target_customer_id: targetCustomerId,
          http_status: 503,
          detail: 'customer_limit_lookup_failed',
        });
        return jsonResponse({
          error: 'credit_limit_lookup_failed',
          message: 'نەتوانرا سنووری قەرزی کڕیار بپشکنرێت؛ مامەلە تۆمار نەکرا.',
        }, 503);
      }

      const debtLimit = toNumber(profile.debt_limit) ?? 0;

      if (debtLimit > 0) {
        if (currency !== 'IQD') {
          await logDecision('error', {
            target_customer_id: targetCustomerId,
            debt_limit: debtLimit,
            http_status: 422,
            detail: 'credit_limit_currency_not_supported:' +
              (currency || 'unknown'),
          });
          return jsonResponse({
            error: 'credit_limit_currency_not_supported',
            message:
              'سنووری قەرز ئێستا بە IQD کار دەکات؛ قەرزی بە دراوی تر پێش تۆمارکردن ڕاگیرا.',
          }, 422);
        }

        // Use the already verified Daftar endpoint used by the production inbound sync,
        // then filter this customer's IQD rows locally. This avoids relying on an
        // unverified by-contact route and makes the pre-write balance authoritative.
        const balanceUrl = OLD_BASE + '/api/v1/transactions?user_id=' +
          encodeURIComponent(String(LEGACY_USER_ID));

        let currentBalance: number;
        try {
          const balanceResponse = await fetch(balanceUrl, {
            method: 'GET',
            headers: { Accept: 'application/json' },
            redirect: 'manual',
          });
          if (!balanceResponse.ok) {
            await logDecision('error', {
              target_customer_id: targetCustomerId,
              debt_limit: debtLimit,
              http_status: 503,
              detail: 'authoritative_balance_http_' + balanceResponse.status,
            });
            return jsonResponse({
              error: 'current_balance_unavailable',
              message:
                'نەتوانرا قەرزی ئێستای کڕیار لە Daftar پشتڕاست بکرێتەوە؛ مامەلە تۆمار نەکرا.',
            }, 503);
          }
          const payload = await balanceResponse.json();
          if (
            !payload || typeof payload !== 'object' ||
            (payload as Record<string, unknown>).success !== true
          ) {
            throw new Error('invalid_transactions_response');
          }
          const rows = extractTransactions(payload);
          currentBalance = computeBalance(rows, contactId, currency);
        } catch (e) {
          await logDecision('error', {
            target_customer_id: targetCustomerId,
            debt_limit: debtLimit,
            http_status: 503,
            detail: 'authoritative_balance_failed:' + String(e).slice(0, 180),
          });
          return jsonResponse({
            error: 'current_balance_unavailable',
            message: 'پشکنینی قەرزی ئێستا سەرکەوتوو نەبوو؛ مامەلە تۆمار نەکرا.',
          }, 503);
        }

        const projectedBalance = currentBalance + amount;
        if (projectedBalance > debtLimit) {
          const remainingCapacity = Math.max(0, debtLimit - currentBalance);
          await logDecision('blocked', {
            target_customer_id: targetCustomerId,
            debt_limit: debtLimit,
            current_balance: currentBalance,
            projected_balance: projectedBalance,
            http_status: 422,
            detail: 'credit_limit_exceeded',
          });
          return jsonResponse({
            error: 'credit_limit_exceeded',
            message: 'ئەم مامەڵەیە تۆمار نەکرا، چونکە لە سنووری قەرزی دیاری‌کراو زیاترە.',
            debt_limit: debtLimit,
            current_balance: currentBalance,
            requested_amount: amount,
            projected_balance: projectedBalance,
            remaining_capacity: remainingCapacity,
          }, 422);
        }

        await logDecision('allowed', {
          target_customer_id: targetCustomerId,
          debt_limit: debtLimit,
          current_balance: currentBalance,
          projected_balance: projectedBalance,
          http_status: 200,
          detail: 'within_credit_limit',
        });
      }
    }
  }

  try {
    const response = await fetch(targetUrl, {
      method: req.method,
      headers: outboundHeaders,
      body: ['GET', 'HEAD'].includes(req.method.toUpperCase())
        ? undefined
        : toArrayBuffer(bodyBytes),
      redirect: 'manual',
    });

    const headers = new Headers();
    for (
      const name of [
        'content-type',
        'etag',
        'cache-control',
        'last-modified',
        'content-disposition',
        'location',
      ]
    ) {
      const value = response.headers.get(name);
      if (value) headers.set(name, value);
    }
    headers.set('x-zhirox-daftar-gateway', 'v7');

    if (
      req.method.toUpperCase() === 'GET' &&
      (path === '/api/v1/users' || path === '/api/v1/users/')
    ) {
      try {
        const payload = await response.json();
        if (
          payload && typeof payload === 'object' &&
          Array.isArray((payload as Record<string, unknown>).data)
        ) {
          const data = ((payload as Record<string, unknown>).data as Record<
            string,
            unknown
          >[])
            .filter((row) =>
              String(row?.user_id ?? '') === String(LEGACY_USER_ID)
            );
          return jsonResponse(
            { ...(payload as Record<string, unknown>), data },
            response.status,
            {
              'x-zhirox-daftar-gateway': 'v7',
            },
          );
        }
        return jsonResponse(payload, response.status, {
          'x-zhirox-daftar-gateway': 'v7',
        });
      } catch (_) {
        return jsonResponse({ error: 'invalid_users_response' }, 502, {
          'x-zhirox-daftar-gateway': 'v7',
        });
      }
    }

    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers,
    });
  } catch (e) {
    console.error('daftar_proxy_failed', String(e));
    return jsonResponse({
      error: 'daftar_upstream_unavailable',
      message: 'پەیوەندی بە Daftar Qarz سەرکەوتوو نەبوو.',
    }, 502);
  }
});
