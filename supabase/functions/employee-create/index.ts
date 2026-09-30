import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import {
  DEFAULT_TRUE_EMPLOYEE_PERMISSIONS,
  EMPLOYEE_PERMISSION_KEYS,
} from "../_shared/employee-permission-keys.ts";

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

function isStrongPassword(value: string): boolean {
  if (value.length < 12) return false;
  if (!/[a-z]/.test(value) || !/[A-Z]/.test(value) || !/[0-9]/.test(value)) return false;
  if (!/[^A-Za-z0-9]/.test(value)) return false;
  const normalized = value.toLowerCase();
  return !new Set([
    "password123!",
    "password1234!",
    "qwerty123456!",
    "1234567890aa!",
    "zhirox123456!",
  ]).has(normalized);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const secret = envJsonKey("SUPABASE_SECRET_KEYS") ??
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!secret) return json({ error: "server_not_configured" }, 500);

    const admin = createClient(url, secret, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    if (!token) return json({ error: "authentication_required" }, 401);

    const { data: authData, error: authLookupError } = await admin.auth.getUser(token);
    const requester = authData.user;
    if (authLookupError || !requester) {
      return json({ error: "authentication_required" }, 401);
    }

    const { data: requesterProfile, error: requesterError } = await admin
      .from("profiles")
      .select("id,role,active,approved,subscription_end,is_system_owner")
      .eq("id", requester.id)
      .maybeSingle();
    if (requesterError) return json({ error: requesterError.message }, 400);
    if (
      !requesterProfile ||
      requesterProfile.role !== "admin" ||
      requesterProfile.active !== true ||
      requesterProfile.approved !== true
    ) {
      return json({ error: "employee_creation_requires_admin" }, 403);
    }
    if (!requesterProfile.is_system_owner && requesterProfile.subscription_end) {
      const end = Date.parse(String(requesterProfile.subscription_end));
      if (!Number.isFinite(end) || end < Date.now()) {
        return json({ error: "subscription_expired" }, 403);
      }
    }

    const body = await req.json();
    const name = String(body.name ?? "").trim();
    const fatherName = String(body.father_name ?? "").trim();
    const grandfatherName = String(body.grandfather_name ?? "").trim();
    const phone = String(body.phone ?? "").trim();
    const password = String(body.password ?? "");
    if (!name || !phone) return json({ error: "invalid_input" }, 400);
    if (!isStrongPassword(password)) return json({ error: "weak_password" }, 400);

    const { data: existing, error: existingError } = await admin
      .from("profiles")
      .select("id")
      .eq("phone", phone)
      .maybeSingle();
    if (existingError) return json({ error: existingError.message }, 400);
    if (existing) return json({ error: "phone_exists" }, 409);

    const permissions: Record<string, boolean> = {};
    for (const key of EMPLOYEE_PERMISSION_KEYS) {
      const supplied = body[key];
      permissions[key] = typeof supplied === "boolean"
        ? supplied
        : DEFAULT_TRUE_EMPLOYEE_PERMISSIONS.has(key);
    }

    const email = `${phone}@zhirox.local`;
    const { data: createdAuth, error: createAuthError } =
      await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: {
          name,
          phone,
          role: "employee",
          admin_id: requester.id,
        },
      });
    if (createAuthError || !createdAuth.user) {
      return json({ error: createAuthError?.message ?? "auth_create_failed" }, 400);
    }

    const profile = {
      id: createdAuth.user.id,
      name,
      father_name: fatherName,
      grandfather_name: grandfatherName,
      phone,
      role: "employee",
      market_name: "",
      admin_id: requester.id,
      created_by: requester.id,
      approved: true,
      active: true,
      debt_limit: 0,
      debt_duration: 30,
      ...permissions,
      subscription_end: null,
      is_system_owner: false,
    };

    const { data: inserted, error: profileError } = await admin
      .from("profiles")
      .insert(profile)
      .select()
      .single();
    if (profileError) {
      await admin.auth.admin.deleteUser(createdAuth.user.id);
      if (profileError.code === "23505") return json({ error: "phone_exists" }, 409);
      return json({ error: profileError.message }, 400);
    }

    return json({ user: inserted }, 201);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
