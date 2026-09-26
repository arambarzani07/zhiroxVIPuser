export const CUSTOMER_PUSH_LINK_BASE_PATH = "/functions/v1/customer-push-link";
export const CUSTOMER_PUSH_STATIC_URL = "https://push.zhirox.com/";
const CUSTOMER_PUSH_RUNTIME_PATH = "/customer-push-link";
const CUSTOMER_PUSH_API_URL = "https://madoflmbretqghqbqaak.supabase.co/functions/v1/customer-push";

const securityHeaders: Record<string, string> = {
  "Referrer-Policy": "no-referrer",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
};

function response(
  body: BodyInit | null,
  status = 200,
  contentType = "text/plain; charset=utf-8",
  extra: Record<string, string> = {},
): Response {
  return new Response(body, {
    status,
    headers: {
      ...securityHeaders,
      "Content-Type": contentType,
      ...extra,
    },
  });
}

function isToken(value: string): boolean {
  return /^[a-f0-9]{64}$/.test(value);
}

export function customerPushLinkSuffix(pathname: string): string {
  if (pathname === "" || pathname === "/") return "";
  for (const prefix of [CUSTOMER_PUSH_LINK_BASE_PATH, CUSTOMER_PUSH_RUNTIME_PATH]) {
    if (pathname === prefix || pathname === `${prefix}/`) return "";
    if (pathname.startsWith(`${prefix}/`)) return pathname.slice(prefix.length);
  }
  return pathname;
}

function manifest(token: string): Response {
  const suffix = isToken(token) ? `?token=${encodeURIComponent(token)}` : "";
  return response(
    JSON.stringify({
      name: "ZHIROX Customer Portal",
      short_name: "ZHIROX",
      start_url: `${CUSTOMER_PUSH_LINK_BASE_PATH}/${suffix}`,
      scope: `${CUSTOMER_PUSH_LINK_BASE_PATH}/`,
      display: "standalone",
      theme_color: "#f4f6fa",
      background_color: "#f4f6fa",
      lang: "ku",
      dir: "rtl",
    }),
    200,
    "application/manifest+json; charset=utf-8",
  );
}

const styles = String.raw`:root{color-scheme:light;font-family:system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;--bg:#f4f6fa;--surface:#fff;--text:#171b2e;--muted:#697086;--line:#e4e8f0;--brand:#2457d6;--brand-soft:#edf3ff;--danger:#b72f3d;--success:#087a55;--shadow:0 16px 44px rgba(20,31,61,.08)}*{box-sizing:border-box}html{background:var(--bg);overflow-x:hidden}body{margin:0;min-height:100vh;overflow-x:hidden;background:var(--bg);color:var(--text);padding:max(16px,env(safe-area-inset-top)) 14px max(88px,env(safe-area-inset-bottom))}button{font:inherit;min-height:44px}[hidden]{display:none!important}.portal-shell{width:min(100%,920px);margin:auto}.portal-header{display:flex;align-items:center;justify-content:space-between;gap:14px;margin-bottom:18px}.brand-lockup{display:flex;align-items:center;gap:12px;min-width:0}.brand-mark{width:48px;height:48px;display:grid;place-items:center;border-radius:14px;background:var(--brand);color:#fff;font-size:24px;font-weight:900;box-shadow:var(--shadow)}.eyebrow{margin:0 0 4px;color:var(--muted);font-size:12px;font-weight:800}h1{margin:0;font-size:clamp(22px,5vw,32px)}h2{margin:0;font-size:18px}.muted{color:var(--muted);line-height:1.8}.status-badge{padding:8px 11px;border-radius:999px;background:var(--brand-soft);color:var(--brand);font-size:12px;font-weight:800}.portal-nav{position:sticky;top:max(10px,env(safe-area-inset-top));z-index:5;display:grid;grid-template-columns:repeat(3,1fr);gap:6px;padding:6px;margin-bottom:16px;border:1px solid var(--line);border-radius:16px;background:rgba(255,255,255,.95);backdrop-filter:blur(16px)}.nav-item{border:0;border-radius:11px;background:transparent;color:var(--muted);font-weight:800;cursor:pointer}.nav-item.is-active{background:var(--brand);color:#fff}.portal-view{display:grid;gap:14px}.view-heading,.section-heading{display:flex;align-items:center;justify-content:space-between;gap:12px}.powered-by{font-size:11px;color:var(--muted)}.balance-card{padding:24px;border-radius:24px;background:linear-gradient(145deg,#171b2e,#253056);color:#fff;box-shadow:var(--shadow)}.balance-topline{display:flex;justify-content:space-between;gap:12px;margin-bottom:14px}.balance-status{padding:5px 8px;border:1px solid rgba(255,255,255,.18);border-radius:999px;font-size:11px}.balance-card strong{display:block;font-size:clamp(32px,10vw,48px)}.balance-caption{font-size:12px;opacity:.7}.summary-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.metric-card,.panel,.notification-card,.state-card{border:1px solid var(--line);border-radius:20px;background:var(--surface);box-shadow:0 8px 26px rgba(20,31,61,.04)}.metric-card{padding:16px}.metric-card span{display:block;color:var(--muted);font-size:12px;margin-bottom:6px}.metric-card strong{font-size:20px}.panel,.notification-card,.state-card{padding:18px}.section-heading{margin-bottom:12px}.text-action{border:0;background:transparent;color:var(--brand);font-weight:800}.ledger{display:grid;gap:10px}.entry{padding:14px;border:1px solid var(--line);border-radius:16px}.entry-head{display:flex;justify-content:space-between;gap:12px}.entry-meta{margin-top:7px;color:var(--muted);font-size:13px}.debt-label{color:var(--danger)}.payment-label{color:var(--success)}.primary-action,.secondary-action{width:100%;margin-top:12px;border-radius:14px;padding:12px 16px;font-weight:800}.primary-action{border:0;background:var(--brand);color:#fff}.secondary-action{border:1px solid var(--line);background:#fff;color:var(--text)}.notification-state{color:var(--brand);font-weight:900}.notification-state[data-state="active"]{color:var(--success)}.notification-state[data-state="error"]{color:var(--danger)}.notification-copy{margin-bottom:14px}.action-result{font-size:13px}.state-card{text-align:center;padding-block:34px}.state-icon{width:52px;height:52px;margin:0 auto 12px;display:grid;place-items:center;border-radius:16px;background:#fff1f2;color:var(--danger);font-weight:900}.help-dialog{width:min(calc(100% - 28px),480px);border:0;border-radius:22px;padding:0}.help-dialog form{padding:22px}.dialog-close{float:left;width:44px;border:0;border-radius:12px;font-size:24px}.sr-status{position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%);white-space:nowrap}@media(max-width:420px){body{padding-inline:10px}.portal-header{align-items:flex-start}.status-badge{max-width:105px;text-align:center}.portal-nav{position:fixed;inset-inline:10px;bottom:max(8px,env(safe-area-inset-bottom));top:auto;margin:0}.nav-item{font-size:11px}.balance-card{padding:20px}.powered-by{display:none}}@media(max-width:340px){.summary-grid{grid-template-columns:1fr}.status-badge{display:none}}@media(min-width:720px){.summary-grid{grid-template-columns:repeat(4,minmax(0,1fr))}}@media(prefers-reduced-motion:reduce){*,*::before,*::after{scroll-behavior:auto!important;transition:none!important;animation:none!important}}`;

const appJs = String.raw`'use strict';
const BASE='/functions/v1/customer-push-link';
const API='${CUSTOMER_PUSH_API_URL}';
const LINK_KEY='zhirox_push_link_token';
const SECRET_KEY='zhirox_push_device_secret';
const ENDPOINT_KEY='zhirox_push_endpoint';
const TOKEN=/^[a-f0-9]{64}$/;
const byId=(id)=>document.getElementById(id);
const portal=byId('portalApp'),locked=byId('lockedState'),market=byId('marketBrand'),greeting=byId('customerGreeting'),badge=byId('accountBadge'),balance=byId('primaryRemaining'),currency=byId('primaryCurrency'),metrics=byId('summaryMetrics'),recent=byId('recentLedger'),ledger=byId('ledger'),more=byId('loadMore'),state=byId('notificationState'),enable=byId('enable'),iosHelp=byId('showIosHelp'),dialog=byId('iosHelpDialog'),result=byId('result'),status=byId('status');
let activeToken='',vapid='',offset=0;
function setStatus(text){status.textContent=text}
function setResult(text,kind){result.textContent=text;result.className='action-result '+(kind||'')}
function tab(name){for(const button of document.querySelectorAll('[data-tab]'))button.classList.toggle('is-active',button.dataset.tab===name);byId('homeView').hidden=name!=='home';byId('transactionsView').hidden=name!=='transactions';byId('notificationsView').hidden=name!=='notifications';window.scrollTo({top:0,behavior:matchMedia('(prefers-reduced-motion: reduce)').matches?'auto':'smooth'})}
byId('homeTab').onclick=()=>tab('home');byId('transactionsTab').onclick=()=>tab('transactions');byId('notificationsTab').onclick=()=>tab('notifications');byId('openTransactions').onclick=()=>tab('transactions');
function ios(){const ua=navigator.userAgent||'';return /iPad|iPhone|iPod/.test(ua)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1)}
function standalone(){return navigator.standalone===true||matchMedia('(display-mode: standalone)').matches}
function supportsPush(){return 'serviceWorker'in navigator&&'PushManager'in window&&'Notification'in window}
function vapidKey(value){const pad='='.repeat((4-value.length%4)%4);const raw=atob((value+pad).replace(/-/g,'+').replace(/_/g,'/'));return Uint8Array.from([...raw].map((c)=>c.charCodeAt(0)))}
async function api(payload){const r=await fetch(API,{method:'POST',mode:'cors',credentials:'omit',headers:{'content-type':'application/json'},body:JSON.stringify(payload)});const data=await r.json().catch(()=>({}));if(!r.ok)throw new Error(data.error||'request_failed');return data}
function resolveToken(){const q=new URL(location.href).searchParams.get('token')||'';if(q){if(!TOKEN.test(q))return'';localStorage.setItem(LINK_KEY,q);return q}const saved=localStorage.getItem(LINK_KEY)||'';return TOKEN.test(saved)?saved:''}
function credentials(next=0){if(activeToken)return{action:'portal',token:activeToken,offset:next};const endpoint=localStorage.getItem(ENDPOINT_KEY)||'',secret=localStorage.getItem(SECRET_KEY)||'';if(endpoint.startsWith('https://')&&TOKEN.test(secret))return{action:'portal',endpoint:endpoint,device_secret:secret,offset:next};return null}
function amount(value,unit){const n=Number(value||0);return new Intl.NumberFormat('en-US',{maximumFractionDigits:2}).format(Number.isFinite(n)?n:0)+' '+(unit||'IQD')}
function text(parent,tag,value,className){const el=document.createElement(tag);el.textContent=value;if(className)el.className=className;parent.appendChild(el);return el}
function renderTotals(totals){metrics.replaceChildren();const list=Array.isArray(totals)?totals:[];const first=list[0]||{};const unit=typeof first.currency==='string'?first.currency:'IQD';balance.textContent=amount(first.remaining||0,unit);currency.textContent=unit;if(!list.length){list.push({currency:'IQD',total_debt:0,paid:0,remaining:0})}for(const item of list){const c=typeof item.currency==='string'?item.currency:'IQD';const d=document.createElement('article');d.className='metric-card';text(d,'span','کۆی قەرز — '+c);text(d,'strong',amount(item.total_debt,c));metrics.appendChild(d);const p=document.createElement('article');p.className='metric-card';text(p,'span','کۆی پارەدان — '+c);text(p,'strong',amount(item.paid,c));metrics.appendChild(p)}}
function entry(item){const payment=item.kind==='payment',el=document.createElement('article');el.className='entry';const head=document.createElement('div');head.className='entry-head';text(head,'strong',payment?'پارەدان':'قەرز',payment?'payment-label':'debt-label');text(head,'strong',amount(item.amount,item.currency));el.appendChild(head);const when=new Date(item.occurred_at);const date=Number.isNaN(when.getTime())?'':when.toLocaleDateString('ku-IQ');const note=typeof item.note==='string'?item.note:'';if(date||note)text(el,'div',[date,note].filter(Boolean).join(' — '),'entry-meta');if(!payment)text(el,'div','ماوە: '+amount(item.remaining,item.currency),'entry-meta');return el}
function renderRows(rows,append){if(!append)ledger.replaceChildren();const list=Array.isArray(rows)?rows:[];if(!list.length&&!append){text(ledger,'p','هێشتا هیچ مامەڵەیەک تۆمار نەکراوە.','muted');return}for(const item of list)ledger.appendChild(entry(item))}
function renderRecent(rows){recent.replaceChildren();const list=Array.isArray(rows)?rows.slice(0,4):[];if(!list.length){text(recent,'p','هێشتا هیچ مامەڵەیەک تۆمار نەکراوە.','muted');return}for(const item of list)recent.appendChild(entry(item))}
function renderState(kind,message){state.dataset.state=kind;state.textContent=message}
function lock(){portal.hidden=true;locked.hidden=false;badge.textContent='ڕاگیراو / نادروست';setStatus('ئەم لینکە بەردەست نییە یان ڕاگیراوە.')}
async function load(next=0,append=false){const c=credentials(next);if(!c)throw new Error('link_unavailable');const data=await api(c);market.textContent=(data.market_name||'').trim()||'ZHIROX';greeting.textContent=data.customer_name?'بەخێربێیت، '+data.customer_name:'هەژماری کڕیار';badge.textContent='هەژماری چالاک';vapid=typeof data.vapid_public_key==='string'?data.vapid_public_key:'';locked.hidden=true;portal.hidden=false;renderTotals(data.totals);renderRows(data.rows,append);if(!append)renderRecent(data.rows);offset=next+(Array.isArray(data.rows)?data.rows.length:0);more.hidden=data.has_more!==true;return data}
function configure(data){enable.hidden=true;iosHelp.hidden=true;setResult('');if(data.can_subscribe!==true){renderState('active','ئاگادارکردنەوە چالاکە');return}if(!supportsPush()){renderState('error','ئەم وێبگەڕە پشتگیری Web Push ناکات');return}if(Notification.permission==='denied'){renderState('error','مۆڵەتی ئاگادارکردنەوە ڕەتکراوەتەوە');return}if(ios()&&!standalone()){iosHelp.hidden=false;renderState('install-required','بۆ iPhone سەرەتا پۆرتال زیاد بکە بۆ Home Screen');return}enable.hidden=false;renderState('ready','ئاگادارکردنەوە هێشتا چالاک نەکراوە')}
more.onclick=async()=>{more.disabled=true;try{await load(offset,true)}catch(_){setResult('نەتوانرا مامەڵەی زیاتر بهێنرێت.','err')}finally{more.disabled=false}};
iosHelp.onclick=()=>{if(typeof dialog.showModal==='function')dialog.showModal();else setResult('لە Safari: Share → Add to Home Screen.','err')};
enable.onclick=async()=>{enable.disabled=true;setResult('');try{if(!activeToken||!TOKEN.test(activeToken))throw new Error('link_unavailable');if(!supportsPush())throw new Error('push_unsupported');if(ios()&&!standalone())throw new Error('ios_not_standalone');const permission=await Notification.requestPermission();if(permission!=='granted')throw new Error('permission_denied');const registration=await navigator.serviceWorker.register(BASE+'/sw.js',{scope:BASE+'/'});await navigator.serviceWorker.ready;let sub=await registration.pushManager.getSubscription();if(!sub){sub=await registration.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:vapidKey(vapid)})}const data=await api({action:'subscribe',token:activeToken,subscription:sub.toJSON(),platform:ios()?'ios':(/Android/i.test(navigator.userAgent||'')?'android':'desktop')});if(data.linked!==true||typeof data.device_secret!=='string'||!data.device_secret){throw new Error('request_failed')}localStorage.setItem(SECRET_KEY,data.device_secret);localStorage.setItem(ENDPOINT_KEY,sub.endpoint);localStorage.removeItem(LINK_KEY);activeToken='';history.replaceState(null,'',BASE+'/');renderState('active','ئاگادارکردنەوە چالاک کرا');setStatus('پەیوەستکرا.');setResult('ئاگادارکردنەوە بە سەرکەوتوویی چالاک کرا و بە ناوی سوپەرمارکێتەکەت دێت.','ok');enable.hidden=true;iosHelp.hidden=true;await load()}catch(e){const reason=e instanceof Error?e.message:'request_failed';if(reason==='permission_denied'){renderState('error','مۆڵەتی ئاگادارکردنەوە ڕەتکرایەوە');setResult('لە ڕێکخستنەکانی ئامێرەکەت مۆڵەت بدە.','err')}else if(reason==='ios_not_standalone'){iosHelp.hidden=false;renderState('install-required','بۆ iPhone سەرەتا پۆرتال زیاد بکە بۆ Home Screen');setResult('لە Safari زیادیکە بۆ Home Screen و لەوێوە بیکەرەوە.','err')}else{renderState('error','چالاککردن سەرکەوتوو نەبوو');setResult('دووبارە هەوڵ بدە.','err')}enable.disabled=false}};
(async()=>{activeToken=resolveToken();if(!activeToken&&!credentials()){lock();return}try{const data=await load();tab('home');configure(data);setStatus('هەژمارەکەت ئامادەیە.')}catch(_){lock()}})();`;

const serviceWorkerJs = String.raw`'use strict';
const PORTAL='/functions/v1/customer-push-link/';
function portalUrl(value){try{const candidate=new URL(value||PORTAL,self.location.origin);if(candidate.origin===self.location.origin&&candidate.pathname.startsWith('/functions/v1/customer-push-link'))return candidate.pathname+candidate.search+candidate.hash}catch(_){}return PORTAL}
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',(event)=>event.waitUntil(self.clients.claim()));
self.addEventListener('push',(event)=>{let data={};try{data=event.data?event.data.json():{}}catch(_){}event.waitUntil(self.registration.showNotification(data.title||'ZHIROX',{body:data.body||'',data:{url:portalUrl(data.url)}}))});
self.addEventListener('notificationclick',(event)=>{event.notification.close();const target=portalUrl(event.notification.data&&event.notification.data.url);event.waitUntil((async()=>{const windows=await self.clients.matchAll({type:'window',includeUncontrolled:true});if(windows.length){const portal=windows[0];if('navigate'in portal)await portal.navigate(target);await portal.focus();return}await self.clients.openWindow(target)})())});`;

export function routeCustomerPushLink(req: Request): Response {
  const url = new URL(req.url);
  const token = url.searchParams.get("token") ?? "";

  if (req.method === "OPTIONS") {
    return response("ok", 200, "text/plain; charset=utf-8", {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET,HEAD,OPTIONS",
    });
  }
  if (req.method !== "GET" && req.method !== "HEAD") {
    return response("method_not_allowed", 405);
  }

  const suffix = customerPushLinkSuffix(url.pathname);
  const head = req.method === "HEAD";

  if (suffix === "/styles.css") {
    return response(head ? null : styles, 200, "text/css; charset=utf-8");
  }
  if (suffix === "/app.js") {
    return response(head ? null : appJs, 200, "application/javascript; charset=utf-8");
  }
  if (suffix === "/sw.js") {
    return response(head ? null : serviceWorkerJs, 200, "application/javascript; charset=utf-8", {
      "Service-Worker-Allowed": `${CUSTOMER_PUSH_LINK_BASE_PATH}/`,
    });
  }
  if (suffix === "/manifest.webmanifest") {
    if (head) return response(null, 200, "application/manifest+json; charset=utf-8");
    return manifest(token);
  }
  if (suffix === "") {
    const location = isToken(token)
      ? `${CUSTOMER_PUSH_STATIC_URL}?token=${encodeURIComponent(token)}`
      : CUSTOMER_PUSH_STATIC_URL;
    return new Response(null, {
      status: 307,
      headers: {
        ...securityHeaders,
        Location: location,
      },
    });
  }

  return response("not_found", 404);
}

if (import.meta.main) Deno.serve(routeCustomerPushLink);
