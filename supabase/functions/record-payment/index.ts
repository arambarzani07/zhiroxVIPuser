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

Deno.serve(async (req) => {
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
    const amount = Number(body.amount);
    const note = String(body.note ?? "");
    const referenceKind = body.reference_kind == null
      ? null
      : String(body.reference_kind);
    const referenceId = body.reference_id == null
      ? null
      : String(body.reference_id);
    if (!debtId || !Number.isFinite(amount) || amount <= 0) {
      return json({ error: "invalid_input" }, 400);
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
    return json(data);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
