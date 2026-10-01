import { createClient } from "npm:@supabase/supabase-js@2.116.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
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

function serviceKey(): string {
  const legacy = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
  if (legacy) return legacy;
  const modern = (Deno.env.get("SUPABASE_SECRET_KEYS") ?? "").trim();
  if (!modern) return "";
  try {
    const parsed = JSON.parse(modern) as Record<string, string>;
    return String(parsed.default ?? Object.values(parsed)[0] ?? "").trim();
  } catch (_) {
    return modern;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = (Deno.env.get("SUPABASE_URL") ?? "").trim();
  const secret = serviceKey();
  if (!url || !secret) return json({ error: "server_not_configured" }, 500);

  const authorization = (req.headers.get("Authorization") ?? "").trim();
  const token = authorization.toLowerCase().startsWith("bearer ")
    ? authorization.slice(7).trim()
    : "";
  if (!token) return json({ error: "not_authenticated" }, 401);

  const admin = createClient(url, secret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await admin.auth.getUser(token);
  const user = userData?.user;
  if (userError || !user) return json({ error: "not_authenticated" }, 401);

  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("id, role, active, approved")
    .eq("id", user.id)
    .eq("role", "admin")
    .eq("active", true)
    .eq("approved", true)
    .maybeSingle();

  if (profileError) return json({ error: "profile_check_failed" }, 500);
  if (!profile) return json({ error: "admin_required" }, 403);

  const { data, error } = await admin.rpc("get_tenant_autopilot_dashboard_service", {
    p_market_id: user.id,
  });
  if (error) {
    console.error("autopilot-dashboard", error.message);
    return json({ error: "dashboard_unavailable" }, 500);
  }

  return json(data ?? {});
});
