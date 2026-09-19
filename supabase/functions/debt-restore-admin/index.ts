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

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

type ActionBody = {
  action?: string;
  debt_id?: string;
  payment_id?: string;
  limit?: number;
};

export default {
  async fetch(req: Request) {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }
    if (req.method !== 'POST') {
      return json({ error: 'method_not_allowed' }, 405);
    }

    const url = Deno.env.get("SUPABASE_URL") ?? "";
    const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      envJsonKey("SUPABASE_SECRET_KEYS");
    if (!url || !secret) return json({ error: 'server_not_configured' }, 500);

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    if (!token) return json({ error: 'authentication_required' }, 401);

    const admin = createClient(url, secret, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: userError } = await admin.auth.getUser(token);
    if (userError || !userData.user) {
      return json({ error: 'authentication_required' }, 401);
    }
    const userId = userData.user.id;

    const { data: profile, error: profileError } = await admin
      .from('profiles')
      .select('id, role, active, approved, subscription_end, is_system_owner')
      .eq('id', userId)
      .maybeSingle();

    if (profileError || !profile) {
      return json({ error: 'profile_not_found' }, 403);
    }
    if (
      profile.role !== 'admin' ||
      profile.active !== true ||
      profile.approved !== true
    ) {
      return json({ error: 'admin_required' }, 403);
    }
    if (
      profile.is_system_owner !== true &&
      profile.subscription_end &&
      new Date(profile.subscription_end).getTime() < Date.now()
    ) {
      return json({ error: 'subscription_expired' }, 403);
    }

    let body: ActionBody;
    try {
      body = await req.json();
    } catch (_) {
      return json({ error: 'invalid_json' }, 400);
    }

    const action = String(body.action ?? '').trim();

    if (action === 'list') {
      const requestedLimit = Number(body.limit ?? 200);
      const limit = Number.isFinite(requestedLimit)
        ? Math.max(1, Math.min(Math.trunc(requestedLimit), 500))
        : 200;

      const { data: customers, error: customersError } = await admin
        .from('profiles')
        .select('id, name')
        .eq('admin_id', userId)
        .eq('role', 'customer');

      if (customersError) return json({ error: 'customers_query_failed' }, 500);
      if (!customers || customers.length === 0) return json({ items: [] });

      const customerIds = customers.map((row) => row.id);
      const customerNames = new Map(
        customers.map((row) => [row.id, row.name ?? '']),
      );

      const { data: debts, error: debtsError } = await admin
        .from('debts')
        .select(
          'id, customer_id, description, amount, remaining, status, currency, due_date, custom_date, created_at, deleted_at',
        )
        .in('customer_id', customerIds)
        .eq('is_deleted', true)
        .order('deleted_at', { ascending: false, nullsFirst: false })
        .limit(limit);

      if (debtsError) return json({ error: 'deleted_debts_query_failed' }, 500);

      const items = (debts ?? []).map((row) => ({
        ...row,
        customer_name: customerNames.get(row.customer_id) ?? '',
      }));
      return json({ items });
    }

    if (action === 'delete') {
      const debtId = String(body.debt_id ?? '').trim();
      if (!debtId) return json({ error: 'invalid_input' }, 400);

      const { data: deleted, error: deleteError } = await admin.rpc(
        'delete_debt_service',
        { p_actor_id: userId, p_debt_id: debtId },
      );
      if (deleteError || deleted !== true) {
        return json(
          {
            error: deleteError?.message ?? 'delete_failed',
            code: deleteError?.code,
          },
          deleteError?.code === '42501' ? 403 : 500,
        );
      }
      return json({ deleted: true });
    }

    if (action === 'delete_payment') {
      const paymentId = String(body.payment_id ?? '').trim();
      if (!paymentId) return json({ error: 'invalid_input' }, 400);

      const { data: result, error: deleteError } = await admin.rpc(
        'delete_payment_service',
        { p_actor_id: userId, p_payment_id: paymentId },
      );
      if (deleteError || !result?.payment_deleted) {
        return json(
          {
            error: deleteError?.message ?? 'payment_delete_failed',
            code: deleteError?.code,
          },
          deleteError?.code === '42501' ? 403 : 500,
        );
      }
      return json(result);
    }

    if (action === 'restore') {
      const debtId = String(body.debt_id ?? '').trim();
      if (!debtId) return json({ error: 'invalid_input' }, 400);

      const { data: restored, error: restoreError } = await admin.rpc(
        'restore_debt_service',
        { p_actor_id: userId, p_debt_id: debtId },
      );
      if (restoreError || restored !== true) {
        return json(
          {
            error: restoreError?.message ?? 'restore_failed',
            code: restoreError?.code,
          },
          restoreError?.code === '42501' ? 403 : 500,
        );
      }
      return json({ restored: true });
    }

    return json({ error: 'invalid_action' }, 400);
  },
};
