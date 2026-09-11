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
    const secret = envJsonKey("SUPABASE_SECRET_KEYS") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!secret) return json({ error: "server_not_configured" }, 500);

    const admin = createClient(url, secret, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    let requester: any = null;
    let requesterProfile: any = null;
    if (token) {
      const { data } = await admin.auth.getUser(token);
      requester = data.user ?? null;
      if (requester) {
        const { data: profile } = await admin
          .from("profiles")
          .select("*")
          .eq("id", requester.id)
          .maybeSingle();
        requesterProfile = profile ?? null;
      }
    }

    const body = await req.json();
    const action = String(body.action ?? "create_user");

    if (action === "create_user") {
      const role = String(body.role ?? "customer");
      const phone = String(body.phone ?? "").trim();
      const password = String(body.password ?? "");
      const name = String(body.name ?? "").trim();
      const fatherName = String(body.father_name ?? "").trim();
      const grandfatherName = String(body.grandfather_name ?? "").trim();
      let adminId = body.admin_id ? String(body.admin_id) : null;
      const createdBy = requester?.id ?? (body.created_by ? String(body.created_by) : null);

      if (!phone || password.length < 8 || !name) {
        return json({ error: "invalid_input" }, 400);
      }
      if (!["admin", "employee", "customer"].includes(role)) {
        return json({ error: "invalid_role" }, 400);
      }

      const { data: existing } = await admin
        .from("profiles")
        .select("id")
        .eq("phone", phone)
        .maybeSingle();
      if (existing) return json({ error: "phone_exists" }, 409);

      let approved = true;
      let active = true;
      let marketName = "";

      if (role === "admin") {
        if (!requester || !requesterProfile?.is_system_owner || requesterProfile.active !== true) {
          return json({ error: "system_owner_required" }, 403);
        }

        adminId = null;
        marketName = String(body.market_name ?? "").trim();
        if (marketName.length < 2) return json({ error: "invalid_input" }, 400);

        const { data: existingMarket, error: marketLookupError } = await admin
          .from("profiles")
          .select("id")
          .eq("role", "admin")
          .ilike("market_name", marketName)
          .limit(1);
        if (marketLookupError) return json({ error: marketLookupError.message }, 400);
        if ((existingMarket ?? []).length > 0) {
          return json({ error: "market_exists" }, 409);
        }
      } else if (role === "employee") {
        if (!requesterProfile || requesterProfile.role !== "admin" || requesterProfile.active !== true) {
          return json({ error: "employee_creation_requires_admin" }, 403);
        }
        adminId = requester.id;
      } else {
        if (!adminId) return json({ error: "admin_id_required" }, 400);
        const { data: targetAdmin } = await admin
          .from("profiles")
          .select("id, role, active")
          .eq("id", adminId)
          .maybeSingle();
        if (!targetAdmin || targetAdmin.role !== "admin" || targetAdmin.active !== true) {
          return json({ error: "invalid_admin" }, 400);
        }

        if (requesterProfile) {
          if (requesterProfile.active !== true) return json({ error: "forbidden" }, 403);
          const tenantId = requesterProfile.role === "admin"
            ? requesterProfile.id
            : requesterProfile.admin_id;
          if (tenantId !== adminId && !requesterProfile.is_system_owner) {
            return json({ error: "cross_tenant_forbidden" }, 403);
          }
          if (requesterProfile.role === "customer") return json({ error: "forbidden" }, 403);
          if (requesterProfile.role === "employee" && !requesterProfile.can_add_customers) {
            return json({ error: "missing_permission" }, 403);
          }
          approved = true;
        } else {
          approved = false;
        }
      }

      const email = `${phone}@zhirox.local`;
      const { data: authData, error: authError } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { name, phone, role, admin_id: adminId },
      });
      if (authError || !authData.user) {
        return json({ error: authError?.message ?? "auth_create_failed" }, 400);
      }

      const requestedDays = Math.round(Number(body.subscription_days ?? 30));
      const subscriptionDays = role === "admin"
        ? Math.min(3650, Math.max(1, requestedDays || 30))
        : 0;
      const subscriptionEnd = role === "admin"
        ? new Date(Date.now() + subscriptionDays * 86400000).toISOString()
        : null;

      const profile = {
        id: authData.user.id,
        name,
        father_name: fatherName,
        grandfather_name: grandfatherName,
        phone,
        role,
        market_name: role === "admin" ? marketName : "",
        admin_id: adminId,
        created_by: createdBy,
        approved,
        active,
        debt_limit: Number(body.debt_limit ?? 0),
        debt_duration: Number(body.debt_duration ?? 30),
        can_add_customers: Boolean(body.can_add_customers ?? false),
        can_set_debt_limit: Boolean(body.can_set_debt_limit ?? false),
        can_set_due_date: Boolean(body.can_set_due_date ?? false),
        can_edit_debts: Boolean(body.can_edit_debts ?? false),
        can_send_notifications: Boolean(body.can_send_notifications ?? false),
        subscription_end: subscriptionEnd,
        is_system_owner: false,
      };

      const { data: inserted, error: profileError } = await admin
        .from("profiles")
        .insert(profile)
        .select()
        .single();
      if (profileError) {
        await admin.auth.admin.deleteUser(authData.user.id);
        return json({ error: profileError.message }, 400);
      }
      return json({ user: inserted }, 201);
    }

    if (!requester || !requesterProfile) {
      return json({ error: "authentication_required" }, 401);
    }
    if (requesterProfile.active !== true) {
      return json({ error: "forbidden" }, 403);
    }

    if (action === "reset_password") {
      const targetId = String(body.user_id ?? "");
      const newPassword = String(body.new_password ?? "");
      if (!targetId || newPassword.length < 8) {
        return json({ error: "invalid_input" }, 400);
      }

      const { data: target } = await admin
        .from("profiles")
        .select("id, role, admin_id, is_system_owner")
        .eq("id", targetId)
        .maybeSingle();
      if (!target) return json({ error: "not_found" }, 404);
      if (target.is_system_owner) return json({ error: "cannot_reset_system_owner" }, 403);
      if (targetId === requester.id) {
        return json({ error: "self_password_change_requires_old_password" }, 403);
      }

      const isOwner = requesterProfile.is_system_owner === true;
      const isTenantAdmin =
        requesterProfile.role === "admin" &&
        (target.role === "employee" || target.role === "customer") &&
        target.admin_id === requester.id;
      if (!isOwner && !isTenantAdmin) return json({ error: "forbidden" }, 403);

      const { error } = await admin.auth.admin.updateUserById(targetId, {
        password: newPassword,
      });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    if (action === "delete_user") {
      const targetId = String(body.user_id ?? "");
      const { data: target } = await admin
        .from("profiles")
        .select("*")
        .eq("id", targetId)
        .maybeSingle();
      if (!target) return json({ error: "not_found" }, 404);
      if (target.is_system_owner) return json({ error: "cannot_delete_system_owner" }, 403);

      const requesterTenant = requesterProfile.role === "admin"
        ? requesterProfile.id
        : requesterProfile.admin_id;
      const targetTenant = target.role === "admin" ? target.id : target.admin_id;
      const isOwner = requesterProfile.is_system_owner === true;

      if (!isOwner && (
        requesterProfile.role !== "admin" ||
        (targetId !== requester.id && requesterTenant !== targetTenant)
      )) {
        return json({ error: "forbidden" }, 403);
      }
      if (!isOwner && target.role === "admin" && targetId !== requester.id) {
        return json({ error: "cannot_delete_peer_admin" }, 403);
      }

      if (target.role === "customer") {
        const { data: debts } = await admin
          .from("debts")
          .select("id")
          .eq("customer_id", targetId);
        const debtIds = (debts ?? []).map((d: any) => d.id);
        if (debtIds.length) await admin.from("payments").delete().in("debt_id", debtIds);
        await admin
          .from("notifications")
          .delete()
          .or(`customer_id.eq.${targetId},sender_id.eq.${targetId}`);
        await admin.from("debts").delete().eq("customer_id", targetId);
      } else if (target.role === "employee") {
        await admin.from("debts").update({ created_by: null }).eq("created_by", targetId);
        await admin.from("payments").update({ created_by: null }).eq("created_by", targetId);
        await admin.from("notifications").update({ sender_id: null }).eq("sender_id", targetId);
      } else if (target.role === "admin") {
        const { data: tenantUsers } = await admin
          .from("profiles")
          .select("id")
          .eq("admin_id", targetId);
        const ids = [targetId, ...(tenantUsers ?? []).map((u: any) => u.id)];
        const { data: tenantDebts } = await admin
          .from("debts")
          .select("id")
          .in("customer_id", ids);
        const debtIds = (tenantDebts ?? []).map((d: any) => d.id);
        if (debtIds.length) await admin.from("payments").delete().in("debt_id", debtIds);
        await admin
          .from("notifications")
          .delete()
          .or(ids.map((id: string) => `customer_id.eq.${id}`).join(","));
        await admin.from("debts").delete().in("customer_id", ids);
        for (const id of (tenantUsers ?? []).map((u: any) => u.id)) {
          await admin.auth.admin.deleteUser(id);
        }
      }

      const { error } = await admin.auth.admin.deleteUser(targetId);
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    return json({ error: "unknown_action" }, 400);
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
