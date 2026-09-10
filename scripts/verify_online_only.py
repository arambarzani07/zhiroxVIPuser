from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / 'lib'
violations: list[str] = []


def fail(message: str) -> None:
    violations.append(message)


# SharedPreferences may persist only UI/security preferences. Business data must
# always come from the live backend in this online-only app.
allowed_shared_preferences = {
    Path('lib/providers/auth_provider.dart'),
    Path('lib/providers/theme_provider.dart'),
}
for path in LIB.rglob('*.dart'):
    text = path.read_text(encoding='utf-8')
    rel = path.relative_to(ROOT)
    if 'package:shared_preferences/shared_preferences.dart' in text:
        if rel not in allowed_shared_preferences:
            fail(f'{rel}: SharedPreferences is forbidden for business/runtime data')

    if re.search(r"cached_(?:debts|payments|users|customers|profiles|requests|dashboard|stats)", text, re.I):
        fail(f'{rel}: business-data cache key detected')


main = (LIB / 'main.dart').read_text(encoding='utf-8')
for marker in ('class _OnlineOnlyGate', 'child: _OnlineOnlyGate', 'IgnorePointer', 'ConnectivityService.instance'):
    if marker not in main:
        fail(f'lib/main.dart: online-only gate marker missing: {marker}')


auth = (LIB / 'providers/auth_provider.dart').read_text(encoding='utf-8')
if 'PBService.getUser(authUser.id)' not in auth:
    fail('lib/providers/auth_provider.dart: saved sessions must be revalidated against the live profile')
if '_validateSubscription(' not in auth:
    fail('lib/providers/auth_provider.dart: saved sessions must revalidate subscription state')


debt_provider = (LIB / 'providers/debt_provider.dart').read_text(encoding='utf-8')
for forbidden in ('List<RecordModel> _debts', 'List<RecordModel> _payments', 'Future<void> loadDebts', 'Future<void> loadPayments'):
    if forbidden in debt_provider:
        fail(f'lib/providers/debt_provider.dart: stale provider cache API remains: {forbidden}')


pb = (LIB / 'services/pb_service.dart').read_text(encoding='utf-8')
match = re.search(
    r'static\s+Future<double>\s+getCustomerBalance\([^)]*\)\s+async\s*\{(.*?)(?=\n\s*static\s+)',
    pb,
    re.S,
)
if not match:
    fail('lib/services/pb_service.dart: getCustomerBalance implementation not found')
else:
    body = match.group(1)
    if 'catch' in body or re.search(r'\breturn\s+0(?:\.0)?\s*;', body):
        fail('lib/services/pb_service.dart: customer balance must fail closed, never silently return zero')


add_debt = (LIB / 'screens/shared/add_debt_screen.dart').read_text(encoding='utf-8')
if 'PBService.getCustomerBalance' not in add_debt:
    fail('lib/screens/shared/add_debt_screen.dart: debt-limit flow must verify live customer balance')


if violations:
    print('ONLINE-ONLY POLICY FAILED')
    for item in violations:
        print(f' - {item}')
    sys.exit(1)

print('Online-only policy verification passed.')
