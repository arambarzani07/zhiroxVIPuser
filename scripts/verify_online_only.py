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


add_debt = (LIB / 'screens/shared/add_debt_screen.dart').read_text(encoding='utf-8')
for marker in ('_customerLoadError', '_buildCustomerPicker', 'دووبارە هەوڵ بدە'):
    if marker not in add_debt:
        fail(f'lib/screens/shared/add_debt_screen.dart: fail-closed customer loading marker missing: {marker}')
load_match = re.search(
    r'Future<void>\s+_loadCustomers\(\)\s+async\s*\{(.*?)(?=\s*@override\s*void dispose)',
    add_debt,
    re.S,
)
if not load_match or '_customerLoadError =' not in load_match.group(1):
    fail('lib/screens/shared/add_debt_screen.dart: customer load failures must become an explicit error state')

compat = (LIB / 'services/supabase_compat.dart').read_text(encoding='utf-8')
ctx_match = re.search(
    r'Future<_RelationContext>\s+_contextFor\([^)]*\)\s+async\s*\{(.*?)(?=\s*Map<String, dynamic>\s+_writeMap)',
    compat,
    re.S,
)
if not ctx_match:
    fail('lib/services/supabase_compat.dart: relation context loader not found')
elif 'catch' in ctx_match.group(1):
    fail('lib/services/supabase_compat.dart: relation context must not swallow live backend failures')


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


# User-facing screens must not expose raw backend exception text, and debt detail
# must preserve an explicit retryable load-error state.
detail = (LIB / 'screens/shared/debt_detail_screen.dart').read_text(encoding='utf-8')
for rel, source in (
    ('lib/screens/shared/add_debt_screen.dart', add_debt),
    ('lib/screens/shared/debt_detail_screen.dart', detail),
):
    for raw_marker in ("'هەڵە: $e'", "هەڵە لە کردنەوەی کامێرا: $e"):
        if raw_marker in source:
            fail(f'{rel}: raw backend exception text must not be shown to users')
for marker in ('String? _loadError', 'AppHelpers.backendErrorMessage', 'دووبارە هەوڵ بدە'):
    if marker not in detail:
        fail(f'lib/screens/shared/debt_detail_screen.dart: lifecycle/error marker missing: {marker}')


# Financial Chat realtime/audit markers: business history remains server-backed
# and new activity must arrive through Supabase realtime, never a local cache.
profile = (LIB / 'screens/shared/user_profile_screen.dart').read_text(encoding='utf-8')
for marker in (
    'PBService.getFinancialEvents',
    "table: 'financial_events'",
    '_hasNewFinancialActivity',
    '_jumpToLatest',
    '_buildFinancialSystemMessage',
):
    if marker not in profile:
        fail(f'lib/screens/shared/user_profile_screen.dart: Financial Chat marker missing: {marker}')
if 'getFinancialEvents(String customerId)' not in pb:
    fail('lib/services/pb_service.dart: Financial Chat audit reader missing')


# Financial Chat Phase 4 must remain live-only and keep its integrated search,
# date/type filters, debt references, receipt preview and statement/share action.
profile = (LIB / 'screens/shared/user_profile_screen.dart').read_text(encoding='utf-8')
for marker_name in (
    '_financialSearchController',
    '_financialDateRange',
    "_financialTypeFilter = 'all'",
    '_filterFinancialTimeline',
    'showDateRangePicker',
    '_buildPaymentDebtReference',
    '_buildReceiptPreview',
    'Image.network(',
    'کەشف / هاوبەشکردن',
):
    if marker_name not in profile:
        fail(f'lib/screens/shared/user_profile_screen.dart: Financial Chat Phase 4 marker missing: {marker_name}')


if violations:
    print('ONLINE-ONLY POLICY FAILED')
    for item in violations:
        print(f' - {item}')
    sys.exit(1)

print('Online-only policy verification passed.')
