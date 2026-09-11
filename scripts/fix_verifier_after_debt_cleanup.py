from pathlib import Path

path = Path('scripts/verify_online_only.py')
text = path.read_text(encoding='utf-8')
old = '''debt_provider = (LIB / 'providers/debt_provider.dart').read_text(encoding='utf-8')
for forbidden in ('List<RecordModel> _debts', 'List<RecordModel> _payments', 'Future<void> loadDebts', 'Future<void> loadPayments'):
    if forbidden in debt_provider:
        fail(f'lib/providers/debt_provider.dart: stale provider cache API remains: {forbidden}')


'''
if old not in text:
    raise SystemExit('stale debt_provider verifier block not found')
text = text.replace(old, '', 1)
path.write_text(text, encoding='utf-8')
print('Removed stale debt_provider read from online-only verifier.')
