import { withSupabase } from 'npm:@supabase/server';

const json = (body: Record<string, unknown>, status = 200) =>
  Response.json(body, { status });

type ActionBody = {
  action?: string;
  debt_id?: string;
  limit?: number;
};

export default {
  fetch: withSupabase({ auth: 'user' }, async (req, ctx) => {
    if (req.method !== 'POST') {
      return json({ error: 'method_not_allowed' }, 405);
    }

    const userId = ctx.userClaims?.sub;
    if (!userId) return json({ error: 'unauthorized' }, 401);

    const { data: profile, error: profileError } = await ctx.supabaseAdmin
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

    const fetchOwnedDebt = async (debtId: string, deleted: boolean) => {
      const { data: debt, error: debtError } = await ctx.supabaseAdmin
        .from('debts')
        .select('id, customer_id, is_deleted')
        .eq('id', debtId)
        .eq('is_deleted', deleted)
        .maybeSingle();
      if (debtError || !debt) return null;

      const { data: customer, error: customerError } = await ctx.supabaseAdmin
        .from('profiles')
        .select('id')
        .eq('id', debt.customer_id)
        .eq('admin_id', userId)
        .eq('role', 'customer')
        .maybeSingle();
      if (customerError || !customer) return null;
      return debt;
    };

    if (action === 'list') {
      const requestedLimit = Number(body.limit ?? 200);
      const limit = Number.isFinite(requestedLimit)
        ? Math.max(1, Math.min(Math.trunc(requestedLimit), 500))
        : 200;

      const { data: customers, error: customersError } = await ctx.supabaseAdmin
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

      const { data: debts, error: debtsError } = await ctx.supabaseAdmin
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

      const debt = await fetchOwnedDebt(debtId, false);
      if (!debt) return json({ error: 'debt_not_found_or_forbidden' }, 404);

      const now = new Date().toISOString();
      const { data: updated, error: deleteError } = await ctx.supabaseAdmin
        .from('debts')
        .update({
          is_deleted: true,
          deleted_at: now,
          deleted_by: userId,
          updated_at: now,
        })
        .eq('id', debtId)
        .eq('is_deleted', false)
        .select('id')
        .maybeSingle();

      if (deleteError || !updated) return json({ error: 'delete_failed' }, 500);
      return json({ deleted: true });
    }

    if (action === 'restore') {
      const debtId = String(body.debt_id ?? '').trim();
      if (!debtId) return json({ error: 'invalid_input' }, 400);

      const debt = await fetchOwnedDebt(debtId, true);
      if (!debt) return json({ error: 'debt_not_found_or_forbidden' }, 404);

      const { data: updated, error: restoreError } = await ctx.supabaseAdmin
        .from('debts')
        .update({
          is_deleted: false,
          deleted_at: null,
          deleted_by: null,
          updated_at: new Date().toISOString(),
        })
        .eq('id', debtId)
        .eq('is_deleted', true)
        .select('id')
        .maybeSingle();

      if (restoreError || !updated) return json({ error: 'restore_failed' }, 500);
      return json({ restored: true });
    }

    return json({ error: 'invalid_action' }, 400);
  }),
};
