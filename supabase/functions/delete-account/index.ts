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

function chunks<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let index = 0; index < items.length; index += size) {
    out.push(items.slice(index, index + size));
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const secret = envJsonKey("SUPABASE_SECRET_KEYS") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!secret) return json({ error: "server_not_configured" }, 500);

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    if (!token) return json({ error: "authentication_required" }, 401);

    const admin = createClient(url, secret, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: authData, error: authError } = await admin.auth.getUser(token);
    const requester = authData.user ?? null;
    if (authError || !requester) return json({ error: "authentication_required" }, 401);

    const { data: requesterProfile, error: requesterProfileError } = await admin
      .from("profiles")
      .select("id, role, active, is_system_owner")
      .eq("id", requester.id)
      .maybeSingle();
    if (requesterProfileError) return json({ error: requesterProfileError.message }, 400);
    if (!requesterProfile?.active || requesterProfile.is_system_owner !== true) {
      return json({ error: "system_owner_required" }, 403);
    }

    const body = await req.json();
    const targetId = String(body.user_id ?? "").trim();
    if (!targetId) return json({ error: "invalid_input" }, 400);

    const { data: target, error: targetError } = await admin
      .from("profiles")
      .select("id, role, is_system_owner")
      .eq("id", targetId)
      .maybeSingle();
    if (targetError) return json({ error: targetError.message }, 400);
    if (!target || target.role !== "admin") return json({ error: "admin_not_found" }, 404);
    if (target.is_system_owner === true) return json({ error: "cannot_delete_system_owner" }, 403);

    // Privacy boundary: System Owner manages the platform account lifecycle,
    // not the market's internal content. Hard deletion would inspect and erase
    // customers, debts, receipts, and other tenant data, so it is disabled.
    // Use lifecycle suspension/archive controls instead.
    return json({ error: "owner_market_delete_disabled" }, 409);

  } catch (error) {
    return json({ error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
