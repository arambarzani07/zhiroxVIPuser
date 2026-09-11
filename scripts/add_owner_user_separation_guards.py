from pathlib import Path

ROOT = Path.cwd()
path = ROOT / 'scripts/verify_online_only.py'
text = path.read_text(encoding='utf-8')

if 'import os\n' not in text:
    text = text.replace('from pathlib import Path\n', 'from pathlib import Path\nimport os\n', 1)

marker = '# Owner/User edition separation and privileged account-admin guards.'
block = r'''
# Owner/User edition separation and privileged account-admin guards.
edition = os.environ.get('GITHUB_REF_NAME', '')
login_source = (LIB / 'screens/auth/login_screen.dart').read_text(encoding='utf-8')
account_admin_edge = ROOT / 'supabase/functions/account-admin/index.ts'
if not account_admin_edge.exists():
    fail('supabase/functions/account-admin/index.ts: account-admin production source must be tracked')
else:
    account_admin_source = account_admin_edge.read_text(encoding='utf-8')
    for required in (
        'requesterProfile?.is_system_owner',
        'requesterProfile.active !== true',
        'system_owner_required',
        'admin.auth.getUser(token)',
    ):
        if required not in account_admin_source:
            fail(f'supabase/functions/account-admin/index.ts: privileged account guard missing: {required}')

if edition == 'owner-source':
    for required in (
        "package:zhirox/screens/auth/admin_management_screen.dart",
        "getBoolValue('is_system_owner')",
        'return const AdminManagementScreen()',
    ):
        if required not in main:
            fail(f'lib/main.dart: Owner System Owner routing marker missing: {required}')
    if 'RegisterAdminScreen' in login_source or 'register_admin_screen.dart' in login_source:
        fail('lib/screens/auth/login_screen.dart: Owner logged-out login must not open RegisterAdminScreen directly')
    owner_management = (LIB / 'screens/auth/admin_management_screen.dart').read_text(encoding='utf-8')
    for required in (
        '_showCreateAdminDialog',
        "context.read<AuthProvider>().logout()",
        'PBService.registerAdmin(',
    ):
        if required not in owner_management:
            fail(f'lib/screens/auth/admin_management_screen.dart: Owner management marker missing: {required}')
elif edition == 'user-source':
    if 'RegisterAdminScreen' in login_source or 'register_admin_screen.dart' in login_source:
        fail('lib/screens/auth/login_screen.dart: User edition must never route to RegisterAdminScreen')
    for required in (
        '_showOwnerContactDialog',
        'تەنها لەلایەن خاوەن سیستەمەوە درووست دەکرێت.',
    ):
        if required not in login_source:
            fail(f'lib/screens/auth/login_screen.dart: User owner-contact marker missing: {required}')
'''

if marker not in text:
    anchor = '\nif violations:\n'
    if anchor not in text:
        raise SystemExit('verifier final anchor not found')
    text = text.replace(anchor, '\n' + block.strip() + '\n' + anchor, 1)

path.write_text(text, encoding='utf-8')
print('Owner/User separation guards applied.')
