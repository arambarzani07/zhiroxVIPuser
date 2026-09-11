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

async function isOperational(admin: any, profile: any): Promise<boolean> {
  if (!profile || profile.active !== true || profile.approved !== true) return false;
  if (profile.is_system_owner === true) return true;

  const tenantId = profile.role === "admin" ? profile.id : profile.admin_id;
  if (!tenantId) return false;
  const tenant = profile.role === "admin"
    ? profile
    : (await admin
        .from("profiles")
        .select("id, active, approved, subscription_end")
        .eq("id", tenantId)
        .eq("role", "admin")
        .maybeSingle()).data;
  if (!tenant || tenant.active !== true || tenant.approved !== true) return false;

  const subscriptionEnd = tenant.subscription_end
    ? Date.parse(String(tenant.subscription_end))
    : null;
  return subscriptionEnd === null ||
    (Number.isFinite(subscriptionEnd) && subscriptionEnd >= Date.now());
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const secret = envJsonKey("SUPABASE_SECRET_KEYS") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!secret) return json({ error: "server_not_configured" }, 500);

    const admin = createClient(url, secret, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    if (!token) return json({ error: "authentication_required" }, 401);

    const { data: authData, error: authError } = await admin.auth.getUser(token);
    if (authError || !authData.user) return json({ error: "authentication_required" }, 401);

    const body = await req.json();
    const targetId = String(body.user_id ?? "").trim();
    const incoming = body.data && typeof body.data === "object" ? body.data : {};
    if (!targetId) return json({ error: "invalid_input" }, 400);

    const [{ data: requester, error: requesterError }, { data: target, error: targetError }] =
      await Promise.all([
        admin.from("profiles").select("*").eq("id", authData.user.id).maybeSingle(),
        admin.from("profiles").select("*").eq("id", targetId).maybeSingle(),
      ]);

    if (requesterError) return json({ error: requesterError.message }, 400);
    if (targetError) return json({ error: targetError.message }, 400);
    if (!requester || !target) return json({ error: "profile_not_found" }, 404);
    if (!(await isOperational(admin, requester))) {
      return json({ error: "forbidden" }, 403);
    }

    const isSelf = requester.id === target.id;
    const sameTenantMember =
      requester.role === "admin" &&
      (target.role === "employee" || target.role === "customer") &&
      target.admin_id === requester.id;
    if (!isSelf && !sameTenantMember) return json({ error: "forbidden" }, 403);

    const selfFields = new Set(["name", "father_name", "grandfather_name", "phone"]);
    if (requester.role === "admin") selfFields.add("market_name");

    const tenantAdminFields = new Set([
      "name",
      "father_name",
      "grandfather_name",
      "phone",
      "approved",
      "active",
      "debt_limit",
      "debt_duration",
      "can_add_customers",
      "can_set_debt_limit",
      "can_set_due_date",
      "can_edit_debts",
      "can_send_notifications",
    ]);

    const allowed = isSelf ? selfFields : tenantAdminFields;
    const update: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(incoming)) {
      if (allowed.has(key)) update[key] = value;
    }

    if (typeof update.phone === "string") {
      const phone = update.phone.trim();
      if (!phone) return json({ error: "invalid_phone" }, 400);
      const { data: duplicate, error: duplicateError } = await admin
        .from("profiles")
        .select("id")
        .eq("phone", phone)
        .neq("id", targetId)
        .maybeSingle();
      if (duplicateError) return json({ error: duplicateError.message }, 400);
      if (duplicate) return json({ error: "phone_exists" }, 409);
      update.phone = phone;
    }

    if (Object.keys(update).length === 0) return json({ user: target });

    const syncAuthIdentity = Object.hasOwn(update, "phone") || Object.hasOwn(update, "name");
    let previousAuthEmail: string | undefined;
    let previousAuthMetadata: Record<string, unknown> | undefined;

    if (syncAuthIdentity) {
      const { data: targetAuthData, error: targetAuthError } =
        await admin.auth.admin.getUserById(targetId);
      if (targetAuthError || !targetAuthData.user) {
        return json({ error: targetAuthError?.message ?? "auth_user_not_found" }, 400);
      }

      previousAuthEmail = targetAuthData.user.email;
      previousAuthMetadata = { ...(targetAuthData.user.user_metadata ?? {}) };
      const nextPhone = String(update.phone ?? target.phone ?? "").trim();
      const nextName = String(update.name ?? target.name ?? "").trim();
      const authUpdate: Record<string, unknown> = {
        user_metadata: {
          ...previousAuthMetadata,
          name: nextName,
          phone: nextPhone,
          role: target.role,
          admin_id: target.admin_id,
        },
      };
      if (Object.hasOwn(update, "phone")) {
        authUpdate.email = `${nextPhone}@zhirox.local`;
      }

      const { error: userError } = await admin.auth.admin.updateUserById(targetId, authUpdate);
      if (userError) return json({ error: userError.message }, 400);
    }

    update.updated_at = new Date().toISOString();
    const { data: updated, error: updateError } = await admin
      .from("profiles")
      .update(update)
      .eq("id", targetId)
      .select()
      .single();

    if (updateError) {
      if (syncAuthIdentity) {
        try {
          const rollback: Record<string, unknown> = {
            user_metadata: previousAuthMetadata ?? {},
          };
          if (previousAuthEmail) rollback.email = previousAuthEmail;
          await admin.auth.admin.updateUserById(targetId, rollback);
        } catch (_) {
          // Best-effort auth rollback. The profile update remains authoritative.
        }
      }
      return json({ error: updateError.message }, 400);
    }

    return json({ user: updated });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
