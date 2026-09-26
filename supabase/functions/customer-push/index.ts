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
  dueSummary?: (args: { tokenHash: string | null; endpoint: string | null; deviceSecretHash: string | null }) => Promise<Record<string, unknown>>;
  receipt?: (args: { receiptId: string; tokenHash: string | null; endpoint: string | null; deviceSecretHash: string | null }) => Promise<Record<string, unknown>>;
  periodStatement?: (args: { fromDate: string; toDate: string; tokenHash: string | null; endpoint: string | null; deviceSecretHash: string | null }) => Promise<Record<string, unknown>>;
  notificationHistory: (args: { tokenHash: string | null; endpoint: string | null; deviceSecretHash: string | null; limit: number }) => Promise<Record<string, unknown>>;
  preferences?: (args: { tokenHash: string | null; endpoint: string | null; deviceSecretHash: string | null }) => Promise<Record<string, unknown>>;
  updatePreferences?: (args: { tokenHash: string | null; endpoint: string | null; deviceSecretHash: string | null; dueReminders: boolean; installmentReminders: boolean; monthlyStatements: boolean; manualMessages: boolean }) => Promise<Record<string, unknown>>;
  markNotification?: (args: { notificationId: string; tokenHash: string | null; endpoint: string | null; deviceSecretHash: string | null; acknowledge: boolean }) => Promise<Record<string, unknown>>;
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
function isUuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
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
    action === "notifications" ||
    action === "preferences" ||
    action === "update_preferences" ||
    action === "mark_read" ||
    action === "acknowledge" ||
    action === "receipt" ||
    action === "statement"
  ) {
    if (!(await enforceRateLimit(req, deps))) return json({ error: "rate_limited" }, 429);
    if (
      (action === "validate" || action === "subscribe") &&
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
      const auth = {
        tokenHash: token ? await deps.hash(token) : null,
        endpoint,
        deviceSecretHash: deviceSecret ? await deps.hash(deviceSecret) : null,
      };
      const portal = await deps.portal({ ...auth, offset });
      const dueSummary = deps.dueSummary
        ? await deps.dueSummary(auth)
        : {};
      return json({
        ...portal,
        due_summary: dueSummary,
        vapid_public_key: deps.vapidPublicKey,
      });
    } catch (_) {
      return json({ error: "link_unavailable" }, 404);
    }
  }

  if (action === "receipt") {
    const token = isToken(body.token) ? body.token : null;
    const endpoint = typeof body.endpoint === "string" && body.endpoint.startsWith("https://")
      ? body.endpoint
      : null;
    const deviceSecret = isToken(body.device_secret) ? body.device_secret : null;
    const receiptId = String(body.receipt_id ?? "").trim();
    if ((!token && (!endpoint || !deviceSecret)) || !isUuid(receiptId)) {
      return json({ error: "invalid_input" }, 400);
    }
    if (!deps.receipt) return json({ error: "feature_unavailable" }, 503);
    try {
      return json(await deps.receipt({
        receiptId,
        tokenHash: token ? await deps.hash(token) : null,
        endpoint,
        deviceSecretHash: deviceSecret ? await deps.hash(deviceSecret) : null,
      }));
    } catch (_) {
      return json({ error: "link_unavailable" }, 404);
    }
  }

  if (action === "statement") {
    const token = isToken(body.token) ? body.token : null;
    const endpoint = typeof body.endpoint === "string" && body.endpoint.startsWith("https://")
      ? body.endpoint
      : null;
    const deviceSecret = isToken(body.device_secret) ? body.device_secret : null;
    const fromDate = String(body.from_date ?? "").trim();
    const toDate = String(body.to_date ?? "").trim();
    const datePattern = /^\d{4}-\d{2}-\d{2}$/;
    if (
      (!token && (!endpoint || !deviceSecret)) ||
      !datePattern.test(fromDate) ||
      !datePattern.test(toDate) ||
      fromDate > toDate
    ) {
      return json({ error: "invalid_input" }, 400);
    }
    if (!deps.periodStatement) return json({ error: "feature_unavailable" }, 503);
    try {
      return json(await deps.periodStatement({
        fromDate,
        toDate,
        tokenHash: token ? await deps.hash(token) : null,
        endpoint,
        deviceSecretHash: deviceSecret ? await deps.hash(deviceSecret) : null,
      }));
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

  if (action === "preferences" || action === "update_preferences") {
    const token = isToken(body.token) ? body.token : null;
    const endpoint = typeof body.endpoint === "string" && body.endpoint.startsWith("https://")
      ? body.endpoint
      : null;
    const deviceSecret = isToken(body.device_secret) ? body.device_secret : null;
    if (!token && (!endpoint || !deviceSecret)) {
      return json({ error: "link_unavailable" }, 400);
    }

    const auth = {
      tokenHash: token ? await deps.hash(token) : null,
      endpoint,
      deviceSecretHash: deviceSecret ? await deps.hash(deviceSecret) : null,
    };
    try {
      if (action === "preferences") {
        if (!deps.preferences) return json({ error: "feature_unavailable" }, 503);
        return json(await deps.preferences(auth));
      }
      if (!deps.updatePreferences) return json({ error: "feature_unavailable" }, 503);
      return json(await deps.updatePreferences({
        ...auth,
        dueReminders: body.due_reminders !== false,
        installmentReminders: body.installment_reminders !== false,
        monthlyStatements: body.monthly_statements !== false,
        manualMessages: body.manual_messages !== false,
      }));
    } catch (_) {
      return json({ error: "link_unavailable" }, 404);
    }
  }

  if (action === "mark_read" || action === "acknowledge") {
    const token = isToken(body.token) ? body.token : null;
    const endpoint = typeof body.endpoint === "string" && body.endpoint.startsWith("https://")
      ? body.endpoint
      : null;
    const deviceSecret = isToken(body.device_secret) ? body.device_secret : null;
    const notificationId = String(body.notification_id ?? "").trim();
    if ((!token && (!endpoint || !deviceSecret)) || !isUuid(notificationId)) {
      return json({ error: "invalid_input" }, 400);
    }
    if (!deps.markNotification) return json({ error: "feature_unavailable" }, 503);
    try {
      return json(await deps.markNotification({
        notificationId,
        tokenHash: token ? await deps.hash(token) : null,
        endpoint,
        deviceSecretHash: deviceSecret ? await deps.hash(deviceSecret) : null,
        acknowledge: action === "acknowledge",
      }));
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
    dueSummary: async (args) => {
      const { data, error } = await admin.rpc(
        "read_customer_portal_due_summary_service",
        {
          p_token_hash: args.tokenHash,
          p_endpoint: args.endpoint,
          p_device_secret_hash: args.deviceSecretHash,
        },
      );
      if (error) throw error;
      return (data ?? {}) as Record<string, unknown>;
    },
    receipt: async (args) => {
      const { data, error } = await admin.rpc(
        "read_customer_portal_receipt_service",
        {
          p_receipt_id: args.receiptId,
          p_token_hash: args.tokenHash,
          p_endpoint: args.endpoint,
          p_device_secret_hash: args.deviceSecretHash,
        },
      );
      if (error) throw error;
      return (data ?? {}) as Record<string, unknown>;
    },
    periodStatement: async (args) => {
      const { data, error } = await admin.rpc(
        "read_customer_period_statement_service",
        {
          p_from_date: args.fromDate,
          p_to_date: args.toDate,
          p_token_hash: args.tokenHash,
          p_endpoint: args.endpoint,
          p_device_secret_hash: args.deviceSecretHash,
        },
      );
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
    preferences: async (args) => {
      const { data, error } = await admin.rpc(
        "read_customer_notification_preferences_service",
        {
          p_token_hash: args.tokenHash,
          p_endpoint: args.endpoint,
          p_device_secret_hash: args.deviceSecretHash,
        },
      );
      if (error) throw error;
      return (data ?? {}) as Record<string, unknown>;
    },
    updatePreferences: async (args) => {
      const { data, error } = await admin.rpc(
        "update_customer_notification_preferences_service",
        {
          p_token_hash: args.tokenHash,
          p_endpoint: args.endpoint,
          p_device_secret_hash: args.deviceSecretHash,
          p_due_reminders: args.dueReminders,
          p_installment_reminders: args.installmentReminders,
          p_monthly_statements: args.monthlyStatements,
          p_manual_messages: args.manualMessages,
        },
      );
      if (error) throw error;
      return (data ?? {}) as Record<string, unknown>;
    },
    markNotification: async (args) => {
      const { data, error } = await admin.rpc(
        "mark_customer_push_notification_read_service",
        {
          p_outbox_id: args.notificationId,
          p_token_hash: args.tokenHash,
          p_endpoint: args.endpoint,
          p_device_secret_hash: args.deviceSecretHash,
          p_acknowledge: args.acknowledge,
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
