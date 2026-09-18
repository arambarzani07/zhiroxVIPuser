import { createClient } from "npm:@supabase/supabase-js@2.116.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
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
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const secret =
      envJsonKey("SUPABASE_SECRET_KEYS") ??
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!secret) return json({ error: "server_not_configured" }, 500);

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    if (!token) return json({ error: "authentication_required" }, 401);

    const admin = createClient(url, secret, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: requesterData, error: requesterError } =
      await admin.auth.getUser(token);
    const requester = requesterData.user;
    if (requesterError || !requester) {
      return json({ error: "authentication_required" }, 401);
    }

    const { data: requesterProfile, error: profileError } = await admin
      .from("profiles")
      .select("id,is_system_owner,active,approved")
      .eq("id", requester.id)
      .maybeSingle();
    if (profileError) return json({ error: profileError.message }, 400);
    if (
      !requesterProfile ||
      requesterProfile.is_system_owner !== true ||
      requesterProfile.active !== true ||
      requesterProfile.approved !== true
    ) {
      return json({ error: "system_owner_required" }, 403);
    }

    const body = await req.json();
    const adminId = String(body.admin_id ?? "").trim();
    const newPassword = String(body.new_password ?? "");
    const reason = String(body.reason ?? "").trim().slice(0, 500);

    if (!adminId || newPassword.length < 8 || newPassword.length > 128) {
      return json({ error: "invalid_input" }, 400);
    }

    const { data: target, error: targetError } = await admin
      .from("profiles")
      .select("id,role,is_system_owner,active,approved")
      .eq("id", adminId)
      .eq("role", "admin")
      .eq("is_system_owner", false)
      .maybeSingle();
    if (targetError) return json({ error: targetError.message }, 400);
    if (!target) return json({ error: "admin_not_found" }, 404);

    const { error: passwordError } = await admin.auth.admin.updateUserById(
      adminId,
      { password: newPassword },
    );
    if (passwordError) {
      return json({ error: passwordError.message }, 400);
    }

    const { data: recoveryResult, error: recoveryError } = await admin.rpc(
      "complete_system_owner_admin_recovery_service",
      {
        p_actor_id: requester.id,
        p_admin_id: adminId,
        p_reason: reason,
      },
    );
    if (recoveryError) {
      return json(
        {
          error: "recovery_finalize_failed",
          detail: recoveryError.message,
          password_updated: true,
        },
        500,
      );
    }

    return json({
      ok: true,
      admin_id: adminId,
      revoked_session_count:
        Number(recoveryResult?.revoked_session_count ?? 0) || 0,
      reset_device_count:
        Number(recoveryResult?.reset_device_count ?? 0) || 0,
    });
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});
