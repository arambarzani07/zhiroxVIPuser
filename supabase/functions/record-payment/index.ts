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

export type PaymentPushRequest = {
  debtId: string;
  customerId: string;
  amount: number;
};

export type PaymentPushContext = {
  customerId: string;
  marketId: string;
  marketName: string;
  currency: string;
  dollarRate: number;
  remainingIqd: number;
};

export type PaymentPushEnqueue = {
  marketId: string;
  customerId: string;
  eventType: "payment_created";
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

export type PaymentPushDeps = {
  now: () => Date;
  loadContext: (request: PaymentPushRequest) => Promise<PaymentPushContext>;
  enqueuePush: (args: PaymentPushEnqueue) => Promise<void>;
  reportError: (message: string) => void;
};

function paymentRecord(result: unknown): Record<string, unknown> | null {
  if (Array.isArray(result)) {
    const first = result[0];
    return first && typeof first === "object"
      ? first as Record<string, unknown>
      : null;
  }
  return result && typeof result === "object"
    ? result as Record<string, unknown>
    : null;
}

export function canonicalPaymentId(result: unknown): string {
  const record = paymentRecord(result);
  if (!record) return "";

  const directId = String(record.id ?? "").trim();
  if (directId) return directId;

  const payments = record.payments;
  if (!Array.isArray(payments)) return "";
  for (const payment of payments) {
    if (!payment || typeof payment !== "object") continue;
    const id = String((payment as Record<string, unknown>).id ?? "").trim();
    if (id) return id;
  }
  return "";
}

function persistedPaymentAmount(result: unknown, fallback: number): number {
  const record = paymentRecord(result);
  if (!record) return fallback;
  const direct = Number(record.amount);
  if (Number.isFinite(direct) && direct > 0) return direct;
  return fallback;
}

export async function finalizePaymentPush(
  result: unknown,
  request: PaymentPushRequest,
  deps: PaymentPushDeps,
): Promise<unknown> {
  try {
    const paymentId = canonicalPaymentId(result);
    if (!paymentId) throw new Error("payment_push_missing_canonical_id");

    const context = await deps.loadContext(request);
    const isCustomerWide = request.customerId.trim().length > 0;
    const useUsd = !isCustomerWide &&
      context.currency.trim().toUpperCase() === "USD" &&
      context.dollarRate > 0;
    const currency: "IQD" | "USD" = useUsd ? "USD" : "IQD";
    const storedAmount = persistedPaymentAmount(result, request.amount);
    const displayAmount = useUsd
      ? Math.round((storedAmount / context.dollarRate) * 100) / 100
      : storedAmount;

    await deps.enqueuePush({
      marketId: context.marketId,
      customerId: context.customerId,
      eventType: "payment_created",
      eventRecordId: paymentId,
      idempotencyKey: `payment_created:${paymentId}`,
      payload: {
        amount: displayAmount,
        currency,
        remaining_iqd: context.remainingIqd,
        market_name: context.marketName,
        occurred_at: deps.now().toISOString(),
      },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    deps.reportError(`payment push enqueue deferred: ${message}`);
  }

  return result;
}

// Supabase's ungenerated-schema client type narrows arbitrary tables/RPCs to
// `never` during standalone Deno type-checking. Keep this backend-only client
// explicit so the Edge Function can remain testable without generated types.
type AdminClient = any;

async function loadPaymentPushContext(
  admin: AdminClient,
  request: PaymentPushRequest,
): Promise<PaymentPushContext> {
  let resolvedCustomerId = request.customerId.trim();
  let currency = "IQD";
  let dollarRate = 0;

  if (request.debtId.trim().length > 0) {
    const { data: debt, error: debtError } = await admin
      .from("debts")
      .select("customer_id,currency,dollar_rate")
      .eq("id", request.debtId)
      .maybeSingle();
    if (debtError || !debt) {
      throw new Error(`payment_push_debt_context_failed:${debtError?.message ?? "not_found"}`);
    }
    resolvedCustomerId = String(debt.customer_id ?? "").trim();
    currency = String(debt.currency ?? "IQD").trim().toUpperCase();
    dollarRate = Number(debt.dollar_rate ?? 0);
  }

  if (!resolvedCustomerId) throw new Error("payment_push_customer_missing");

  const { data: customer, error: customerError } = await admin
    .from("profiles")
    .select("id,role,admin_id")
    .eq("id", resolvedCustomerId)
    .maybeSingle();
  if (customerError || !customer || customer.role !== "customer") {
    throw new Error(`payment_push_customer_context_failed:${customerError?.message ?? "not_found"}`);
  }

  const marketId = String(customer.admin_id ?? "").trim();
  if (!marketId) throw new Error("payment_push_market_missing");

  const { data: market, error: marketError } = await admin
    .from("profiles")
    .select("id,market_name")
    .eq("id", marketId)
    .eq("role", "admin")
    .maybeSingle();
  if (marketError || !market) {
    throw new Error(`payment_push_market_context_failed:${marketError?.message ?? "not_found"}`);
  }

  const pageSize = 1000;
  let offset = 0;
  let remainingIqd = 0;
  while (true) {
    const { data: debts, error: debtsError } = await admin
      .from("debts")
      .select("remaining")
      .eq("customer_id", resolvedCustomerId)
      .eq("is_deleted", false)
      .range(offset, offset + pageSize - 1);
    if (debtsError) {
      throw new Error(`payment_push_balance_failed:${debtsError.message}`);
    }
    for (const debt of debts ?? []) {
      const remaining = Number(debt.remaining ?? 0);
      if (Number.isFinite(remaining) && remaining > 0) remainingIqd += remaining;
    }
    if ((debts ?? []).length < pageSize) break;
    offset += pageSize;
  }

  return {
    customerId: resolvedCustomerId,
    marketId,
    marketName: String(market.market_name ?? ""),
    currency,
    dollarRate: Number.isFinite(dollarRate) ? dollarRate : 0,
    remainingIqd,
  };
}

async function enqueuePaymentPush(
  admin: AdminClient,
  args: PaymentPushEnqueue,
): Promise<void> {
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

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const secret = envJsonKey("SUPABASE_SECRET_KEYS") ??
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!secret) return json({ error: "server_not_configured" }, 500);

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    if (!token) return json({ error: "authentication_required" }, 401);

    const admin = createClient(url, secret, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: userError } = await admin.auth.getUser(token);
    if (userError || !userData.user) {
      return json({ error: "authentication_required" }, 401);
    }

    const body = await req.json();
    const debtId = String(body.debt_id ?? "").trim();
    const customerId = String(body.customer_id ?? "").trim();
    const amount = Number(body.amount);
    const note = String(body.note ?? "");
    const referenceKind = body.reference_kind == null
      ? null
      : String(body.reference_kind);
    const referenceId = body.reference_id == null
      ? null
      : String(body.reference_id);

    if ((!debtId && !customerId) || (debtId && customerId) ||
        !Number.isFinite(amount) || amount <= 0) {
      return json({ error: "invalid_input" }, 400);
    }

    const pushRequest: PaymentPushRequest = { debtId, customerId, amount };
    const pushDeps: PaymentPushDeps = {
      now: () => new Date(),
      loadContext: (request) => loadPaymentPushContext(admin, request),
      enqueuePush: (args) => enqueuePaymentPush(admin, args),
      reportError: (message) => console.warn(message),
    };

    if (customerId) {
      const { data, error } = await admin.rpc("record_customer_payment_service", {
        p_actor_id: userData.user.id,
        p_customer_id: customerId,
        p_amount: amount,
        p_note: note,
        p_reference_kind: referenceKind,
        p_reference_id: referenceId,
      });
      if (error) {
        const status = error.code === "42501" ? 403 : 400;
        return json({ error: error.message, code: error.code }, status);
      }
      return json(await finalizePaymentPush(data, pushRequest, pushDeps));
    }

    const { data, error } = await admin.rpc("record_payment_service", {
      p_actor_id: userData.user.id,
      p_debt_id: debtId,
      p_amount: amount,
      p_note: note,
      p_reference_kind: referenceKind,
      p_reference_id: referenceId,
    });
    if (error) {
      const status = error.code === "42501" ? 403 : 400;
      return json({ error: error.message, code: error.code }, status);
    }
    return json(await finalizePaymentPush(data, pushRequest, pushDeps));
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : String(error) }, 500);
  }
}

if (import.meta.main) Deno.serve(handle);
