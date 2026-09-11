from pathlib import Path

ROOT = Path('.')
LIB = ROOT / 'lib'
MAIN = LIB / 'main.dart'
PROVIDER = LIB / 'providers/debt_provider.dart'
DEBT_LIST = LIB / 'screens/shared/debt_list_screen.dart'
VERIFY = ROOT / 'scripts/verify_online_only.py'

# Safety check: the legacy provider/list must not still be part of live navigation
# or referenced from other application code before deleting them.
provider_refs = []
debt_list_refs = []
for path in LIB.rglob('*.dart'):
    text = path.read_text(encoding='utf-8')
    rel = path.as_posix()
    if 'DebtProvider' in text:
        provider_refs.append(rel)
    if 'DebtListScreen' in text:
        debt_list_refs.append(rel)

allowed_provider_refs = {
    'lib/main.dart',
    'lib/providers/debt_provider.dart',
    'lib/screens/shared/debt_list_screen.dart',
}
if set(provider_refs) - allowed_provider_refs:
    raise SystemExit(f'Unexpected DebtProvider references: {provider_refs}')
if set(debt_list_refs) - {'lib/screens/shared/debt_list_screen.dart'}:
    raise SystemExit(f'DebtListScreen is still live: {debt_list_refs}')

main = MAIN.read_text(encoding='utf-8')
main = main.replace("import 'package:zhirox/providers/debt_provider.dart';\n", '')
main = main.replace('        ChangeNotifierProvider(create: (_) => DebtProvider()),\n', '')
if 'DebtProvider' in main:
    raise SystemExit('DebtProvider still referenced in main.dart')
MAIN.write_text(main, encoding='utf-8')

if PROVIDER.exists():
    PROVIDER.unlink()
if DEBT_LIST.exists():
    DEBT_LIST.unlink()

verify = VERIFY.read_text(encoding='utf-8')
marker = '# Legacy standalone debt workspace/provider must stay removed.'
if marker not in verify:
    insert = r'''

# Legacy standalone debt workspace/provider must stay removed. Customer finance
# now lives exclusively in Customer Profile -> Financial Chat.
legacy_provider = LIB / 'providers/debt_provider.dart'
legacy_debt_list = LIB / 'screens/shared/debt_list_screen.dart'
if legacy_provider.exists():
    fail('lib/providers/debt_provider.dart: legacy action-only wrapper must stay removed')
if legacy_debt_list.exists():
    fail('lib/screens/shared/debt_list_screen.dart: standalone debt workspace must stay removed')
for dart_path in LIB.rglob('*.dart'):
    source = dart_path.read_text(encoding='utf-8')
    if 'DebtProvider' in source:
        fail(f'{dart_path.relative_to(ROOT)}: DebtProvider must not return')
    if 'DebtListScreen' in source:
        fail(f'{dart_path.relative_to(ROOT)}: standalone DebtListScreen must not return')
'''
    anchor = "if violations:\n"
    if anchor not in verify:
        raise SystemExit('Verifier insertion anchor missing')
    verify = verify.replace(anchor, insert + '\n' + anchor, 1)
VERIFY.write_text(verify, encoding='utf-8')

print('Legacy DebtProvider and standalone DebtListScreen removed safely.')
