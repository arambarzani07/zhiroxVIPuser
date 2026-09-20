import { createClient } from 'npm:@supabase/supabase-js@2';

const OLD_BASE = 'https://api-daftar-qarz.kasbkar.net';
const API_PREFIX = '/api/v1/';
const LEGACY_USER_ID = 28;
const SOURCE_FINGERPRINT = 'daftar-live-account-28-v1';

function getSecretKey(): string {
  const newKeys = Deno.env.get('SUPABASE_SECRET_KEYS');
  if (newKeys) {
    try {
      const parsed = JSON.parse(newKeys);
      if (typeof parsed?.default === 'string' && parsed.default) return parsed.default;
    } catch (_) {}
  }
  return Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
}

function normalizePath(req: Request): { path: string; query: string } {
  const originalPath = req.headers.get('x-daftar-original-path')?.trim();
  const originalQuery = req.headers.get('x-daftar-original-query') ?? '';
  if (originalPath) {
    const path = originalPath.startsWith('/') ? originalPath : '/' + originalPath;
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
  const allowed = ['authorization', 'content-type', 'accept', 'accept-language', 'user-agent', 'if-none-match', 'if-modified-since'];
  for (const name of allowed) {
    const value = req.headers.get(name);
    if (value) headers.set(name, value);
  }
  return headers;
}

async function parseTransactionBody(req: Request, bodyBytes: Uint8Array): Promise<Record<string, unknown>> {
  const contentType = (req.headers.get('content-type') ?? '').toLowerCase();
  const text = new TextDecoder().decode(bodyBytes);

  if (contentType.includes('application/json')) {
    try {
      const parsed = JSON.parse(text);
      return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
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
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
  } catch (_) {
    return {};
  }
}

function firstValue(obj: Record<string, unknown>, keys: string[]): unknown {
  for (const key of keys) {
    if (obj[key] !== undefined && obj[key] !== null && String(obj[key]).trim() !== '') return obj[key];
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
  if (Array.isArray(payload)) return payload.filter((x) => x && typeof x === 'object') as Record<string, unknown>[];
  if (!payload || typeof payload !== 'object') return [];
  const obj = payload as Record<string, unknown>;
  for (const key of ['data', 'transactions', 'results', 'items']) {
    const value = obj[key];
    if (Array.isArray(value)) return value.filter((x) => x && typeof x === 'object') as Record<string, unknown>[];
    if (value && typeof value === 'object') {
      const nested = extractTransactions(value);
      if (nested.length) return nested;
    }
  }
  return [];
}

function computeBalance(rows: Record<string, unknown>[]): number {
  let balance = 0;
  for (const row of rows) {
    const rawType = firstValue(row, ['transaction_type', 'type', 'transactionType']);
    const type = String(rawType ?? '').trim().toUpperCase();
    const amount = Math.abs(toNumber(firstValue(row, ['amount', 'net_amount', 'value'])) ?? 0);
    if (!amount) continue;
    if (type === 'LOAN' || type === 'DEBT') balance += amount;
    else if (type === 'PAYMENT' || type === 'PAID') balance -= amount;
  }
  return balance;
}

function jsonResponse(payload: unknown, status = 200, extraHeaders: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...extraHeaders },
  });
}

Deno.serve(async (req: Request) => {
  const { path, query } = normalizePath(req);

  if (!path.startsWith(API_PREFIX)) {
    return jsonResponse({ error: 'invalid_path', message: 'Invalid Daftar API path.' }, 404);
  }

  const targetUrl = OLD_BASE + path + (query ? '?' + query : '');
  const bodyBytes = ['GET', 'HEAD'].includes(req.method.toUpperCase())
    ? new Uint8Array()
    : new Uint8Array(await req.arrayBuffer());

  const isTransactionWrite =
    path === '/api/v1/transactions/' || path === '/api/v1/transactions';

  const outboundHeaders = sanitizeOutboundHeaders(req);

  if (isTransactionWrite && ['POST', 'PUT', 'PATCH'].includes(req.method.toUpperCase())) {
    const body = await parseTransactionBody(req, bodyBytes);
    const txType = String(firstValue(body, ['transaction_type', 'type', 'transactionType']) ?? '').trim().toUpperCase();
    const userId = String(firstValue(body, ['user_id', 'userId', 'user_id_']) ?? LEGACY_USER_ID).trim();
    const contactId = String(firstValue(body, ['contact_id', 'contactId', 'contact']) ?? '').trim();
    const amount = toNumber(firstValue(body, ['amount', 'net_amount', 'value']));
    const currency = String(firstValue(body, ['currency']) ?? '').trim().toUpperCase();

    if (userId !== String(LEGACY_USER_ID)) {
      return jsonResponse({ error: 'wrong_account', message: 'ئەم وەشانە تەنها بۆ هەژماری دیاریکراوی Daftar Qarz ڕێکخراوە.' }, 403);
    }

    if (txType === 'LOAN' || txType === 'DEBT') {
      const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
      const secretKey = getSecretKey();
      if (!supabaseUrl || !secretKey) {
        return jsonResponse({ error: 'credit_limit_service_unavailable', message: 'پشکنینی سنووری قەرز بەردەست نییە. مامەلە تۆمار نەکرا.' }, 503);
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
        await logDecision('error', { http_status: 422, detail: 'missing_contact_or_amount' });
        return jsonResponse({ error: 'credit_limit_check_invalid_request', message: 'زانیاری کڕیار یان بڕی قەرز تەواو نییە؛ مامەلە تۆمار نەکرا.' }, 422);
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
          detail: linkError ? 'customer_link_lookup_failed' : 'customer_link_missing',
        });
        return jsonResponse({ error: 'customer_link_missing', message: 'پەیوەندی کڕیار لەگەڵ ZHIROX نەدۆزرایەوە؛ بۆ پاراستنی سنووری قەرز مامەلە ڕاگیرا.' }, 409);
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
        return jsonResponse({ error: 'credit_limit_lookup_failed', message: 'نەتوانرا سنووری قەرزی کڕیار بپشکنرێت؛ مامەلە تۆمار نەکرا.' }, 503);
      }

      const debtLimit = toNumber(profile.debt_limit) ?? 0;

      if (debtLimit > 0) {
        const balanceUrl = OLD_BASE + '/api/v1/transactions/by-contact?user_id=' +
          encodeURIComponent(String(LEGACY_USER_ID)) + '&contact_id=' + encodeURIComponent(contactId);

        let currentBalance: number;
        try {
          const balanceResponse = await fetch(balanceUrl, {
            method: 'GET',
            headers: outboundHeaders,
            redirect: 'manual',
          });
          if (!balanceResponse.ok) {
            await logDecision('error', {
              target_customer_id: targetCustomerId,
              debt_limit: debtLimit,
              http_status: 503,
              detail: 'authoritative_balance_http_' + balanceResponse.status,
            });
            return jsonResponse({ error: 'current_balance_unavailable', message: 'نەتوانرا قەرزی ئێستای کڕیار لە Daftar پشتڕاست بکرێتەوە؛ مامەلە تۆمار نەکرا.' }, 503);
          }
          const payload = await balanceResponse.json();
          const rows = extractTransactions(payload);
          currentBalance = computeBalance(rows);
        } catch (e) {
          await logDecision('error', {
            target_customer_id: targetCustomerId,
            debt_limit: debtLimit,
            http_status: 503,
            detail: 'authoritative_balance_failed:' + String(e).slice(0, 180),
          });
          return jsonResponse({ error: 'current_balance_unavailable', message: 'پشکنینی قەرزی ئێستا سەرکەوتوو نەبوو؛ مامەلە تۆمار نەکرا.' }, 503);
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
            message: 'سنووری قەرزی ئەم کڕیارە تێدەپەڕێت؛ مامەلە تۆمار نەکرا.',
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
      body: ['GET', 'HEAD'].includes(req.method.toUpperCase()) ? undefined : toArrayBuffer(bodyBytes),
      redirect: 'manual',
    });

    const headers = new Headers();
    for (const name of ['content-type', 'etag', 'cache-control', 'last-modified', 'content-disposition', 'location']) {
      const value = response.headers.get(name);
      if (value) headers.set(name, value);
    }
    headers.set('x-zhirox-daftar-gateway', 'v1');

    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers,
    });
  } catch (e) {
    console.error('daftar_proxy_failed', String(e));
    return jsonResponse({ error: 'daftar_upstream_unavailable', message: 'پەیوەندی بە Daftar Qarz سەرکەوتوو نەبوو.' }, 502);
  }
});
