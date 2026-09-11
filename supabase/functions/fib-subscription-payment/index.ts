import { createClient } from "npm:@supabase/supabase-js@2.116.0";

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
    { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body },
  );
  if (!response.ok) throw new Error("fib_auth_failed");
  const data = await response.json();
  if (!data.access_token) throw new Error("fib_auth_failed");
  return String(data.access_token);
}

async function fibRequest(path: string, init: RequestInit = {}) {
  const token = await fibAccessToken();
  const response = await fetch(`${fibBaseUrl()}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${token}`,
      ...(init.headers ?? {}),
    },
  });
  if (!response.ok) throw new Error(`fib_request_failed_${response.status}`);
  return await response.json();
}

function normalizedStatus(value: unknown) {
  const status = String(value ?? "").toUpperCase();
  if (status === "PAID") return "paid";
  if (status === "DECLINED") return "declined";
  if (status === "EXPIRED") return "expired";
  if (status === "CANCELLED" || status === "CANCELED") return "cancelled";
  return "pending";
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
      if (!localPaymentId || !fibPaymentId) return json({ error: "invalid_callback" }, 406);
      const { data: payment } = await admin
        .from("subscription_payments")
        .select("id,fib_payment_id")
        .eq("id", localPaymentId)
        .eq("fib_payment_id", fibPaymentId)
        .maybeSingle();
      if (!payment) return json({ error: "payment_not_found" }, 406);
      const verified = await fibRequest(`/protected/v1/payments/${fibPaymentId}/status`);
      const status = normalizedStatus(verified.status);
      if (status === "paid") {
        await admin.rpc("activate_fib_subscription_payment", {
          p_local_payment_id: localPaymentId,
          p_fib_payment_id: fibPaymentId,
        });
      } else {
        await admin.from("subscription_payments").update({ status, updated_at: new Date().toISOString() })
          .eq("id", localPaymentId).neq("status", "paid");
      }
      return new Response(null, { status: 202 });
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    const { data: userData, error: userError } = await admin.auth.getUser(token);
    if (userError || !userData.user) return json({ error: "authentication_required" }, 401);
    const userId = userData.user.id;
    const { data: profile } = await admin.from("profiles")
      .select("id,role,active,approved")
      .eq("id", userId).maybeSingle();
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
        .eq("admin_id", userId).eq("role", "employee").eq("active", true);
      const extraEmployees = Math.max(0, (employeeCount ?? 0) - 3);
      const amount = pricing.amount + extraEmployees * pricing.extraEmployee;
      const { data: localPayment, error: insertError } = await admin
        .from("subscription_payments")
        .insert({ admin_id: userId, plan, amount_iqd: amount })
        .select("id").single();
      if (insertError || !localPayment) return json({ error: "payment_create_failed" }, 400);
      const callbackUrl = `${supabaseUrl}/functions/v1/fib-subscription-payment?action=callback&payment_id=${localPayment.id}`;
      try {
        const created = await fibRequest("/protected/v1/payments", {
          method: "POST",
          body: JSON.stringify({
            monetaryValue: { amount: amount.toFixed(2), currency: "IQD" },
            statusCallbackUrl: callbackUrl,
            description: `ZHIROX ${plan} subscription`,
          }),
        });
        await admin.from("subscription_payments").update({
          fib_payment_id: created.paymentId,
          readable_code: created.readableCode,
          valid_until: created.validUntil,
          updated_at: new Date().toISOString(),
        }).eq("id", localPayment.id);
        return json({
          local_payment_id: localPayment.id,
          fib_payment_id: created.paymentId,
          amount_iqd: amount,
          readable_code: created.readableCode,
          valid_until: created.validUntil,
          personal_app_link: created.personalAppLink,
          business_app_link: created.businessAppLink,
          corporate_app_link: created.corporateAppLink,
          qr_code: created.qrCode,
        });
      } catch (error) {
        await admin.from("subscription_payments").delete().eq("id", localPayment.id);
        throw error;
      }
    }

    if (body.action === "status") {
      const localPaymentId = String(body.local_payment_id ?? "");
      const { data: payment } = await admin.from("subscription_payments")
        .select("id,fib_payment_id,status")
        .eq("id", localPaymentId).eq("admin_id", userId).maybeSingle();
      if (!payment?.fib_payment_id) return json({ error: "payment_not_found" }, 404);
      if (payment.status === "paid") return json({ status: "paid" });
      const verified = await fibRequest(`/protected/v1/payments/${payment.fib_payment_id}/status`);
      const status = normalizedStatus(verified.status);
      if (status === "paid") {
        await admin.rpc("activate_fib_subscription_payment", {
          p_local_payment_id: payment.id,
          p_fib_payment_id: payment.fib_payment_id,
        });
      } else {
        await admin.from("subscription_payments").update({ status, updated_at: new Date().toISOString() })
          .eq("id", payment.id).neq("status", "paid");
      }
      return json({ status });
    }

    return json({ error: "invalid_action" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return json({ error: message.startsWith("fib_") ? message : "payment_failed" }, 500);
  }
});
