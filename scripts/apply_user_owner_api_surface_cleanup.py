from pathlib import Path
import re

ROOT = Path.cwd()
pb_path = ROOT / 'lib/services/pb_service.dart'
verify_path = ROOT / 'scripts/verify_online_only.py'

pb = pb_path.read_text(encoding='utf-8')
verify = verify_path.read_text(encoding='utf-8')

# Remove the User-edition client entry point for creating admin accounts.
register_re = re.compile(
    r"\n  static Future<RecordModel> registerAdmin\(\{.*?\n  \}\n\n(?=  static Future<RecordModel> registerCustomer)",
    re.S,
)
pb, register_count = register_re.subn('\n', pb, count=1)
if register_count == 0 and 'static Future<RecordModel> registerAdmin(' in pb:
    raise SystemExit('registerAdmin cleanup target not matched')

# Remove System-Owner management client methods from User edition while
# preserving checkSubscriptionDaysLeft, which regular accounts still need.
management_re = re.compile(
    r"\n  static Future<Map<String, dynamic>> getAdminsPage\(\{.*?"
    r"\n  static Future<int> checkSubscriptionDaysLeft",
    re.S,
)
match = management_re.search(pb)
if match:
    pb = pb[:match.start()] + '\n  static Future<int> checkSubscriptionDaysLeft' + pb[match.end():]
elif any(marker in pb for marker in (
    'static Future<Map<String, dynamic>> getAdminsPage(',
    'static Future<void> renewAdminSubscription(',
    'static Future<void> deleteAdminWithData(',
)):
    raise SystemExit('Owner management cleanup target not matched')

start = '# System Owner admin management must use the set-based, owner-checked RPCs.\n'
mid = '# System Owner admin deletion must use its JWT-verified dedicated Edge Function.\n'
end = '# Owner/User edition separation and privileged account-admin guards.\n'
if start not in verify or mid not in verify or end not in verify:
    raise SystemExit('Verifier owner-management block anchors not found')

backend_rpc_guard = """# User mobile client must not expose System Owner admin-management APIs.
for forbidden in (
    'static Future<RecordModel> registerAdmin(',
    'static Future<Map<String, dynamic>> getAdminsPage(',
    'static Future<void> renewAdminSubscription(',
    'static Future<void> deleteAdminWithData(',
):
    if forbidden in pb:
        fail(f'lib/services/pb_service.dart: User source must not expose owner API: {forbidden}')

# Shared backend migrations remain tracked and security-hardened even though
# the User mobile client does not call these owner-only RPCs.
admin_rpc_migration = ROOT / 'supabase/migrations/20260911102326_system_owner_admin_management_rpcs.sql'
if not admin_rpc_migration.exists():
    fail(f'{admin_rpc_migration.relative_to(ROOT)}: System Owner admin-management migration must be tracked')
else:
    admin_rpc_source = admin_rpc_migration.read_text(encoding='utf-8').lower()
    for marker in (
        'security definer',
        'p.is_system_owner = true',
        'a.is_system_owner = false',
        'get_system_owner_admins_page',
        'renew_system_owner_admin_subscription',
        'revoke all on function public.get_system_owner_admins_page(integer, integer) from public, anon;',
        'revoke all on function public.renew_system_owner_admin_subscription(uuid, integer) from public, anon;',
    ):
        if marker not in admin_rpc_source:
            fail(f'{admin_rpc_migration.relative_to(ROOT)}: System Owner RPC security marker missing: {marker}')

"""

secure_delete_guard = """# Shared backend secure admin deletion must remain JWT-verified and Owner-scoped.
secure_delete_edge = ROOT / 'supabase/functions/delete-account/index.ts'
if not secure_delete_edge.exists():
    fail('supabase/functions/delete-account/index.ts: secure admin deletion Edge Function must be tracked')
else:
    secure_delete_source = secure_delete_edge.read_text(encoding='utf-8')
    for marker in (
        'requesterProfile.is_system_owner !== true',
        'target.role !== \"admin\"',
        'target.is_system_owner === true',
        'admin.auth.admin.deleteUser(userId)',
        'admin.auth.admin.deleteUser(targetId)',
        'admin.storage.from(\"receipts\").remove(batch)',
    ):
        if marker not in secure_delete_source:
            fail(f'supabase/functions/delete-account/index.ts: secure deletion marker missing: {marker}')
    for forbidden in (
        '.from(\"payments\").delete()',
        '.from(\"debts\").delete()',
        '.from(\"notifications\").delete()',
    ):
        if forbidden in secure_delete_source:
            fail(f'supabase/functions/delete-account/index.ts: relational cleanup must stay FK-cascade driven, found {forbidden}')

"""

prefix, rest = verify.split(start, 1)
_, rest_after_mid = rest.split(mid, 1)
_, suffix = rest_after_mid.split(end, 1)
verify = prefix + backend_rpc_guard + secure_delete_guard + end + suffix

pb_path.write_text(pb, encoding='utf-8')
verify_path.write_text(verify, encoding='utf-8')
print('User owner-only client API surface removed.')
