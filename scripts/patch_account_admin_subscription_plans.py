#!/usr/bin/env python3
from pathlib import Path

path = Path('supabase/functions/account-admin/index.ts')
text = path.read_text(encoding='utf-8')

helpers_anchor = '''function chunks<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let index = 0; index < items.length; index += size) {
    out.push(items.slice(index, index + size));
  }
  return out;
}
'''
helpers = '''function chunks<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let index = 0; index < items.length; index += size) {
    out.push(items.slice(index, index + size));
  }
  return out;
}

const subscriptionPlanDays: Record<string, number> = {
  monthly: 30,
  quarterly: 90,
  semiannual: 180,
  annual: 365,
};

function resolveSubscriptionPlan(
  rawPlan: unknown,
  rawCustomDays: unknown,
): { plan: string; days: number } | null {
  const plan = String(rawPlan ?? '').trim().toLowerCase();
  const fixedDays = subscriptionPlanDays[plan];
  if (fixedDays) return { plan, days: fixedDays };
  if (plan !== 'custom') return null;

  const days = Math.round(Number(rawCustomDays));
  if (!Number.isFinite(days) || days < 1 || days > 3650) return null;
  return { plan: 'custom', days };
}
'''
if 'const subscriptionPlanDays: Record<string, number>' not in text:
    if helpers_anchor not in text:
        raise SystemExit('helpers anchor missing')
    text = text.replace(helpers_anchor, helpers, 1)

old_role_prelude = '''      let canManageSettings = false;

      if (role === "admin") {
'''
new_role_prelude = '''      let canManageSettings = false;
      let resolvedSubscription: { plan: string; days: number } | null = null;

      if (role === "admin") {
'''
if old_role_prelude in text:
    text = text.replace(old_role_prelude, new_role_prelude, 1)

old_market = '''        adminId = null;
        marketName = String(body.market_name ?? "").trim();
        if (marketName.length < 2) return json({ error: "invalid_input" }, 400);
'''
new_market = '''        adminId = null;
        marketName = String(body.market_name ?? "").trim();
        resolvedSubscription = resolveSubscriptionPlan(
          body.subscription_plan,
          body.subscription_days,
        );
        if (marketName.length < 2 || !resolvedSubscription) {
          return json({ error: "invalid_input" }, 400);
        }
'''
if old_market in text:
    text = text.replace(old_market, new_market, 1)

old_days = '''      const requestedDays = Math.round(Number(body.subscription_days ?? 30));
      const subscriptionDays = role === "admin"
        ? Math.min(3650, Math.max(1, requestedDays || 30))
        : 0;
      const subscriptionEnd = role === "admin"
        ? new Date(Date.now() + subscriptionDays * 86400000).toISOString()
        : null;
'''
new_days = '''      const subscriptionEnd = role === "admin" && resolvedSubscription
        ? new Date(Date.now() + resolvedSubscription.days * 86400000).toISOString()
        : null;
'''
if old_days in text:
    text = text.replace(old_days, new_days, 1)

old_profile_tail = '''        can_manage_settings: canManageSettings,
        subscription_end: subscriptionEnd,
        is_system_owner: false,
'''
new_profile_tail = '''        can_manage_settings: canManageSettings,
        subscription_plan: resolvedSubscription?.plan ?? null,
        subscription_end: subscriptionEnd,
        is_system_owner: false,
'''
if old_profile_tail in text:
    text = text.replace(old_profile_tail, new_profile_tail, 1)

old_renew = '''      const adminId = String(body.admin_id ?? "").trim();
      const days = Math.round(Number(body.days));
      if (!adminId || !Number.isFinite(days) || days < 1 || days > 3650) {
        return json({ error: "invalid_input" }, 400);
      }
'''
new_renew = '''      const adminId = String(body.admin_id ?? "").trim();
      const resolvedSubscription = resolveSubscriptionPlan(
        body.subscription_plan,
        body.days,
      );
      if (!adminId || !resolvedSubscription) {
        return json({ error: "invalid_input" }, 400);
      }
'''
if old_renew in text:
    text = text.replace(old_renew, new_renew, 1)

old_end = '''      const subscriptionEnd = new Date(base + days * 86400000).toISOString();
      const { error: updateError } = await admin
        .from("profiles")
        .update({ subscription_end: subscriptionEnd })
        .eq("id", adminId);
'''
new_end = '''      const subscriptionEnd = new Date(
        base + resolvedSubscription.days * 86400000,
      ).toISOString();
      const { error: updateError } = await admin
        .from("profiles")
        .update({
          subscription_plan: resolvedSubscription.plan,
          subscription_end: subscriptionEnd,
        })
        .eq("id", adminId);
'''
if old_end in text:
    text = text.replace(old_end, new_end, 1)

required = [
    'const subscriptionPlanDays: Record<string, number>',
    'function resolveSubscriptionPlan(',
    'subscription_plan: resolvedSubscription?.plan ?? null,',
    'subscription_plan: resolvedSubscription.plan,',
    'platform/account metadata only',
]
for marker in required:
    if marker not in text:
        raise SystemExit(f'marker missing after patch: {marker}')

path.write_text(text, encoding='utf-8')
print('account-admin subscription plans hardened')
