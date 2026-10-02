import { createClient } from "npm:@supabase/supabase-js@2.116.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
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

function serviceKey(): string {
  const raw = env("SUPABASE_SECRET_KEYS");
  if (raw) {
    try {
      const parsed = JSON.parse(raw) as Record<string, string>;
      const value = parsed.default ?? Object.values(parsed)[0];
      if (value) return String(value).trim();
    } catch (_) {}
  }
  return env("SUPABASE_SERVICE_ROLE_KEY");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const supabaseUrl = env("SUPABASE_URL");
  const secret = serviceKey();
  if (!supabaseUrl || !secret) return json({ error: "server_not_configured" }, 500);

  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : "";
  if (!bearer) return json({ error: "authentication_required" }, 401);

  const admin = createClient(supabaseUrl, secret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: authData, error: authError } = await admin.auth.getUser(bearer);
  if (authError || !authData.user) return json({ error: "authentication_required" }, 401);

  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("id,active,approved,is_system_owner")
    .eq("id", authData.user.id)
    .maybeSingle();
  if (profileError) return json({ error: "profile_lookup_failed" }, 500);
  if (!profile || profile.active !== true || profile.approved !== true || profile.is_system_owner !== true) {
    return json({ error: "system_owner_required" }, 403);
  }

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch (_) {
    body = {};
  }

  const search = String(body.search ?? "").trim().slice(0, 120);
  const health = String(body.health ?? "all").trim().toLowerCase();
  const pageRaw = Number(body.page ?? 1);
  const perPageRaw = Number(body.per_page ?? 30);
  const page = Number.isFinite(pageRaw) ? Math.max(1, Math.trunc(pageRaw)) : 1;
  const perPage = Number.isFinite(perPageRaw) ? Math.min(100, Math.max(1, Math.trunc(perPageRaw))) : 30;

  if (!["all", "healthy", "degraded", "attention"].includes(health)) {
    return json({ error: "invalid_health_filter" }, 400);
  }

  const { data, error } = await admin.rpc("get_system_owner_autopilot_overview_v2_service", {
    p_search: search,
    p_health: health,
    p_page: page,
    p_per_page: perPage,
  });

  if (error) {
    console.error("owner-autopilot-dashboard rpc error", error.code ?? "rpc_failed");
    return json({ error: "dashboard_unavailable" }, 500);
  }
  if (!data || typeof data !== "object") return json({ error: "invalid_dashboard_response" }, 500);

  return json(data);
});
