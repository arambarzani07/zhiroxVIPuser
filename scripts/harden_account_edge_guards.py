from pathlib import Path
import os

root = Path(os.environ.get('REPO_ROOT', Path.cwd())).resolve()
account = root / 'supabase/functions/account-admin/index.ts'
verify = root / 'scripts/verify_online_only.py'

source = account.read_text(encoding='utf-8')

admin_guard = '''    if (target.role === "admin") {
      return json({ error: "admin_delete_requires_dedicated_endpoint" }, 409);
    }
'''
anchor = '''    if (!target) return json({ error: "not_found" }, 404);
    if (target.is_system_owner) return json({ error: "cannot_delete_system_owner" }, 403);

'''
if 'admin_delete_requires_dedicated_endpoint' not in source:
    if source.count(anchor) != 1:
        raise SystemExit('account-admin delete target anchor mismatch')
    source = source.replace(anchor, anchor + admin_guard + '\n', 1)

legacy = '''      } else if (target.role === "admin") {
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
'''
if legacy in source:
    source = source.replace(legacy, '      }\n', 1)
if 'const { data: tenantUsers }' in source:
    raise SystemExit('legacy admin delete block still present')
account.write_text(source, encoding='utf-8')

v = verify.read_text(encoding='utf-8')
marker = '# Account Edge Function privilege boundaries.'
if marker not in v:
    insert = r'''
# Account Edge Function privilege boundaries.
# Admin account lifecycle is Owner-only: creation is guarded by account-admin,
# while destructive admin deletion must stay centralized in delete-account.
update_account_edge = ROOT / 'supabase/functions/update-account/index.ts'
if not update_account_edge.exists():
    fail('supabase/functions/update-account/index.ts: production update-account source must be tracked')
else:
    update_account_source = update_account_edge.read_text(encoding='utf-8')
    for required in (
        'requester.active !== true',
        'sameTenantMember',
        'target.role === "employee" || target.role === "customer"',
        'targetAuthData',
        'previousAuthMetadata',
        'Object.hasOwn(update, "phone")',
    ):
        if required not in update_account_source:
            fail(f'supabase/functions/update-account/index.ts: account hardening marker missing: {required}')
    for forbidden in ('"role",', '"is_system_owner",', '"admin_id",'):
        # These privileged fields may appear in auth metadata, but must never be
        # present in either profile-update allowlist.
        allowlist_area = update_account_source.split('const selfFields', 1)[-1].split('const allowed', 1)[0]
        if forbidden in allowlist_area:
            fail(f'supabase/functions/update-account/index.ts: privileged profile field entered update allowlist: {forbidden}')

if account_admin_edge.exists():
    account_admin_source = account_admin_edge.read_text(encoding='utf-8')
    if 'admin_delete_requires_dedicated_endpoint' not in account_admin_source:
        fail('supabase/functions/account-admin/index.ts: admin deletion must be routed to delete-account')
    if 'const { data: tenantUsers }' in account_admin_source:
        fail('supabase/functions/account-admin/index.ts: duplicate admin cascade deletion must stay removed')

'''
    if '\nif violations:\n' not in v:
        raise SystemExit('verifier insertion anchor missing')
    v = v.replace('\nif violations:\n', '\n' + insert + 'if violations:\n', 1)
verify.write_text(v, encoding='utf-8')
