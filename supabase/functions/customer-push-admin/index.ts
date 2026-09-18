import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import { randomHexToken, sha256Hex } from "../_shared/customer_push/crypto.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

export const CUSTOMER_PUSH_PUBLIC_BASE_URL = "https://push.zhirox.com/";
export const MANUAL_PUSH_MESSAGE_MAX_LENGTH = 240;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
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

export type AdminDeps = {
  now: () => Date;
  randomToken: () => string;
  randomId: () => string;
  hash: (value: string) => Promise<string>;
  manageLink: (args: {
    actorId: string;
    customerId: string;
    tokenHash: string;
    expiresAt: string | null;
  }) => Promise<unknown>;
  status: (args: { actorId: string; customerId: string }) => Promise<Record<string, unknown>>;
  overview: (args: {
    actorId: string;
    search: string;
    filter: string;
    limit: number;
    offset: number;
  }) => Promise<Record<string, unknown>>;
  history: (args: {
    actorId: string;
    customerId: string;
    limit: number;
  }) => Promise<Record<string, unknown>>;
  retry: (args: {
    actorId: string;
    customerId: string;
    outboxId: string;
  }) => Promise<Record<string, unknown>>;
  revokeAll: (args: { actorId: string; customerId: string }) => Promise<number>;
  sendManual: (args: {
    actorId: string;
    customerId: string | null;
    message: string;
    requestId: string;
  }) => Promise<Record<string, unknown>>;
  publicBaseUrl: string;
};

function requireCustomerId(value: unknown): string {
  const id = String(value ?? "").trim();
  if (!/^[0-9a-f-]{36}$/i.test(id)) throw new Error("invalid_customer_id");
  return id;
}

function requireOutboxId(value: unknown): string {
  const id = String(value ?? "").trim();
  if (!/^[0-9a-f-]{36}$/i.test(id)) throw new Error("invalid_outbox_id");
  return id;
}

function requireManualMessage(value: unknown): string {
  const message = String(value ?? "").trim();
  if (!message || message.length > MANUAL_PUSH_MESSAGE_MAX_LENGTH) {
    throw new Error("invalid_message");
  }
  return message;
}

export async function handleAdminAction(
  body: Record<string, unknown>,
  actorId: string,
  deps: AdminDeps,
): Promise<Record<string, unknown>> {
  const action = String(body.action ?? "");

  if (action === "broadcast_manual") {
    const message = requireManualMessage(body.message);
    return await deps.sendManual({
      actorId,
      customerId: null,
      message,
      requestId: deps.randomId(),
    });
  }

  if (action === "overview") {
    const search = String(body.search ?? "").trim();
    const filter = String(body.filter ?? "all").trim().toLowerCase();
    if (!["all", "active", "inactive", "failed", "pending"].includes(filter)) {
      throw new Error("invalid_overview_filter");
    }
    const rawLimit = Number(body.limit ?? 60);
    const rawOffset = Number(body.offset ?? 0);
    const limit = Number.isFinite(rawLimit)
      ? Math.max(1, Math.min(Math.trunc(rawLimit), 100))
      : 60;
    const offset = Number.isFinite(rawOffset)
      ? Math.max(0, Math.trunc(rawOffset))
      : 0;
    return await deps.overview({ actorId, search, filter, limit, offset });
  }

  const customerId = requireCustomerId(body.customer_id);

  if (action === "create_link") {
    const rawToken = deps.randomToken();
    const tokenHash = await deps.hash(rawToken);
    await deps.manageLink({
      actorId,
      customerId,
      tokenHash,
      expiresAt: null,
    });
    const separator = deps.publicBaseUrl.includes("?") ? "&" : "?";
    return {
      url: `${deps.publicBaseUrl}${separator}token=${encodeURIComponent(rawToken)}`,
      expires_at: null,
    };
  }

  if (action === "status") {
    return await deps.status({ actorId, customerId });
  }

  if (action === "history") {
    const requestedLimit = Number(body.limit ?? 20);
    const limit = Number.isFinite(requestedLimit)
      ? Math.max(1, Math.min(Math.trunc(requestedLimit), 100))
      : 20;
    return await deps.history({ actorId, customerId, limit });
  }

  if (action === "retry") {
    return await deps.retry({
      actorId,
      customerId,
      outboxId: requireOutboxId(body.outbox_id),
    });
  }

  if (action === "revoke_all") {
    return {
      revoked_count: await deps.revokeAll({ actorId, customerId }),
    };
  }

  if (action === "send_manual") {
    const message = requireManualMessage(body.message);
    return await deps.sendManual({
      actorId,
      customerId,
      message,
      requestId: deps.randomId(),
    });
  }

  throw new Error("unsupported_action");
}

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    envJsonKey("SUPABASE_SECRET_KEYS");
  if (!url || !secret) return json({ error: "server_not_configured" }, 500);

  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!bearer) return json({ error: "authentication_required" }, 401);

  const admin = createClient(url, secret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await admin.auth.getUser(bearer);
  if (userError || !userData.user) return json({ error: "authentication_required" }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "invalid_json" }, 400);
  }

  try {
    const result = await handleAdminAction(body, userData.user.id, {
      now: () => new Date(),
      randomToken: () => randomHexToken(32),
      randomId: () => crypto.randomUUID(),
      hash: sha256Hex,
      publicBaseUrl: CUSTOMER_PUSH_PUBLIC_BASE_URL,
      manageLink: async ({ actorId, customerId, tokenHash, expiresAt }) => {
        const { error } = await admin.rpc("manage_customer_push_link", {
          p_actor: actorId,
          p_customer: customerId,
          p_token_hash: tokenHash,
          p_expires_at: expiresAt,
        });
        if (error) throw error;
      },
      overview: async ({ actorId, search, filter, limit, offset }) => {
        const { data, error } = await admin.rpc(
          "list_customer_push_overview_service",
          {
            p_actor: actorId,
            p_search: search,
            p_filter: filter,
            p_limit: limit,
            p_offset: offset,
          },
        );
        if (error) throw error;
        return (data ?? {}) as Record<string, unknown>;
      },
      status: async ({ actorId, customerId }) => {
        const { data, error } = await admin.rpc("customer_push_status_service", {
          p_actor: actorId,
          p_customer: customerId,
        });
        if (error) throw error;
        return (data ?? {}) as Record<string, unknown>;
      },
      history: async ({ actorId, customerId, limit }) => {
        const { data, error } = await admin.rpc(
          "read_customer_push_history_service",
          {
            p_actor: actorId,
            p_customer: customerId,
            p_limit: limit,
          },
        );
        if (error) throw error;
        return (data ?? {}) as Record<string, unknown>;
      },
      retry: async ({ actorId, customerId, outboxId }) => {
        const { data, error } = await admin.rpc(
          "retry_customer_push_service",
          {
            p_actor: actorId,
            p_customer: customerId,
            p_outbox_id: outboxId,
          },
        );
        if (error) throw error;
        return (data ?? {}) as Record<string, unknown>;
      },
      revokeAll: async ({ actorId, customerId }) => {
        const { data, error } = await admin.rpc(
          "revoke_customer_push_subscriptions_service",
          { p_actor: actorId, p_customer: customerId },
        );
        if (error) throw error;
        return Number(data ?? 0);
      },
      sendManual: async ({ actorId, customerId, message, requestId }) => {
        const { data, error } = await admin.rpc(
          "enqueue_manual_customer_push_service",
          {
            p_actor: actorId,
            p_customer: customerId,
            p_message: message,
            p_request_id: requestId,
          },
        );
        if (error) throw error;
        return (data ?? {}) as Record<string, unknown>;
      },
    });
    return json(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (message.includes("push_forbidden") || message.includes("manual_push_forbidden")) {
      return json({ error: "forbidden" }, 403);
    }
    if (
      message.includes("invalid_customer_id") ||
      message.includes("invalid_outbox_id") ||
      message.includes("invalid_overview_filter") ||
      message.includes("invalid_message") ||
      message.includes("unsupported_action")
    ) {
      const code = message.includes("invalid_message") ? "invalid_message" : message;
      return json({ error: code }, 400);
    }
    if (message.includes("no_active_push_subscription")) {
      return json({ error: "no_active_push_subscription" }, 409);
    }
    if (message.includes("push_event_not_found")) {
      return json({ error: "push_event_not_found" }, 404);
    }
    console.error("customer-push-admin error", message);
    return json({ error: "request_failed" }, 500);
  }
}

if (import.meta.main) Deno.serve(handle);
