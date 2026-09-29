import { createClient } from 'npm:@supabase/supabase-js@2';

const OLD_BASE = 'https://api-daftar-qarz.kasbkar.net';
const API_PREFIX = '/api/v1/';
const LEGACY_USER_ID = 28;
const LEGACY_USER_ALIASES = new Set(['EU7q9piahzZ11LNJYu8AhlEUYGd2']);
const SOURCE_FINGERPRINT = 'daftar-live-account-28-v1';

function serviceKey(): string {
  const packed = Deno.env.get('SUPABASE_SECRET_KEYS');
  if (packed) {
    try {
      const parsed = JSON.parse(packed);
      if (typeof parsed?.default === 'string' && parsed.default) return parsed.default;
    } catch (_) {}
  }
  return Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
}

function json(payload: unknown, status = 200, headers: HeadersInit = {}) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      ...headers,
    },
  });
}

function normalizePath(req: Request) {
  const url = new URL(req.url);
  const marker = '/daftar-credit-gateway';
  const idx = url.pathname.indexOf(marker);
  let path = idx >= 0 ? url.pathname.slice(idx + marker.length) : url.pathname;
  if (!path.startsWith('/')) path = '/' + path;
  return { path, query: url.search.replace(/^\?/, '') };
}

function outboundHeaders(req: Request) {
  const h = new Headers();
  for (const name of ['authorization','content-type','accept','accept-language','user-agent','if-none-match','if-modified-since']) {
    const v = req.headers.get(name);
    if (v) h.set(name, v);
  }
  return h;
}

async function authorizeLegacyMutation(req: Request): Promise<boolean> {
  const auth = (req.headers.get('authorization') ?? '').trim();
  if (!auth) return false;
  try {
    const headers = outboundHeaders(req);
    headers.set('accept', 'application/json');
    const response = await fetch(
      OLD_BASE + '/api/v1/users?user_id=' + LEGACY_USER_ID,
      {
        method: 'GET',
        headers,
        redirect: 'manual',
        signal: AbortSignal.timeout(10_000),
      },
    );
    if (!response.ok) return false;
    const payload = await response.json().catch(() => null);
    if (!payload || typeof payload !== 'object') return false;
    const record = payload as Record<string, unknown>;
    if (record.success === false) return false;
    const rows = extractRows(payload);
    if (rows.length > 0) {
      return rows.some((row) => {
        const id = String(firstValue(row, ['id', 'user_id', 'userId']) ?? '').trim();
        return id === String(LEGACY_USER_ID) || LEGACY_USER_ALIASES.has(id);
      });
    }
    return record.success === true && record.data != null;
  } catch (_) {
    return false;
  }
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

function normalizeDigits(value: string) {
  const map: Record<string,string> = {
    '٠':'0','١':'1','٢':'2','٣':'3','٤':'4','٥':'5','٦':'6','٧':'7','٨':'8','٩':'9',
    '۰':'0','۱':'1','۲':'2','۳':'3','۴':'4','۵':'5','۶':'6','۷':'7','۸':'8','۹':'9'
  };
  return value.replace(/[٠-٩۰-۹]/g, c => map[c] ?? c);
}

function toNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (value === undefined || value === null) return null;
  const s = normalizeDigits(String(value)).replace(/,/g, '').trim();
  if (!s) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

function firstValue(obj: Record<string, unknown>, keys: string[]) {
  for (const k of keys) {
    const v = obj[k];
    if (v !== undefined && v !== null && String(v).trim() !== '') return v;
  }
  return undefined;
}

async function parseBody(req: Request, bytes: Uint8Array): Promise<Record<string, unknown>> {
  const ct = (req.headers.get('content-type') ?? '').toLowerCase();
  const text = new TextDecoder().decode(bytes);
  if (ct.includes('application/json')) {
    try {
      const v = JSON.parse(text);
      return v && typeof v === 'object' && !Array.isArray(v) ? v : {};
    } catch (_) { return {}; }
  }
  if (ct.includes('application/x-www-form-urlencoded')) {
    const out: Record<string, unknown> = {};
    for (const [k,v] of new URLSearchParams(text).entries()) out[k] = v;
    return out;
  }
  if (ct.includes('multipart/form-data')) {
    try {
      const clone = new Request(req.url, {method:req.method, headers:req.headers, body:toArrayBuffer(bytes)});
      const fd = await clone.formData();
      const out: Record<string, unknown> = {};
      for (const [k,v] of fd.entries()) if (typeof v === 'string') out[k] = v;
      return out;
    } catch (_) { return {}; }
  }
  try {
    const v = JSON.parse(text);
    return v && typeof v === 'object' && !Array.isArray(v) ? v : {};
  } catch (_) { return {}; }
}

function extractRows(payload: unknown): Record<string, unknown>[] {
  if (Array.isArray(payload)) return payload.filter(x => x && typeof x === 'object') as Record<string,unknown>[];
  if (!payload || typeof payload !== 'object') return [];
  const obj = payload as Record<string, unknown>;
  for (const k of ['data','transactions','results','items']) {
    const v = obj[k];
    if (Array.isArray(v)) return v.filter(x => x && typeof x === 'object') as Record<string,unknown>[];
    if (v && typeof v === 'object') {
      const nested = extractRows(v);
      if (nested.length) return nested;
    }
  }
  return [];
}

async function originalTransactionContact(req: Request, transactionId: string): Promise<string | null> {
  try {
    const h = outboundHeaders(req);
    h.set('accept','application/json');
    const r = await fetch(OLD_BASE + '/api/v1/transactions?user_id=' + LEGACY_USER_ID,{headers:h,redirect:'manual'});
    if (!r.ok) return null;
    const payload = await r.json().catch(()=>null);
    for (const row of extractRows(payload)) {
      if (String(firstValue(row,['id','transaction_id','transactionId']) ?? '') === transactionId) {
        const cid = String(firstValue(row,['contact_id','contactId','contact']) ?? '').trim();
        return cid || null;
      }
    }
  } catch (_) {}
  return null;
}

function computeBalance(rows: Record<string, unknown>[], contactId: string, currency: string) {
  let balance = 0;
  for (const row of rows) {
    const cid = String(firstValue(row,['contact_id','contactId','contact']) ?? '').trim();
    if (cid !== contactId) continue;
    const cur = String(firstValue(row,['currency']) ?? 'IQD').trim().toUpperCase();
    if (cur !== currency) continue;
    const type = String(firstValue(row,['transaction_type','type','transactionType']) ?? '').trim().toUpperCase();
    const amount = Math.abs(toNumber(firstValue(row,['amount','net_amount','value'])) ?? 0);
    if (!amount) continue;
    if (type === 'LOAN' || type === 'DEBT') balance += amount;
    else if (type === 'PAYMENT' || type === 'PAID') balance -= amount;
  }
  return Math.max(0, Math.round(balance * 100) / 100);
}

type LimitPatch = { seen:boolean; iqd?:number|null; usd?:number|null; invalid?:boolean };

function parseLimitCommand(noteRaw: unknown): LimitPatch {
  const note = normalizeDigits(String(noteRaw ?? '')).trim();
  if (!note) return {seen:false};
  const marker = /(?:#?LIMIT|سنوور)/i.test(note);
  if (!marker) return {seen:false};

  const out: LimitPatch = {seen:true};
  const parse = (rx: RegExp): {found:boolean; value:number|null; invalid:boolean} => {
    const m = note.match(rx);
    if (!m) return {found:false,value:null,invalid:false};
    const raw = m[1].trim();
    if (/^(?:OFF|NONE|UNLIMITED|NULL|بێسنور|بێ\s*سنوور)$/i.test(raw)) {
      return {found:true,value:null,invalid:false};
    }
    const n = toNumber(raw);
    return {found:true,value:n,invalid:n === null || n < 0};
  };

  const iq = parse(/(?:IQD|دینار)\s*[:=]\s*([^\s,;]+)/i);
  const us = parse(/(?:USD|دۆلار)\s*[:=]\s*([^\s,;]+)/i);
  if (iq.found) out.iqd = iq.value;
  if (us.found) out.usd = us.value;
  if ((!iq.found && !us.found) || iq.invalid || us.invalid) out.invalid = true;
  return out;
}

Deno.serve(async (req: Request) => {
  const ua = req.headers.get('user-agent') ?? '';
  if (!/^Dart\/3\./i.test(ua)) {
    return json({error:'unsupported_client',message:'This gateway is reserved for Daftar Qarz 0.2.7.'},403);
  }

  const {path, query:rawQuery} = normalizePath(req);
  if (!path.startsWith(API_PREFIX)) return json({error:'invalid_path'},404);

  if (['POST','PUT','PATCH','DELETE'].includes(req.method)) {
    const authorized = await authorizeLegacyMutation(req);
    if (!authorized) {
      return json({error:'authentication_required'},401, {
        'x-daftar-credit-gateway':'v5-auth-required',
      });
    }
  }

  // Preserve Daftar's startup payload and only augment the server-driven Kurdish labels.
  if ((path === '/api/v1/init' || path === '/api/v1/init/') && req.method === 'GET') {
    try {
      const target = OLD_BASE + path + (rawQuery ? '?' + rawQuery : '');
      const response = await fetch(target,{
        method:'GET',
        headers:outboundHeaders(req),
        redirect:'manual'
      });
      const payload = await response.json().catch(()=>null);
      if (!payload || typeof payload !== 'object') return json({error:'invalid_init_response'},502);
      const data = (payload as Record<string,unknown>).data;
      if (data && typeof data === 'object') {
        const langs = (data as Record<string,unknown>).languges;
        if (Array.isArray(langs)) {
          for (const item of langs) {
            if (!item || typeof item !== 'object') continue;
            const lang = item as Record<string,unknown>;
            if (String(lang.lang_code ?? '') === 'ku') {
              lang.end_action_note = 'تێبینی / سنوور';
              lang.add_note_title = 'تێبینی بنووسە — بۆ سنووری قەرز: #LIMIT IQD=1000000 USD=500';
              lang.add_note_btn = 'پاشەکەوتکردن';
            }
          }
        }
      }
      return json(payload,response.status,{'x-daftar-credit-gateway':'v4-init-labels'});
    } catch (_) {
      return json({error:'daftar_init_upstream_unavailable'},502);
    }
  }

  const params = new URLSearchParams(rawQuery);
  let requestedUserId = params.get('user_id');
  if (requestedUserId && LEGACY_USER_ALIASES.has(requestedUserId)) {
    params.set('user_id', String(LEGACY_USER_ID));
    requestedUserId = String(LEGACY_USER_ID);
  }
  if (requestedUserId && requestedUserId !== String(LEGACY_USER_ID)) {
    return json({error:'wrong_account'},403);
  }

  const scopedGet = new Set([
    '/api/v1/users','/api/v1/users/','/api/v1/contacts','/api/v1/contacts/',
    '/api/v1/contacts/totals-by-currency','/api/v1/transactions','/api/v1/transactions/',
    '/api/v1/transactions/by-contact','/api/v1/transactions/totals-by-currency',
    '/api/v1/search/contacts','/api/v1/search/transactions'
  ]);
  if (req.method === 'GET' && scopedGet.has(path) && !params.has('user_id')) {
    params.set('user_id', String(LEGACY_USER_ID));
  }

  const query = params.toString();
  const target = OLD_BASE + path + (query ? '?' + query : '');
  const bytes = ['GET','HEAD'].includes(req.method) ? new Uint8Array() : new Uint8Array(await req.arrayBuffer());

  // Reuse Daftar's built-in note editor as a safe in-app credit-limit control.
  // Normal notes pass through unchanged; only notes beginning with #LIMIT / سنوور are intercepted.
  const txMatch = path.match(/^\/api\/v1\/transactions\/(\d+)\/?$/);
  if (txMatch && ['POST','PUT','PATCH'].includes(req.method)) {
    const body = await parseBody(req, bytes);
    const note = firstValue(body,['note','transaction_note','description']);
    const command = parseLimitCommand(note);
    if (command.seen) {
      if (command.invalid) {
        return json({
          error:'invalid_limit_format',
          message:'فۆرمات: #LIMIT IQD=1000000 USD=500 — بۆ بێ سنوور OFF بنووسە.'
        },422);
      }
      const contactId = await originalTransactionContact(req,txMatch[1]);
      if (!contactId) return json({error:'limit_contact_missing',message:'کڕیار بۆ ئەم مامەڵەیە نەدۆزرایەوە.'},404);

      const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
      const key = serviceKey();
      if (!supabaseUrl || !key) return json({error:'credit_limit_service_unavailable'},503);
      const admin = createClient(supabaseUrl,key,{auth:{persistSession:false,autoRefreshToken:false}});

      const {data:existing} = await admin.from('daftar_native_credit_limits')
        .select('limit_iqd,limit_usd')
        .eq('legacy_user_id',LEGACY_USER_ID)
        .eq('contact_source_id',contactId)
        .maybeSingle();

      const nextIqd = Object.prototype.hasOwnProperty.call(command,'iqd') ? command.iqd ?? null : existing?.limit_iqd ?? null;
      const nextUsd = Object.prototype.hasOwnProperty.call(command,'usd') ? command.usd ?? null : existing?.limit_usd ?? null;

      const {error} = await admin.from('daftar_native_credit_limits').upsert({
        legacy_user_id:LEGACY_USER_ID,
        contact_source_id:contactId,
        limit_iqd:nextIqd,
        limit_usd:nextUsd,
        updated_at:new Date().toISOString()
      },{onConflict:'legacy_user_id,contact_source_id'});
      if (error) return json({error:'limit_save_failed'},503);

      return json({
        success:true,
        data:{
          credit_limit_updated:true,
          transaction_id:txMatch[1],
          contact_id:contactId,
          limit_iqd:nextIqd,
          limit_usd:nextUsd
        },
        message:'سنووری قەرز پاشەکەوت کرا.'
      },200,{'x-daftar-credit-gateway':'v4-limit-note'});
    }
  }

  if ((path === '/api/v1/transactions' || path === '/api/v1/transactions/') && req.method === 'POST') {
    const body = await parseBody(req, bytes);
    const txType = String(firstValue(body,['transaction_type','type','transactionType']) ?? '').trim().toUpperCase();
    const rawUserId = String(firstValue(body,['user_id','userId','user_id_']) ?? LEGACY_USER_ID).trim();
    const userId = LEGACY_USER_ALIASES.has(rawUserId) ? String(LEGACY_USER_ID) : rawUserId;
    const contactId = String(firstValue(body,['contact_id','contactId','contact']) ?? '').trim();
    const note = firstValue(body,['note','transaction_note','description']);

    let amount = toNumber(firstValue(body,['amount','net_amount','value']));
    let currency = String(firstValue(body,['currency']) ?? '').trim().toUpperCase();

    if (amount === null) {
      const iqd = toNumber(firstValue(body,['amount_iqd','amountIQD'])) ?? 0;
      const usd = toNumber(firstValue(body,['amount_usd','amountUSD'])) ?? 0;
      if (iqd > 0 && usd > 0) return json({error:'ambiguous_transaction_amount'},422);
      if (iqd > 0) { amount = iqd; currency = 'IQD'; }
      else if (usd > 0) { amount = usd; currency = 'USD'; }
      else amount = 0;
    }
    if (!currency && amount > 0) currency = 'IQD';

    if (userId !== String(LEGACY_USER_ID)) return json({error:'wrong_account'},403);

    if (txType === 'LOAN' || txType === 'DEBT') {
      const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
      const key = serviceKey();
      if (!supabaseUrl || !key) return json({error:'credit_limit_service_unavailable'},503);
      const admin = createClient(supabaseUrl,key,{auth:{persistSession:false,autoRefreshToken:false}});

      const command = parseLimitCommand(note);
      if (command.seen) {
        if (!contactId) return json({error:'limit_contact_missing',message:'کڕیار دیاری نەکراوە.'},422);
        if (command.invalid) {
          return json({
            error:'invalid_limit_format',
            message:'فۆرمات: #LIMIT IQD=1000000 USD=500 — بۆ بێ سنوور OFF بنووسە.'
          },422);
        }

        const {data:existing} = await admin.from('daftar_native_credit_limits')
          .select('limit_iqd,limit_usd')
          .eq('legacy_user_id',LEGACY_USER_ID)
          .eq('contact_source_id',contactId)
          .maybeSingle();

        const nextIqd = Object.prototype.hasOwnProperty.call(command,'iqd') ? command.iqd ?? null : existing?.limit_iqd ?? null;
        const nextUsd = Object.prototype.hasOwnProperty.call(command,'usd') ? command.usd ?? null : existing?.limit_usd ?? null;

        const {error} = await admin.from('daftar_native_credit_limits').upsert({
          legacy_user_id:LEGACY_USER_ID,
          contact_source_id:contactId,
          limit_iqd:nextIqd,
          limit_usd:nextUsd,
          updated_at:new Date().toISOString()
        },{onConflict:'legacy_user_id,contact_source_id'});
        if (error) return json({error:'limit_save_failed'},503);

        // A #LIMIT transaction is a control command only. It is never forwarded
        // as real debt, even if the UI required a positive amount to submit.
        return json({
          success:true,
          data:{
            credit_limit_updated:true,
            contact_id:contactId,
            limit_iqd:nextIqd,
            limit_usd:nextUsd
          },
          message:'سنووری قەرز پاشەکەوت کرا.'
        },200,{'x-daftar-credit-gateway':'v3-limit-command'});
      }

      if (amount > 0) {
        if (!contactId || !['IQD','USD'].includes(currency)) return json({error:'invalid_loan'},422);

        const {data:limitRow,error:limitError} = await admin.from('daftar_native_credit_limits')
          .select('limit_iqd,limit_usd')
          .eq('legacy_user_id',LEGACY_USER_ID)
          .eq('contact_source_id',contactId)
          .maybeSingle();
        if (limitError) return json({error:'limit_lookup_failed'},503);

        const rawLimit = currency === 'IQD' ? limitRow?.limit_iqd : limitRow?.limit_usd;
        const limit = rawLimit === null || rawLimit === undefined ? null : Number(rawLimit);

        if (limit !== null && Number.isFinite(limit)) {
          const h = outboundHeaders(req);
          h.set('accept','application/json');
          const r = await fetch(OLD_BASE + '/api/v1/transactions?user_id=' + LEGACY_USER_ID,{headers:h,redirect:'manual'});
          if (!r.ok) return json({error:'current_balance_unavailable'},503);
          const payload = await r.json().catch(()=>null);
          if (!payload || typeof payload !== 'object' || (payload as Record<string,unknown>).success !== true) {
            return json({error:'current_balance_unavailable'},503);
          }
          const current = computeBalance(extractRows(payload),contactId,currency);
          const projected = current + amount;
          if (projected > limit) {
            try {
              await admin.from('daftar_credit_limit_gateway_events').insert({
                source_fingerprint:SOURCE_FINGERPRINT,
                legacy_user_id:LEGACY_USER_ID,
                contact_source_id:contactId,
                transaction_type:txType,
                amount,
                currency,
                debt_limit:limit,
                current_balance:current,
                projected_balance:projected,
                decision:'blocked',
                http_status:422,
                detail:'credit_limit_exceeded'
              });
            } catch (_) {}
            return json({
              error:'credit_limit_exceeded',
              message:'ئەم مامەڵەیە تۆمار نەکرا، چونکە لە سنووری قەرزی دیاریکراو زیاترە.',
              debt_limit:limit,
              current_balance:current,
              requested_amount:amount,
              projected_balance:projected,
              remaining_capacity:Math.max(0,limit-current)
            },422);
          }
        }
      }
    }
  }

  try {
    const response = await fetch(target,{
      method:req.method,
      headers:outboundHeaders(req),
      body:['GET','HEAD'].includes(req.method) ? undefined : toArrayBuffer(bytes),
      redirect:'manual'
    });
    const headers = new Headers();
    for (const name of ['content-type','etag','cache-control','last-modified','content-disposition','location']) {
      const v = response.headers.get(name); if (v) headers.set(name,v);
    }
    headers.set('x-daftar-credit-gateway','v2');

    if (req.method === 'GET' && (path === '/api/v1/users' || path === '/api/v1/users/')) {
      try {
        const payload = await response.json();
        if (payload && typeof payload === 'object' && Array.isArray((payload as Record<string,unknown>).data)) {
          const data = ((payload as Record<string,unknown>).data as Record<string,unknown>[])
            .filter(row => String(row?.user_id ?? '') === String(LEGACY_USER_ID));
          return json({...payload as Record<string,unknown>,data},response.status,{'x-daftar-credit-gateway':'v2'});
        }
        return json(payload,response.status,{'x-daftar-credit-gateway':'v2'});
      } catch (_) {
        return json({error:'invalid_users_response'},502);
      }
    }

    return new Response(response.body,{status:response.status,statusText:response.statusText,headers});
  } catch (_) {
    return json({error:'daftar_upstream_unavailable'},502);
  }
});