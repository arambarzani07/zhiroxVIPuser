from pathlib import Path
import re

ROOT = Path.cwd()
auth_path = ROOT / 'lib/providers/auth_provider.dart'
verify_path = ROOT / 'scripts/verify_online_only.py'

auth = auth_path.read_text(encoding='utf-8')
verify = verify_path.read_text(encoding='utf-8')

pattern = re.compile(
    r"\n  Future<void> registerAdmin\(\{.*?\n  \}\n\n(?=  Future<void> registerCustomer\()",
    re.S,
)
auth, count = pattern.subn('\n', auth, count=1)
if count == 0 and ('Future<void> registerAdmin(' in auth or 'PBService.registerAdmin(' in auth):
    raise SystemExit('User AuthProvider registerAdmin target not matched')

# Keep User edition free of every mobile-side admin-creation entry point.
guard = """
# User AuthProvider must not expose admin registration.
auth_provider_source = (LIB / 'providers/auth_provider.dart').read_text(encoding='utf-8')
for forbidden in (
    'Future<void> registerAdmin(',
    'PBService.registerAdmin(',
):
    if forbidden in auth_provider_source:
        fail(f'lib/providers/auth_provider.dart: User source must not expose admin registration: {forbidden}')
"""
anchor = '\nif violations:\n'
if guard not in verify:
    if anchor not in verify:
        raise SystemExit('Verifier final anchor not found')
    verify = verify.replace(anchor, guard + anchor, 1)

auth_path.write_text(auth, encoding='utf-8')
verify_path.write_text(verify, encoding='utf-8')
print('User AuthProvider admin-registration surface removed.')
