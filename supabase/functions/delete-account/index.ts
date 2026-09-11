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

    const { data: tenantUsers, error: tenantUsersError } = await admin
      .from("profiles")
      .select("id")
      .eq("admin_id", targetId);
    if (tenantUsersError) return json({ error: tenantUsersError.message }, 400);

    const childIds = (tenantUsers ?? []).map((row: { id: string }) => row.id);

    // Capture receipt object paths before customer profiles/debts cascade away.
    const receiptPaths: string[] = [];
    if (childIds.length > 0) {
      const { data: receiptRows, error: receiptError } = await admin
        .from("debts")
        .select("receipt_image_path")
        .in("customer_id", childIds);
      if (receiptError) return json({ error: receiptError.message }, 400);
      for (const row of receiptRows ?? []) {
        const path = String(row.receipt_image_path ?? "").trim();
        if (path && !receiptPaths.includes(path)) receiptPaths.push(path);
      }
    }

    // Delete tenant auth accounts first in bounded batches. Every auth deletion
    // cascades its profile and related public rows transactionally via Postgres
    // FKs. If one batch fails, the admin remains so the operation is retryable.
    for (const batch of chunks(childIds, 8)) {
      const results = await Promise.all(
        batch.map(async (userId) => {
          const { error } = await admin.auth.admin.deleteUser(userId);
          return error ? { userId, error: error.message } : null;
        }),
      );
      const failures = results.filter((item) => item !== null);
      if (failures.length > 0) {
        return json(
          {
            error: "tenant_member_delete_failed",
            failed_user_ids: failures.map((item) => item!.userId),
          },
          409,
        );
      }
    }

    const { error: deleteAdminError } = await admin.auth.admin.deleteUser(targetId);
    if (deleteAdminError) {
      return json({ error: "admin_delete_failed", detail: deleteAdminError.message }, 409);
    }

    // Storage is outside the relational FK transaction. Cleanup is best-effort
    // after the authoritative account/data deletion has succeeded.
    let receiptCleanupFailed = false;
    for (const batch of chunks(receiptPaths, 100)) {
      if (batch.length === 0) continue;
      const { error } = await admin.storage.from("receipts").remove(batch);
      if (error) receiptCleanupFailed = true;
    }

    return json({
      ok: true,
      deleted_members: childIds.length,
      receipt_cleanup_failed: receiptCleanupFailed,
    });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
