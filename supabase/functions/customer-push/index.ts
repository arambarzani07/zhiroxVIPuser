import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import { randomHexToken, sha256Hex } from "../_shared/customer_push/crypto.ts";
import { loadOrInitializePushRuntime } from "../_shared/customer_push/runtime.ts";

const basePath = "/functions/v1/customer-push";
const publicBaseUrl = "https://push.zhirox.com/";
const securityHeaders = {
  "Referrer-Policy": "no-referrer",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
};

function response(body: string, status = 200, contentType = "text/plain; charset=utf-8", extra: Record<string, string> = {}) {
  return new Response(body, { status, headers: { ...securityHeaders, "Content-Type": contentType, ...extra } });
}
function json(body: unknown, status = 200) {
  return response(JSON.stringify(body), status, "application/json; charset=utf-8", { "Access-Control-Allow-Origin": "*" });
}
function envJsonKey(name: string): string | null {
  const raw = Deno.env.get(name);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    return parsed.default ?? Object.values(parsed)[0] ?? null;
  } catch (_) {
    return raw;
  }
}

export type PublicPushDeps = {
  hash: (value: string) => Promise<string>;
  randomToken: () => string;
  vapidPublicKey: string;
  rateLimitSalt: string;
  inspect: (tokenHash: string) => Promise<Record<string, unknown>>;
  portal: (args: { tokenHash: string | null; endpoint: string | null; deviceSecretHash: string | null; offset: number }) => Promise<Record<string, unknown>>;
  notificationHistory: (args: { tokenHash: string | null; endpoint: string | null; deviceSecretHash: string | null; limit: number }) => Promise<Record<string, unknown>>;
  redeem: (args: { tokenHash: string; endpoint: string; p256dh: string; auth: string; deviceSecretHash: string; userAgent: string; platform: string }) => Promise<Record<string, unknown>>;
  unsubscribe: (endpoint: string, deviceSecretHash: string) => Promise<boolean>;
  consumeRateLimit: (keyHash: string, limit: number, windowSeconds: number) => Promise<boolean>;
};

function clientIp(req: Request): string {
  const cf = req.headers.get("cf-connecting-ip")?.trim();
  if (cf) return cf;
  const forwarded = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return forwarded || "unknown";
}
function isToken(value: unknown): value is string {
  return typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
}
async function enforceRateLimit(req: Request, deps: PublicPushDeps): Promise<boolean> {
  const keyHash = await deps.hash(`${deps.rateLimitSalt}:${clientIp(req)}`);
  return await deps.consumeRateLimit(keyHash, 30, 60);
}

function manifest(token: string): Response {
  return response(JSON.stringify({
    name: "ZHIROX Notifications",
    short_name: "ZHIROX",
    display: "standalone",
    start_url: `${basePath}?token=${encodeURIComponent(token)}`,
    scope: `${basePath}/`,
    theme_color: "#ffffff",
    background_color: "#ffffff",
  }), 200, "application/manifest+json; charset=utf-8");
}

function serviceWorker(): Response {
  const script = `self.addEventListener('push',event=>{const data=event.data?event.data.json():{};event.waitUntil(self.registration.showNotification(data.title||'ZHIROX',{body:data.body||'',data:{url:data.url||'${basePath}'}}));});self.addEventListener('notificationclick',event=>{event.notification.close();event.waitUntil(clients.openWindow(event.notification.data.url));});`;
  return response(script, 200, "application/javascript; charset=utf-8", { "Service-Worker-Allowed": `${basePath}/` });
}

function genericLanding(): Response {
  return response(`<!doctype html><html lang="ku" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>ZHIROX Notifications</title><style>body{font-family:system-ui;background:#f6f7fb;color:#171b2e;display:grid;place-items:center;min-height:100vh;margin:0}.card{background:white;padding:28px;border-radius:20px;max-width:520px;box-shadow:0 16px 45px #0001;text-align:center}</style></head><body><main class="card"><h1>ZHIROX Notifications</h1><p>بۆ پەیوەستکردن یان دووبارە پەیوەستکردن، QR ـێکی نوێ لە مارکێتەکەت scan بکە.</p></main></body></html>`, 200, "text/html; charset=utf-8", {
    "Content-Security-Policy": "default-src 'self'; style-src 'unsafe-inline'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'",
  });
}

function onboarding(token: string): Response {
  const safeToken = token.replace(/[^a-f0-9]/g, "");
  const html = `<!doctype html><html lang="ku" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><title>ZHIROX Notifications</title><link rel="manifest" href="${basePath}/manifest.webmanifest?token=${safeToken}"><meta name="theme-color" content="#ffffff"><style>body{font-family:system-ui,-apple-system,sans-serif;background:#f6f7fb;color:#171b2e;margin:0;min-height:100vh;display:grid;place-items:center}.card{width:min(92vw,540px);background:#fff;border-radius:22px;box-shadow:0 16px 50px #0001;padding:26px;box-sizing:border-box}.muted{color:#687086}.hidden{display:none}.row{padding:12px 0;border-bottom:1px solid #e2e5ef}button{width:100%;border:0;border-radius:14px;padding:14px 16px;font-weight:700;font-size:16px;background:#3157e0;color:#fff}button:disabled{opacity:.55}.ok{color:#0e9f6e}.err{color:#e5484d}</style></head><body><main class="card"><h1>ئاگادارکردنەوەی ZHIROX</h1><p id="status" class="muted">پشکنینی لینک...</p><section id="identity" class="hidden"><div class="row"><strong>کڕیار:</strong> <span id="customerName"></span></div><div class="row"><strong>مارکێت:</strong> <span id="marketName"></span></div></section><div id="iosHelp" class="hidden"><p>لە iPhone/iPad: لە Safari دوگمەی Share بکە، <strong>Add to Home Screen</strong> هەڵبژێرە، پاشان ZHIROX Notifications لە Home Screen بکەرەوە.</p></div><button id="enable" class="hidden">چالاککردنی ئاگادارکردنەوە</button><p id="result"></p></main><script>
const TOKEN=${JSON.stringify(safeToken)};const BASE=${JSON.stringify(basePath)};const statusEl=document.getElementById('status'),identity=document.getElementById('identity'),enable=document.getElementById('enable'),result=document.getElementById('result');function b64ToUint8(value){const pad='='.repeat((4-value.length%4)%4);const raw=atob((value+pad).replace(/-/g,'+').replace(/_/g,'/'));return Uint8Array.from([...raw].map(c=>c.charCodeAt(0)));}function platform(){const ua=navigator.userAgent||'';if(/iPad|iPhone|iPod/.test(ua))return 'ios';if(/Android/i.test(ua))return 'android';return 'desktop';}function standalone(){return window.navigator.standalone===true||window.matchMedia('(display-mode: standalone)').matches;}async function api(payload){const r=await fetch(BASE,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(payload)});const data=await r.json().catch(()=>({}));if(!r.ok)throw new Error(data.error||'request_failed');return data;}let vapid='';(async()=>{try{const data=await api({action:'validate',token:TOKEN});document.getElementById('customerName').textContent=data.customer_name||'';document.getElementById('marketName').textContent=data.market_name||'';identity.classList.remove('hidden');vapid=data.vapid_public_key||'';const isiOS=platform()==='ios';if(isiOS&&!standalone()){document.getElementById('iosHelp').classList.remove('hidden');statusEl.textContent='سەرەتا زیادیکە بۆ Home Screen.';}else{enable.classList.remove('hidden');statusEl.textContent='لینکەکە دروستە. دەتوانیت ئاگادارکردنەوە چالاک بکەیت.';}}catch(e){statusEl.textContent='ئەم لینکە بەردەست نییە یان ماوەکەی تەواو بووە.';statusEl.className='err';}})();enable.addEventListener('click',async()=>{enable.disabled=true;result.textContent='';try{if(!('serviceWorker' in navigator)||!('PushManager' in window))throw new Error('push_unsupported');const permission=await Notification.requestPermission();if(permission!=='granted')throw new Error('permission_denied');const reg=await navigator.serviceWorker.register(BASE+'/sw.js',{scope:BASE+'/'});await navigator.serviceWorker.ready;const sub=await reg.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:b64ToUint8(vapid)});const data=await api({action:'subscribe',token:TOKEN,subscription:sub.toJSON(),platform:platform()});localStorage.setItem('zhirox_push_device_secret',data.device_secret||'');localStorage.setItem('zhirox_push_endpoint',sub.endpoint);result.textContent='ئاگادارکردنەوە بە سەرکەوتوویی چالاک کرا.';result.className='ok';statusEl.textContent='پەیوەستکرا.';}catch(e){result.textContent=e.message==='permission_denied'?'مۆڵەتی ئاگادارکردنەوە نەدرا.':'چالاککردن سەرکەوتوو نەبوو؛ دووبارە هەوڵ بدە.';result.className='err';enable.disabled=false;}});
</script></body></html>`;
  return response(html, 200, "text/html; charset=utf-8", {
    "Content-Security-Policy": "default-src 'self'; connect-src 'self'; worker-src 'self'; manifest-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'",
  });
}

export async function routeCustomerPush(req: Request, deps: PublicPushDeps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "content-type", "Access-Control-Allow-Methods": "GET,POST,OPTIONS" } });
  const url = new URL(req.url);
  if (req.method === "GET") {
    const token = url.searchParams.get("token") ?? "";
    const destination = new URL(publicBaseUrl);
    if (isToken(token)) destination.searchParams.set("token", token);
    return Response.redirect(destination, 307);
  }
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch (_) { return json({ error: "invalid_json" }, 400); }
  const action = String(body.action ?? "");
  if (
    action === "validate" ||
    action === "subscribe" ||
    action === "portal" ||
    action === "notifications"
  ) {
    if (!(await enforceRateLimit(req, deps))) return json({ error: "rate_limited" }, 429);
    if (
      action !== "portal" &&
      action !== "notifications" &&
      !isToken(body.token)
    ) {
      return json({ error: "link_unavailable" }, 400);
    }
  }

  if (action === "portal") {
    const token = isToken(body.token) ? body.token : null;
    const endpoint = typeof body.endpoint === "string" && body.endpoint.startsWith("https://") ? body.endpoint : null;
    const deviceSecret = isToken(body.device_secret) ? body.device_secret : null;
    const offset = Number(body.offset ?? 0);
    if ((!token && (!endpoint || !deviceSecret)) || !Number.isInteger(offset) || offset < 0 || offset > 1000000) {
      return json({ error: "link_unavailable" }, 400);
    }
    try {
      const portal = await deps.portal({
        tokenHash: token ? await deps.hash(token) : null,
        endpoint,
        deviceSecretHash: deviceSecret ? await deps.hash(deviceSecret) : null,
        offset,
      });
      return json({ ...portal, vapid_public_key: deps.vapidPublicKey });
    } catch (_) {
      return json({ error: "link_unavailable" }, 404);
    }
  }

  if (action === "notifications") {
    const token = isToken(body.token) ? body.token : null;
    const endpoint = typeof body.endpoint === "string" && body.endpoint.startsWith("https://")
      ? body.endpoint
      : null;
    const deviceSecret = isToken(body.device_secret) ? body.device_secret : null;
    const rawLimit = Number(body.limit ?? 20);
    const limit = Number.isFinite(rawLimit)
      ? Math.max(1, Math.min(Math.trunc(rawLimit), 50))
      : 20;
    if (!token && (!endpoint || !deviceSecret)) {
      return json({ error: "link_unavailable" }, 400);
    }
    try {
      const history = await deps.notificationHistory({
        tokenHash: token ? await deps.hash(token) : null,
        endpoint,
        deviceSecretHash: deviceSecret ? await deps.hash(deviceSecret) : null,
        limit,
      });
      return json(history);
    } catch (_) {
      return json({ error: "link_unavailable" }, 404);
    }
  }

  if (action === "validate") {
    try {
      const inspected = await deps.inspect(await deps.hash(body.token as string));
      return json({ customer_name: inspected.customer_name ?? "", market_name: inspected.market_name ?? "", expires_at: inspected.expires_at ?? null, vapid_public_key: deps.vapidPublicKey });
    } catch (_) { return json({ error: "link_unavailable" }, 404); }
  }
  if (action === "subscribe") {
    const subscription = body.subscription;
    if (!subscription || typeof subscription !== "object") return json({ error: "invalid_subscription" }, 400);
    const map = subscription as Record<string, unknown>;
    const endpoint = String(map.endpoint ?? "").trim();
    const keys = map.keys as Record<string, unknown> | undefined;
    const p256dh = String(keys?.p256dh ?? "").trim();
    const auth = String(keys?.auth ?? "").trim();
    if (!endpoint.startsWith("https://") || !p256dh || !auth) return json({ error: "invalid_subscription" }, 400);
    const rawDeviceSecret = deps.randomToken();
    try {
      await deps.redeem({ tokenHash: await deps.hash(body.token as string), endpoint, p256dh, auth, deviceSecretHash: await deps.hash(rawDeviceSecret), userAgent: req.headers.get("user-agent") ?? "", platform: String(body.platform ?? "desktop") });
      return json({ linked: true, device_secret: rawDeviceSecret });
    } catch (_) { return json({ error: "link_unavailable" }, 404); }
  }
  if (action === "unsubscribe") {
    const endpoint = String(body.endpoint ?? "").trim();
    const deviceSecret = String(body.device_secret ?? "").trim();
    if (!endpoint || !deviceSecret) return json({ error: "invalid_input" }, 400);
    return json({ unlinked: await deps.unsubscribe(endpoint, await deps.hash(deviceSecret)) });
  }
  return json({ error: "unsupported_action" }, 400);
}

async function serve(req: Request): Promise<Response> {
  const url = Deno.env.get("SUPABASE_URL")!;
  const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? envJsonKey("SUPABASE_SECRET_KEYS");
  if (!url || !secret) return json({ error: "server_not_configured" }, 500);
  const admin = createClient(url, secret, { auth: { persistSession: false, autoRefreshToken: false } });
  let runtime;
  try { runtime = await loadOrInitializePushRuntime(admin); }
  catch (_) { return json({ error: "server_not_configured" }, 500); }

  return await routeCustomerPush(req, {
    hash: sha256Hex,
    randomToken: () => randomHexToken(32),
    vapidPublicKey: runtime.vapidPublicKey,
    rateLimitSalt: runtime.rateLimitSalt,
    inspect: async (tokenHash) => {
      const { data, error } = await admin.rpc("inspect_customer_push_link_service", { p_token_hash: tokenHash });
      if (error) throw error;
      return (data ?? {}) as Record<string, unknown>;
    },
    portal: async (args) => {
      const { data, error } = await admin.rpc("read_customer_push_portal_service", {
        p_token_hash: args.tokenHash,
        p_endpoint: args.endpoint,
        p_device_secret_hash: args.deviceSecretHash,
        p_offset: args.offset,
      });
      if (error) throw error;
      return (data ?? {}) as Record<string, unknown>;
    },
    notificationHistory: async (args) => {
      const { data, error } = await admin.rpc(
        "read_customer_push_notification_history_service",
        {
          p_token_hash: args.tokenHash,
          p_endpoint: args.endpoint,
          p_device_secret_hash: args.deviceSecretHash,
          p_limit: args.limit,
        },
      );
      if (error) throw error;
      return (data ?? {}) as Record<string, unknown>;
    },
    redeem: async (args) => {
      const { data, error } = await admin.rpc("redeem_customer_push_subscription_service", { p_token_hash: args.tokenHash, p_endpoint: args.endpoint, p_p256dh: args.p256dh, p_auth: args.auth, p_device_secret_hash: args.deviceSecretHash, p_user_agent: args.userAgent, p_platform: args.platform });
      if (error) throw error;
      return (data ?? {}) as Record<string, unknown>;
    },
    unsubscribe: async (endpoint, deviceSecretHash) => {
      const { data, error } = await admin.rpc("unsubscribe_customer_push_subscription_service", { p_endpoint: endpoint, p_device_secret_hash: deviceSecretHash });
      if (error) throw error;
      return data === true;
    },
    consumeRateLimit: async (keyHash, limit, windowSeconds) => {
      const { data, error } = await admin.rpc("consume_customer_push_rate_limit", { p_key_hash: keyHash, p_limit: limit, p_window_seconds: windowSeconds });
      if (error) throw error;
      return data === true;
    },
  });
}

if (import.meta.main) Deno.serve(serve);
