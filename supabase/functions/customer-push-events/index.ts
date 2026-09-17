import { createClient } from "npm:@supabase/supabase-js@2.116.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

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

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export type DebtPushContext = {
  id: string;
  customerId: string;
  createdBy: string;
  marketId: string;
  marketName: string;
  amount: number;
  amountUsd: number;
  currency: string;
  dollarRate: number;
  remainingIqd: number;
  occurredAt: string;
  deleted: boolean;
  legacyLinked: boolean;
  syncLinked: boolean;
};

export type DebtPushEnqueue = {
  marketId: string;
  customerId: string;
  eventType: "debt_created";
  eventRecordId: string;
  idempotencyKey: string;
  payload: {
    amount: number;
    currency: "IQD" | "USD";
    remaining_iqd: number;
    market_name: string;
    occurred_at: string;
  };
};

export type DebtPushDeps = {
  loadDebt: (debtId: string) => Promise<DebtPushContext | null>;
  actorCanAccess: (actorId: string, marketId: string) => Promise<boolean>;
  enqueuePush: (args: DebtPushEnqueue) => Promise<void>;
};

export function isLiveDebtEligible(input: {
  deleted: boolean;
  legacyLinked: boolean;
  syncLinked: boolean;
  createdAt: string;
  now: Date;
}): boolean {
  if (input.deleted || input.legacyLinked || input.syncLinked) return false;
  const createdMs = Date.parse(input.createdAt);
  if (!Number.isFinite(createdMs)) return false;
  const ageMs = input.now.getTime() - createdMs;
  return ageMs >= 2 * 60 * 1000 && ageMs <= 24 * 60 * 60 * 1000;
}

function requireUuid(value: unknown): string {
  const id = String(value ?? "").trim();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) {
    throw new Error("invalid_debt_id");
  }
  return id;
}

export async function handleDebtPushAction(
  body: Record<string, unknown>,
  actorId: string,
  deps: DebtPushDeps,
): Promise<Record<string, unknown>> {
  if (String(body.action ?? "") !== "enqueue_debt") {
    throw new Error("unsupported_action");
  }
  const debtId = requireUuid(body.debt_id);
  const debt = await deps.loadDebt(debtId);
  if (!debt) throw new Error("debt_not_found");
  if (debt.createdBy !== actorId) throw new Error("forbidden");
  if (!await deps.actorCanAccess(actorId, debt.marketId)) {
    throw new Error("forbidden");
  }
  if (debt.deleted) return { enqueued: false, reason: "deleted" };
  if (debt.legacyLinked || debt.syncLinked) {
    return { enqueued: false, reason: "non_live_source" };
  }

  const normalizedCurrency = debt.currency.trim().toUpperCase();
  const useUsd = normalizedCurrency === "USD" && debt.dollarRate > 0;
  const currency: "IQD" | "USD" = useUsd ? "USD" : "IQD";
  const displayAmount = useUsd
    ? (debt.amountUsd > 0
      ? debt.amountUsd
      : Math.round((debt.amount / debt.dollarRate) * 100) / 100)
    : debt.amount;

  await deps.enqueuePush({
    marketId: debt.marketId,
    customerId: debt.customerId,
    eventType: "debt_created",
    eventRecordId: debt.id,
    idempotencyKey: `debt_created:${debt.id}`,
    payload: {
      amount: displayAmount,
      currency,
      remaining_iqd: debt.remainingIqd,
      market_name: debt.marketName,
      occurred_at: debt.occurredAt,
    },
  });
  return { enqueued: true };
}

type AdminClient = any;

async function sumCustomerRemainingIqd(admin: AdminClient, customerId: string) {
  const pageSize = 1000;
  let offset = 0;
  let total = 0;
  while (true) {
    const { data, error } = await admin.from("debts")
      .select("remaining")
      .eq("customer_id", customerId)
      .eq("is_deleted", false)
      .range(offset, offset + pageSize - 1);
    if (error) throw error;
    for (const row of data ?? []) {
      const remaining = Number(row.remaining ?? 0);
      if (Number.isFinite(remaining) && remaining > 0) total += remaining;
    }
    if ((data ?? []).length < pageSize) return total;
    offset += pageSize;
  }
}

async function hasLegacyDebtLink(admin: AdminClient, debtId: string) {
  const { count, error } = await admin.from("legacy_import_links")
    .select("target_id", { count: "exact", head: true })
    .eq("entity_kind", "debt")
    .eq("target_id", debtId);
  if (error) throw error;
  return (count ?? 0) > 0;
}

async function hasSyncDebtLink(admin: AdminClient, debtId: string) {
  const { count, error } = await admin.from("daftar_sync_seen")
    .select("target_id", { count: "exact", head: true })
    .eq("entity_kind", "debt")
    .eq("target_id", debtId);
  if (error) throw error;
  return (count ?? 0) > 0;
}

async function loadDebtContext(
  admin: AdminClient,
  debtId: string,
): Promise<DebtPushContext | null> {
  const { data: debt, error: debtError } = await admin.from("debts")
    .select("id,customer_id,created_by,amount,amount_usd,currency,dollar_rate,is_deleted,custom_date,created_at")
    .eq("id", debtId)
    .maybeSingle();
  if (debtError) throw debtError;
  if (!debt) return null;

  const customerId = String(debt.customer_id ?? "").trim();
  const { data: customer, error: customerError } = await admin.from("profiles")
    .select("id,role,admin_id")
    .eq("id", customerId)
    .maybeSingle();
  if (customerError) throw customerError;
  if (!customer || customer.role !== "customer") return null;

  const marketId = String(customer.admin_id ?? "").trim();
  const { data: market, error: marketError } = await admin.from("profiles")
    .select("id,market_name")
    .eq("id", marketId)
    .eq("role", "admin")
    .maybeSingle();
  if (marketError) throw marketError;
  if (!market) return null;

  const [legacyLinked, syncLinked, remainingIqd] = await Promise.all([
    hasLegacyDebtLink(admin, debtId),
    hasSyncDebtLink(admin, debtId),
    sumCustomerRemainingIqd(admin, customerId),
  ]);

  return {
    id: String(debt.id),
    customerId,
    createdBy: String(debt.created_by ?? ""),
    marketId,
    marketName: String(market.market_name ?? ""),
    amount: Number(debt.amount ?? 0),
    amountUsd: Number(debt.amount_usd ?? 0),
    currency: String(debt.currency ?? "IQD"),
    dollarRate: Number(debt.dollar_rate ?? 0),
    remainingIqd,
    occurredAt: String(debt.custom_date ?? debt.created_at ?? new Date().toISOString()),
    deleted: debt.is_deleted === true,
    legacyLinked,
    syncLinked,
  };
}

async function actorCanAccessMarket(
  admin: AdminClient,
  actorId: string,
  marketId: string,
): Promise<boolean> {
  const { data: actor, error } = await admin.from("profiles")
    .select("id,role,admin_id,active,approved")
    .eq("id", actorId)
    .maybeSingle();
  if (error || !actor || actor.active !== true || actor.approved !== true) return false;
  const actorMarket = actor.role === "admin"
    ? String(actor.id)
    : actor.role === "employee"
    ? String(actor.admin_id ?? "")
    : "";
  return actorMarket === marketId;
}

async function enqueueDebtPush(admin: AdminClient, args: DebtPushEnqueue) {
  const { error } = await admin.rpc("enqueue_customer_push_event_service", {
    p_market_id: args.marketId,
    p_customer_id: args.customerId,
    p_event_type: args.eventType,
    p_event_record_id: args.eventRecordId,
    p_idempotency_key: args.idempotencyKey,
    p_payload: args.payload,
  });
  if (error) throw error;
}

async function serve(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? envJsonKey("SUPABASE_SECRET_KEYS");
  if (!url || !secret) return json({ error: "server_not_configured" }, 500);

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!token) return json({ error: "authentication_required" }, 401);

  const admin = createClient(url, secret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData.user) return json({ error: "authentication_required" }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "invalid_json" }, 400);
  }

  try {
    const result = await handleDebtPushAction(body, userData.user.id, {
      loadDebt: (debtId) => loadDebtContext(admin, debtId),
      actorCanAccess: (actorId, marketId) => actorCanAccessMarket(admin, actorId, marketId),
      enqueuePush: (args) => enqueueDebtPush(admin, args),
    });
    return json(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (message === "forbidden") return json({ error: "forbidden" }, 403);
    if (message === "debt_not_found") return json({ error: "debt_not_found" }, 404);
    if (message === "invalid_debt_id" || message === "unsupported_action") {
      return json({ error: message }, 400);
    }
    console.error("customer-push-events error", message);
    return json({ error: "request_failed" }, 500);
  }
}

if (import.meta.main) Deno.serve(serve);
