import { createClient } from "npm:@supabase/supabase-js@2.116.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

function env(name: string): string {
  return (Deno.env.get(name) ?? "").trim();
}

function serviceKey(): string | null {
  const raw = env("SUPABASE_SECRET_KEYS");
  if (raw) {
    try {
      const keys = JSON.parse(raw) as Record<string, string>;
      const value = keys.default ?? Object.values(keys)[0];
      if (value) return String(value).trim();
    } catch (_) {
      return raw;
    }
  }
  return env("SUPABASE_SERVICE_ROLE_KEY") || null;
}

async function loadBotToken(service: any): Promise<string> {
  const configured = env("TELEGRAM_BOT_TOKEN");
  if (configured) return configured;
  const { data, error } = await service.rpc("get_telegram_runtime_config_service");
  if (error) return "";
  const row = Array.isArray(data) ? data[0] : data;
  return String(row?.bot_token ?? "").trim();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = env("SUPABASE_URL");
  const key = serviceKey();
  if (!url || !key) return json({ error: "server_not_configured" }, 500);

  const token = /^Bearer (.+)$/i.exec(req.headers.get("Authorization") ?? "")?.[1];
  if (!token) return json({ error: "unauthorized" }, 401);

  const service = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: auth, error: authError } = await service.auth.getUser(token);
  if (authError || !auth.user) return json({ error: "unauthorized" }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
    if (!body || typeof body !== "object" || Array.isArray(body)) throw Error();
  } catch (_) {
    return json({ error: "invalid_json" }, 400);
  }

  const customerId = body.customer_id;
  const message = body.message;
  if (
    typeof customerId !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(customerId) ||
    typeof message !== "string" ||
    !message.trim() ||
    message.length > 1024
  ) {
    return json({ error: "invalid_input" }, 400);
  }

  const { data: sender, error: senderError } = await service
    .from("profiles")
    .select("id,role,admin_id,active,approved,can_send_notifications")
    .eq("id", auth.user.id)
    .maybeSingle();
  if (senderError) return json({ error: "profile_lookup_failed" }, 500);
  if (
    !sender ||
    !sender.active ||
    !sender.approved ||
    !(
      sender.role === "admin" ||
      (sender.role === "employee" && sender.can_send_notifications === true)
    )
  ) {
    return json({ error: "forbidden" }, 403);
  }

  const tenantId = sender.role === "admin" ? sender.id : sender.admin_id;
  if (!tenantId) return json({ error: "forbidden" }, 403);

  const { data: tenant, error: tenantError } = await service
    .from("profiles")
    .select("id,active,approved,subscription_end")
    .eq("id", tenantId)
    .eq("role", "admin")
    .maybeSingle();
  if (tenantError) return json({ error: "tenant_lookup_failed" }, 500);
  if (
    !tenant ||
    !tenant.active ||
    !tenant.approved ||
    (tenant.subscription_end && Date.parse(tenant.subscription_end) < Date.now())
  ) {
    return json({ error: "tenant_inactive" }, 403);
  }

  const { data: customer, error: customerError } = await service
    .from("profiles")
    .select("id,admin_id,active,approved")
    .eq("id", customerId)
    .eq("role", "customer")
    .maybeSingle();
  if (customerError) return json({ error: "customer_lookup_failed" }, 500);
  if (
    !customer ||
    customer.admin_id !== tenantId ||
    !customer.active ||
    !customer.approved
  ) {
    return json({ error: "customer_not_found" }, 404);
  }

  const botToken = await loadBotToken(service);
  if (!botToken) {
    return json({ sent: false, reason: "telegram_service_not_configured" });
  }

  const { data: connections, error: connectionError } = await service.rpc(
    "get_telegram_connection_for_service",
    { p_user_id: customerId },
  );
  if (connectionError) {
    return json({ error: "telegram_connection_lookup_failed" }, 500);
  }
  const chatId = String(connections?.[0]?.chat_id ?? "").trim();
  if (!chatId) {
    return json({ sent: false, reason: "customer_telegram_not_connected" });
  }

  try {
    const response = await fetch(
      `https://api.telegram.org/bot${botToken}/sendMessage`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          chat_id: chatId,
          text: message.trim(),
          disable_web_page_preview: true,
        }),
        signal: AbortSignal.timeout(8000),
      },
    );
    if (!response.ok) {
      return json({ sent: false, reason: "telegram_delivery_failed" }, 502);
    }
    return json({ sent: true, delivery: "official_bot" });
  } catch (_) {
    return json({ sent: false, reason: "telegram_unavailable" }, 502);
  }
});
