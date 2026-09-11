import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const plans: Record<string, { amount: number; extraEmployee: number }> = {
  monthly: { amount: 10000, extraEmployee: 2000 },
  quarterly: { amount: 25000, extraEmployee: 6000 },
  semiannual: { amount: 45000, extraEmployee: 12000 },
  annual: { amount: 80000, extraEmployee: 24000 },
};

type PaymentRow = {
  id: string;
  fib_payment_id: string;
  amount_iqd: number;
  status: string;
  valid_until?: string | null;
};

type ProviderState = {
  status: "pending" | "paid" | "declined" | "expired" | "cancelled";
  providerStatus: string;
  decliningReason: string | null;
  validUntil: string | null;
  paidAt: string | null;
};

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

function fibBaseUrl() {
  return (Deno.env.get("FIB_BASE_URL") ?? "https://fib.stage.fib.iq")
    .replace(/\/$/, "");
}

async function fibAccessToken(): Promise<string> {
  const clientId = Deno.env.get("FIB_CLIENT_ID");
  const clientSecret = Deno.env.get("FIB_CLIENT_SECRET");
  if (!clientId || !clientSecret) throw new Error("fib_not_configured");

  const body = new URLSearchParams({
    grant_type: "client_credentials",
    client_id: clientId,
    client_secret: clientSecret,
  });
  const response = await fetch(
    `${fibBaseUrl()}/auth/realms/fib-online-shop/protocol/openid-connect/token`,
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body,
    },
  );
  if (!response.ok) throw new Error("fib_auth_failed");
  const data = await response.json();
  if (!data.access_token) throw new Error("fib_auth_failed");
  return String(data.access_token);
}

async function fibRequest(path: string, init: RequestInit = {}) {
  const token = await fibAccessToken();
  const headers = new Headers(init.headers ?? {});
  headers.set("Authorization", `Bearer ${token}`);
  if (!headers.has("Content-Type")) headers.set("Content-Type", "application/json");

  const response = await fetch(`${fibBaseUrl()}${path}`, {
    ...init,
    headers,
  });
  if (!response.ok) throw new Error(`fib_request_failed_${response.status}`);
  if (response.status === 204) return {};

  const text = await response.text();
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch (_) {
    throw new Error("fib_invalid_response");
  }
}

function normalizedStatus(
  value: unknown,
  decliningReason: unknown,
  validUntil: unknown,
): ProviderState["status"] {
  const status = String(value ?? "").toUpperCase();
  const reason = String(decliningReason ?? "").toUpperCase();

  if (status === "PAID") return "paid";
  if (status === "DECLINED") {
    if (reason === "PAYMENT_EXPIRATION") return "expired";
    if (reason === "PAYMENT_CANCELLATION") return "cancelled";
    return "declined";
  }

  // Defensive compatibility for provider variants while still supporting
  // FIB's documented PAID / UNPAID / DECLINED status model.
  if (status === "EXPIRED") return "expired";
  if (status === "CANCELLED" || status === "CANCELED") return "cancelled";

  const expiryMs = Date.parse(String(validUntil ?? ""));
  if (status === "UNPAID" && Number.isFinite(expiryMs) && expiryMs <= Date.now()) {
    return "expired";
  }
  return "pending";
}

function verifyProviderPayment(
  verified: Record<string, unknown>,
  expectedFibPaymentId: string,
  expectedAmountIqd: number,
): ProviderState {
  const paymentId = String(verified.paymentId ?? "");
  if (paymentId !== expectedFibPaymentId) {
    throw new Error("fib_payment_id_mismatch");
  }

  const rawAmount = verified.amount;
  const amount = rawAmount && typeof rawAmount === "object"
    ? rawAmount as Record<string, unknown>
    : {};
  const currency = String(amount.currency ?? "").toUpperCase();
  const providerAmount = Number(amount.amount);
  if (
    currency !== "IQD" ||
    !Number.isFinite(providerAmount) ||
    Math.abs(providerAmount - expectedAmountIqd) > 0.001
  ) {
    throw new Error("fib_amount_mismatch");
  }

  const providerStatus = String(verified.status ?? "").toUpperCase();
  const decliningReason = verified.decliningReason == null
    ? null
    : String(verified.decliningReason);
  const validUntil = verified.validUntil == null
    ? null
    : String(verified.validUntil);
  const paidAt = verified.paidAt == null ? null : String(verified.paidAt);

  return {
    status: normalizedStatus(providerStatus, decliningReason, validUntil),
    providerStatus,
    decliningReason,
    validUntil,
    paidAt,
  };
}

async function activatePayment(
  admin: SupabaseClient,
  payment: PaymentRow,
) {
  const { data, error } = await admin.rpc("activate_fib_subscription_payment", {
    p_local_payment_id: payment.id,
    p_fib_payment_id: payment.fib_payment_id,
  });
  if (error || data !== true) throw new Error("subscription_activation_failed");
}

async function saveProviderState(
  admin: SupabaseClient,
  payment: PaymentRow,
  state: ProviderState,
) {
  const now = new Date().toISOString();
  const patch: Record<string, unknown> = {
    provider_status: state.providerStatus,
    declining_reason: state.decliningReason,
    provider_paid_at: state.paidAt,
    last_verified_at: now,
    updated_at: now,
  };
  if (state.validUntil) patch.valid_until = state.validUntil;

  if (state.status === "paid") {
    const { error } = await admin.from("subscription_payments")
      .update(patch)
      .eq("id", payment.id);
    if (error) throw new Error("payment_state_update_failed");
    return;
  }

  patch.status = state.status;
  const { error } = await admin.from("subscription_payments")
    .update(patch)
    .eq("id", payment.id)
    .neq("status", "paid");
  if (error) throw new Error("payment_state_update_failed");
}

async function reconcileProviderPayment(
  admin: SupabaseClient,
  payment: PaymentRow,
): Promise<ProviderState> {
  const verified = await fibRequest(
    `/protected/v1/payments/${encodeURIComponent(payment.fib_payment_id)}/status`,
  );
  const state = verifyProviderPayment(
    verified as Record<string, unknown>,
    payment.fib_payment_id,
    Number(payment.amount_iqd),
  );

  if (state.status === "paid") {
    await activatePayment(admin, payment);
  }
  await saveProviderState(admin, payment, state);
  return state;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = envJsonKey("SUPABASE_SECRET_KEYS") ??
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!serviceKey) return json({ error: "server_not_configured" }, 500);

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const requestUrl = new URL(req.url);
    const action = requestUrl.searchParams.get("action") ?? "";

    if (action === "callback") {
      const localPaymentId = requestUrl.searchParams.get("payment_id") ?? "";
      const callback = await req.json().catch(() => ({}));
      const fibPaymentId = String(callback.id ?? "");
      if (!localPaymentId || !fibPaymentId) {
        return json({ error: "invalid_callback" }, 406);
      }

      const { data: payment, error: paymentError } = await admin
        .from("subscription_payments")
        .select("id,fib_payment_id,amount_iqd,status,valid_until")
        .eq("id", localPaymentId)
        .eq("fib_payment_id", fibPaymentId)
        .maybeSingle();
      if (paymentError || !payment) return json({ error: "payment_not_found" }, 406);
      if (payment.status === "paid") return new Response(null, { status: 202 });

      await reconcileProviderPayment(admin, payment as PaymentRow);
      return new Response(null, { status: 202 });
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    const { data: userData, error: userError } = await admin.auth.getUser(token);
    if (userError || !userData.user) {
      return json({ error: "authentication_required" }, 401);
    }

    const userId = userData.user.id;
    const { data: profile } = await admin.from("profiles")
      .select("id,role,active,approved")
      .eq("id", userId)
      .maybeSingle();
    if (!profile || profile.role !== "admin" || !profile.active || !profile.approved) {
      return json({ error: "admin_required" }, 403);
    }

    const body = await req.json().catch(() => ({}));
    if (body.action === "create") {
      const plan = String(body.plan ?? "");
      const pricing = plans[plan];
      if (!pricing) return json({ error: "invalid_plan" }, 400);

      const { count: employeeCount } = await admin.from("profiles")
        .select("id", { count: "exact", head: true })
        .eq("admin_id", userId)
        .eq("role", "employee")
        .eq("active", true);
      const extraEmployees = Math.max(0, (employeeCount ?? 0) - 3);
      const amount = pricing.amount + extraEmployees * pricing.extraEmployee;

      const { data: localPayment, error: insertError } = await admin
        .from("subscription_payments")
        .insert({ admin_id: userId, plan, amount_iqd: amount })
        .select("id")
        .single();
      if (insertError || !localPayment) {
        return json({ error: "payment_create_failed" }, 400);
      }

      const callbackUrl = `${supabaseUrl}/functions/v1/fib-subscription-payment?action=callback&payment_id=${encodeURIComponent(localPayment.id)}`;
      let fibPaymentId = "";
      try {
        const created = await fibRequest("/protected/v1/payments", {
          method: "POST",
          body: JSON.stringify({
            monetaryValue: { amount: amount.toFixed(2), currency: "IQD" },
            statusCallbackUrl: callbackUrl,
            description: `ZHIROX ${plan} subscription`,
          }),
        }) as Record<string, unknown>;

        fibPaymentId = String(created.paymentId ?? "");
        if (!fibPaymentId) throw new Error("fib_invalid_create_response");

        const { error: updateError } = await admin.from("subscription_payments").update({
          fib_payment_id: fibPaymentId,
          readable_code: created.readableCode ?? null,
          valid_until: created.validUntil ?? null,
          updated_at: new Date().toISOString(),
        }).eq("id", localPayment.id);
        if (updateError) {
          try {
            await fibRequest(
              `/protected/v1/payments/${encodeURIComponent(fibPaymentId)}/cancel`,
              { method: "POST" },
            );
          } catch (_) {}
          await admin.from("subscription_payments").delete().eq("id", localPayment.id);
          throw new Error("payment_create_failed");
        }

        return json({
          local_payment_id: localPayment.id,
          fib_payment_id: fibPaymentId,
          amount_iqd: amount,
          readable_code: created.readableCode,
          valid_until: created.validUntil,
          personal_app_link: created.personalAppLink,
          business_app_link: created.businessAppLink,
          corporate_app_link: created.corporateAppLink,
          qr_code: created.qrCode,
        });
      } catch (error) {
        if (!fibPaymentId) {
          await admin.from("subscription_payments").delete().eq("id", localPayment.id);
        }
        throw error;
      }
    }

    if (body.action === "status") {
      const localPaymentId = String(body.local_payment_id ?? "");
      const { data: payment, error: paymentError } = await admin
        .from("subscription_payments")
        .select("id,fib_payment_id,amount_iqd,status,valid_until")
        .eq("id", localPaymentId)
        .eq("admin_id", userId)
        .maybeSingle();
      if (paymentError || !payment?.fib_payment_id) {
        return json({ error: "payment_not_found" }, 404);
      }

      if (payment.status === "paid") return json({ status: "paid" });
      if (["declined", "expired", "cancelled"].includes(payment.status)) {
        return json({ status: payment.status });
      }

      const state = await reconcileProviderPayment(admin, payment as PaymentRow);
      return json({ status: state.status });
    }

    return json({ error: "invalid_action" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const providerError = message.startsWith("fib_");
    const activationError = message === "subscription_activation_failed" ||
      message === "payment_state_update_failed";
    return json(
      { error: providerError || activationError ? message : "payment_failed" },
      500,
    );
  }
});
