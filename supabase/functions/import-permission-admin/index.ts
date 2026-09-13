import { createClient } from "npm:@supabase/supabase-js@2.116.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const secret = envJsonKey("SUPABASE_SECRET_KEYS") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!secret) return json({ error: "server_not_configured" }, 500);
    const admin = createClient(url, secret, { auth: { persistSession: false, autoRefreshToken: false } });

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    if (!token) return json({ error: "unauthorized" }, 401);
    const { data: userData } = await admin.auth.getUser(token);
    const user = userData.user;
    if (!user) return json({ error: "unauthorized" }, 401);

    const { data: owner } = await admin.from("profiles")
      .select("id,is_system_owner,active")
      .eq("id", user.id)
      .maybeSingle();
    if (!owner || owner.is_system_owner !== true || owner.active !== true) {
      return json({ error: "system_owner_required" }, 403);
    }

    const body = await req.json();
    const action = String(body.action ?? "list");
    if (action === "list") {
      const { data, error } = await admin.from("profiles")
        .select("id,name,market_name,phone,active,approved,subscription_end,can_import_data")
        .eq("role", "admin")
        .eq("is_system_owner", false)
        .order("created_at", { ascending: false });
      if (error) return json({ error: error.message }, 400);
      return json({ admins: data ?? [] });
    }

    if (action === "set") {
      const adminId = String(body.admin_id ?? "").trim();
      const allowed = body.allowed === true;
      if (!adminId) return json({ error: "invalid_input" }, 400);
      const { data, error } = await admin.from("profiles")
        .update({ can_import_data: allowed, updated_at: new Date().toISOString() })
        .eq("id", adminId)
        .eq("role", "admin")
        .eq("is_system_owner", false)
        .select("id,can_import_data")
        .maybeSingle();
      if (error) return json({ error: error.message }, 400);
      if (!data) return json({ error: "admin_not_found" }, 404);
      return json({ ok: true, admin: data });
    }

    return json({ error: "unsupported_action" }, 400);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "internal_error" }, 500);
  }
});
