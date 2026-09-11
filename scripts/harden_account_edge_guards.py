from pathlib import Path
import os
import re

root = Path(os.environ.get('REPO_ROOT', Path.cwd())).resolve()
account = root / 'supabase/functions/account-admin/index.ts'
verify = root / 'scripts/verify_online_only.py'

source = account.read_text(encoding='utf-8')

admin_guard = '''      if (target.role === "admin") {
        return json({ error: "admin_delete_requires_dedicated_endpoint" }, 409);
      }
'''
owner_guard_line = '      if (target.is_system_owner) return json({ error: "cannot_delete_system_owner" }, 403);\n'
if 'admin_delete_requires_dedicated_endpoint' not in source:
    delete_start = source.find('    if (action === "delete_user") {')
    if delete_start < 0:
        raise SystemExit('account-admin delete_user block missing')
    guard_at = source.find(owner_guard_line, delete_start)
    if guard_at < 0:
        raise SystemExit('account-admin delete target guard missing')
    insert_at = guard_at + len(owner_guard_line)
    source = source[:insert_at] + admin_guard + source[insert_at:]

legacy_pattern = re.compile(
    r'      \} else if \(target\.role === "admin"\) \{.*?\n      \}\n\n'
    r'      const \{ error \} = await admin\.auth\.admin\.deleteUser\(targetId\);',
    re.S,
)
source, count = legacy_pattern.subn(
    '      }\n\n      const { error } = await admin.auth.admin.deleteUser(targetId);',
    source,
    count=1,
)
if count == 0 and 'const { data: tenantUsers }' in source:
    raise SystemExit('legacy admin delete block did not match')
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
    allowlist_area = update_account_source.split('const selfFields', 1)[-1].split('const allowed', 1)[0]
    for forbidden in ('"role",', '"is_system_owner",', '"admin_id",'):
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
