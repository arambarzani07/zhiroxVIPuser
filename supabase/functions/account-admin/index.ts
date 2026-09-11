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
      // Audit ownership is authoritative: authenticated calls use the requester;
      // public customer registrations never get to spoof created_by.
      const createdBy = requester?.id ?? null;

      if (!phone || password.length < 8 || !name) {
        return json({ error: "invalid_input" }, 400);
      }
      if (!["admin", "employee", "customer"].includes(role)) {
        return json({ error: "invalid_role" }, 400);
      }

      const { data: existing, error: existingError } = await admin
        .from("profiles")
        .select("id")
        .eq("phone", phone)
        .maybeSingle();
      if (existingError) return json({ error: existingError.message }, 400);
      if (existing) return json({ error: "phone_exists" }, 409);

      let approved = true;
      const active = true;
      let marketName = "";
      let debtLimit = 0;
      const debtDuration = 30;
      let canAddCustomers = false;
      let canSetDebtLimit = false;
      let canSetDueDate = false;
      let canEditDebts = false;
      let canSendNotifications = false;

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
        if (
          !requesterProfile ||
          requesterProfile.role !== "admin" ||
          !(await isOperational(admin, requesterProfile))
        ) {
          return json({ error: "employee_creation_requires_admin" }, 403);
        }
        adminId = requester.id;
        canAddCustomers = Boolean(body.can_add_customers ?? false);
        canSetDebtLimit = Boolean(body.can_set_debt_limit ?? false);
        canSetDueDate = Boolean(body.can_set_due_date ?? false);
        canEditDebts = Boolean(body.can_edit_debts ?? false);
        canSendNotifications = Boolean(body.can_send_notifications ?? false);
      } else {
        if (!adminId) return json({ error: "admin_id_required" }, 400);
        const { data: targetAdmin, error: targetAdminError } = await admin
          .from("profiles")
          .select("id, role, active, approved, subscription_end")
          .eq("id", adminId)
          .maybeSingle();
        if (targetAdminError) return json({ error: targetAdminError.message }, 400);
        if (
          !targetAdmin ||
          targetAdmin.role !== "admin" ||
          !(await isOperational(admin, targetAdmin))
        ) {
          return json({ error: "invalid_admin" }, 400);
        }

        if (requesterProfile) {
          if (!(await isOperational(admin, requesterProfile))) {
            return json({ error: "forbidden" }, 403);
          }
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

        const requestedDebtLimit = Number(body.debt_limit ?? 0);
        const safeDebtLimit =
          Number.isFinite(requestedDebtLimit) && requestedDebtLimit >= 0
            ? requestedDebtLimit
            : 0;
        if (
          requesterProfile?.role === "admin" ||
          (requesterProfile?.role === "employee" &&
            requesterProfile.can_set_debt_limit === true)
        ) {
          debtLimit = safeDebtLimit;
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
        debt_limit: debtLimit,
        debt_duration: debtDuration,
        can_add_customers: canAddCustomers,
        can_set_debt_limit: canSetDebtLimit,
        can_set_due_date: canSetDueDate,
        can_edit_debts: canEditDebts,
        can_send_notifications: canSendNotifications,
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
    if (!(await isOperational(admin, requesterProfile))) {
      return json({ error: "forbidden" }, 403);
    }

    if (action === "list_admins") {
      if (requesterProfile.is_system_owner !== true) {
        return json({ error: "system_owner_required" }, 403);
      }
      const page = Math.max(1, Math.round(Number(body.page ?? 1)) || 1);
      const perPage = Math.min(100, Math.max(1, Math.round(Number(body.per_page ?? 15)) || 15));
      const from = (page - 1) * perPage;
      const { data: admins, count, error } = await admin
        .from("profiles")
        .select(
          "id,name,phone,role,market_name,subscription_end,approved,active,is_system_owner,created_at,updated_at",
          { count: "exact" },
        )
        .eq("role", "admin")
        .eq("is_system_owner", false)
        .order("created_at", { ascending: false })
        .order("id", { ascending: false })
        .range(from, from + perPage - 1);
      if (error) return json({ error: error.message }, 400);

      const adminIds = (admins ?? []).map((row: any) => row.id);
      const counts = new Map<string, { employee: number; customer: number }>();
      if (adminIds.length > 0) {
        const { data: members, error: membersError } = await admin
          .from("profiles")
          .select("admin_id,role")
          .in("admin_id", adminIds)
          .in("role", ["employee", "customer"]);
        if (membersError) return json({ error: membersError.message }, 400);
        for (const member of members ?? []) {
          const current = counts.get(member.admin_id) ?? { employee: 0, customer: 0 };
          if (member.role === "employee") current.employee += 1;
          if (member.role === "customer") current.customer += 1;
          counts.set(member.admin_id, current);
        }
      }

      const totalItems = count ?? 0;
      return json({
        admins: (admins ?? []).map((row: any) => ({
          admin: row,
          employee_count: counts.get(row.id)?.employee ?? 0,
          customer_count: counts.get(row.id)?.customer ?? 0,
        })),
        total_items: totalItems,
        total_pages: Math.max(1, Math.ceil(totalItems / perPage)),
        page,
      });
    }

    if (action === "renew_subscription") {
      if (requesterProfile.is_system_owner !== true) {
        return json({ error: "system_owner_required" }, 403);
      }
      const adminId = String(body.admin_id ?? "").trim();
      const days = Math.round(Number(body.days));
      if (!adminId || !Number.isFinite(days) || days < 1 || days > 3650) {
        return json({ error: "invalid_input" }, 400);
      }
      const { data: target, error: targetError } = await admin
        .from("profiles")
        .select("id,subscription_end")
        .eq("id", adminId)
        .eq("role", "admin")
        .eq("is_system_owner", false)
        .maybeSingle();
      if (targetError) return json({ error: targetError.message }, 400);
      if (!target) return json({ error: "admin_not_found" }, 404);

      const parsedEnd = target.subscription_end
        ? Date.parse(String(target.subscription_end))
        : Number.NaN;
      const base = Number.isFinite(parsedEnd) && parsedEnd > Date.now()
        ? parsedEnd
        : Date.now();
      const subscriptionEnd = new Date(base + days * 86400000).toISOString();
      const { error: updateError } = await admin
        .from("profiles")
        .update({ subscription_end: subscriptionEnd })
        .eq("id", adminId);
      if (updateError) return json({ error: updateError.message }, 400);
      return json({ subscription_end: subscriptionEnd });
    }


    if (action === "reset_password") {
      const targetId = String(body.user_id ?? "").trim();
      const newPassword = String(body.new_password ?? "");
      if (!targetId || newPassword.length < 8) {
        return json({ error: "invalid_input" }, 400);
      }

      const { data: target, error: targetError } = await admin
        .from("profiles")
        .select("id, role, admin_id, is_system_owner")
        .eq("id", targetId)
        .maybeSingle();
      if (targetError) return json({ error: targetError.message }, 400);
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
      const targetId = String(body.user_id ?? "").trim();
      if (!targetId) return json({ error: "invalid_input" }, 400);

      const { data: target, error: targetError } = await admin
        .from("profiles")
        .select("id, role, admin_id, is_system_owner")
        .eq("id", targetId)
        .maybeSingle();
      if (targetError) return json({ error: targetError.message }, 400);
      if (!target) return json({ error: "not_found" }, 404);
      if (target.is_system_owner) return json({ error: "cannot_delete_system_owner" }, 403);
      if (target.role === "admin") {
        return json({ error: "admin_delete_requires_dedicated_endpoint" }, 409);
      }

      const isOwner = requesterProfile.is_system_owner === true;
      const isTenantAdmin =
        requesterProfile.role === "admin" &&
        (target.role === "employee" || target.role === "customer") &&
        target.admin_id === requester.id;
      if (!isOwner && !isTenantAdmin) return json({ error: "forbidden" }, 403);

      // Public relational data is intentionally FK-driven: profile deletion
      // cascades customer debt/payment/read state and SET NULLs creator fields.
      // Capture receipt object paths first because Storage is outside Postgres.
      const receiptPaths: string[] = [];
      if (target.role === "customer") {
        const { data: receiptRows, error: receiptError } = await admin
          .from("debts")
          .select("receipt_image_path")
          .eq("customer_id", targetId);
        if (receiptError) return json({ error: receiptError.message }, 400);
        for (const row of receiptRows ?? []) {
          const path = String(row.receipt_image_path ?? "").trim();
          if (path && !receiptPaths.includes(path)) receiptPaths.push(path);
        }
      }

      const { error: deleteError } = await admin.auth.admin.deleteUser(targetId);
      if (deleteError) return json({ error: deleteError.message }, 400);

      let receiptCleanupFailed = false;
      for (const batch of chunks(receiptPaths, 100)) {
        if (batch.length === 0) continue;
        const { error } = await admin.storage.from("receipts").remove(batch);
        if (error) receiptCleanupFailed = true;
      }

      return json({ ok: true, receipt_cleanup_failed: receiptCleanupFailed });
    }

    return json({ error: "unknown_action" }, 400);
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
