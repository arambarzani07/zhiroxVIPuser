from pathlib import Path
import os
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
platform_operations_gate = (LIB / 'widgets/platform_operations_gate.dart').read_text(encoding='utf-8')
for marker in ('class _OnlineOnlyGate', 'child: _OnlineOnlyGate', 'IgnorePointer', 'ConnectivityService.instance'):
    if marker not in main:
        fail(f'lib/main.dart: online-only gate marker missing: {marker}')

for marker in (
    "import 'package:zhirox/widgets/platform_operations_gate.dart';",
    'PlatformOperationsGate(',
):
    if marker not in main:
        fail(f'lib/main.dart: platform operations gate marker missing: {marker}')
for marker in (
    'getPlatformOperationsState',
    "state['maintenance_effective'] == true",
    "state['announcement_effective'] == true",
    'Timer.periodic(const Duration(minutes: 1)',
    "getBoolValue('is_system_owner')",
):
    if marker not in platform_operations_gate:
        fail(f'lib/widgets/platform_operations_gate.dart: runtime operations marker missing: {marker}')


auth = (LIB / 'providers/auth_provider.dart').read_text(encoding='utf-8')
if 'PBService.getUser(authUser.id)' not in auth:
    fail('lib/providers/auth_provider.dart: saved sessions must be revalidated against the live profile')
if '_validateSubscription(' not in auth:
    fail('lib/providers/auth_provider.dart: saved sessions must revalidate subscription state')


add_debt_dir = LIB / 'screens/shared'
add_debt_main_path = add_debt_dir / 'add_debt_screen.dart'
add_debt_main = add_debt_main_path.read_text(encoding='utf-8')
add_debt_part_paths = sorted(
    path for path in add_debt_dir.glob('add_debt_*.dart')
    if path != add_debt_main_path
)
add_debt_parts = {
    path.name: path.read_text(encoding='utf-8') for path in add_debt_part_paths
}
add_debt = add_debt_main + '\n' + '\n'.join(add_debt_parts.values())
for marker in (
    "part 'add_debt_items.dart';",
    "part 'add_debt_customer_section.dart';",
):
    if marker not in add_debt_main:
        fail(f'lib/screens/shared/add_debt_screen.dart: add-debt part wiring missing: {marker}')
customer_section = add_debt_parts.get('add_debt_customer_section.dart', '')
for marker in ('_customerLoadError', '_buildCustomerPicker', 'دووبارە هەوڵ بدە'):
    if marker not in customer_section:
        fail(
            'lib/screens/shared/add_debt_customer_section.dart: '
            f'fail-closed customer loading marker missing: {marker}'
        )
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
if "'employee_stats'" not in pb:
    fail('Employee totals must use the authorized Daftar live-read gateway')
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


if 'PBService.getCustomerBalance' not in add_debt:
    fail('lib/screens/shared/add_debt_screen.dart: debt-limit flow must verify live customer balance')
if 'PBService.getAllApprovedCustomers()' not in add_debt:
    fail('lib/screens/shared/add_debt_screen.dart: customer picker must load every paginated customer page')

employee_home = (LIB / 'screens/employee/employee_home_screen.dart').read_text(encoding='utf-8')
if "label: const Text('زیادکردنی کڕیاری نوێ')" in employee_home:
    fail('lib/screens/employee/employee_home_screen.dart: duplicate customer-list action must not return')


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

dashboard_service = (LIB / 'services/pb_service.dart').read_text(encoding='utf-8')
for marker in (
    'getAllApprovedCustomers()',
    "'employee_stats'",
    "client.auth.currentUser?.id",
    ".from('notifications')",
    "senderId: senderId",
):
    if marker not in dashboard_service:
        fail(f'lib/services/pb_service.dart: complete-data or overdue de-duplication marker missing: {marker}')
if "senderId: customerId" in dashboard_service:
    fail('lib/services/pb_service.dart: overdue notification sender must be the authenticated staff user')
if "'admin_dashboard'" not in dashboard_service:
    fail('lib/services/pb_service.dart: dashboard must use the bounded Daftar live-read gateway')
if "pb.collection('payments').getList(filter: paymentFilter" in dashboard_service:
    fail('lib/services/pb_service.dart: dashboard still downloads payment rows for totals')

employee_permissions_sql = (
    ROOT / 'supabase/migrations/20260912130000_enforce_employee_permissions.sql'
).read_text(encoding='utf-8').lower()
for marker in (
    'security invoker',
    'get_admin_dashboard_snapshot()',
    'grant execute on function public.get_admin_dashboard_snapshot() to authenticated;',
):
    if marker not in employee_permissions_sql:
        fail(f'dashboard snapshot migration missing marker: {marker}')

for marker in (
    'private.create_tenant_backup_impl',
    'private.get_tenant_export_impl',
    'employee_permissions_select_authorized',
    'app_update_settings_updated_by_idx',
):
    if marker not in employee_permissions_sql:
        fail(f'governance/RLS hardening migration missing marker: {marker}')

user_list_source = (LIB / 'screens/shared/user_list_screen.dart').read_text(
    encoding='utf-8'
)
customer_directory_controller_source = (
    LIB / 'features/customers/customer_directory_controller.dart'
).read_text(encoding='utf-8')
customer_center_widgets_source = (
    LIB / 'features/customers/customer_center_widgets.dart'
).read_text(encoding='utf-8')
customer_center_source = (
    user_list_source
    + '\n'
    + customer_directory_controller_source
    + '\n'
    + customer_center_widgets_source
)
for marker in ('_inboxError!', 'warning_amber_rounded', 'هەوڵدانەوە'):
    if marker not in customer_center_source:
        fail(f'customer balance retry UI missing marker: {marker}')
for marker in (
    'PBService.getCustomerDirectoryPage',
    'loadMore: true',
    '_nextCursor',
    '_hasMoreUsers',
):
    if marker not in customer_center_source:
        fail(f'customer directory pagination marker missing: {marker}')
for marker in ("'customer_directory'", "'customer_debts_page'"):
    if marker not in pb:
        fail(f'lib/services/pb_service.dart: scalable live-read marker missing: {marker}')


# Financial Chat realtime/audit markers: business history remains server-backed
# and new activity must arrive through Supabase realtime, never a local cache.
#
# UserProfile is intentionally split across Dart part files. Verify the part
# wiring explicitly, then treat the whole library as one source contract so
# refactors do not create false policy failures.
profile_dir = LIB / 'screens/shared'
profile_main_path = profile_dir / 'user_profile_screen.dart'
profile_financial_chat_path = profile_dir / 'user_profile_financial_chat.dart'
profile_main = profile_main_path.read_text(encoding='utf-8')
if not profile_financial_chat_path.exists():
    fail('lib/screens/shared/user_profile_financial_chat.dart: Financial Chat module missing')
if "part 'user_profile_financial_chat.dart';" not in profile_main:
    fail('lib/screens/shared/user_profile_screen.dart: Financial Chat part wiring missing')
profile_part_paths = sorted(
    path for path in profile_dir.glob('user_profile_*.dart')
    if path != profile_main_path
)
profile = profile_main + '\n' + '\n'.join(
    path.read_text(encoding='utf-8') for path in profile_part_paths
)
payment_flow = (LIB / 'screens/shared/financial_payment_flow.dart').read_text(encoding='utf-8')
document_actions = (LIB / 'screens/shared/financial_document_actions.dart').read_text(encoding='utf-8')
debt_detail_source = (LIB / 'screens/shared/debt_detail_screen.dart').read_text(encoding='utf-8')
for marker in (
    'PBService.getCustomerFinancialTimelinePage',
    "table: 'financial_events'",
    '_hasNewFinancialActivity',
    '_jumpToLatest',
    '_buildFinancialSystemMessage',
):
    if marker not in profile:
        fail(f'lib/screens/shared/user_profile_screen.dart: Financial Chat marker missing: {marker}')
if 'getFinancialEvents(String customerId)' not in pb:
    fail('lib/services/pb_service.dart: Financial Chat audit reader missing')

# Long Financial Chat histories must stay virtualized. Building every message
# bubble eagerly inside a Column causes large customer ledgers to jank/freeze.
for marker in (
    '_FinancialChatRenderEntry',
    '_buildFinancialChatRenderEntries',
    'SliverChildBuilderDelegate',
    'addAutomaticKeepAlives: false',
):
    if marker not in profile:
        fail(f'lib/screens/shared/user_profile_screen.dart: Financial Chat virtualization marker missing: {marker}')
if '_buildFinancialChatMessages(' in profile:
    fail('lib/screens/shared/user_profile_screen.dart: eager Financial Chat message widget list must not return')


# Text search must debounce full-history hydration so typing does not start
# an expensive page walk on the first keypress. Existing filter hydration is
# single-flight; this guard keeps the text entry path debounced as well.
for marker in (
    'Timer? _financialSearchDebounce;',
    '_scheduleFinancialSearchHydration',
    'Duration(milliseconds: 350)',
    '_financialSearchDebounce?.cancel();',
):
    if marker not in profile:
        fail(f'lib/screens/shared/user_profile_screen.dart: Financial Chat search debounce marker missing: {marker}')
if """onChanged: (_) {
            setState(() {});
            unawaited(_hydrateFinancialHistoryForFilters());
          },""" in profile:
    fail('lib/screens/shared/user_profile_screen.dart: text search must not hydrate full history on every keypress')


# Financial Chat long-history performance must stay server-paginated. Initial
# customer load uses one aggregate/open-debt snapshot plus a deterministic
# 50-item composite-cursor timeline page; filters hydrate all pages explicitly.
for marker in (
    'getCustomerFinanceSnapshot',
    'getCustomerFinancialTimelinePage',
    "'customer_finance_snapshot'",
    "'customer_timeline'",
    "'cursor'",
    'getAllCustomerDebtsLive',
):
    if marker not in pb:
        fail(f'lib/services/pb_service.dart: Financial Chat pagination marker missing: {marker}')
for marker in (
    '_openDebts',
    '_financialTimelineHasMore',
    '_financialTimelineCursor',
    '_loadOlderFinancialHistory',
    '_ensureAllFinancialHistoryLoaded',
    '_hydrateFinancialHistoryForFilters',
    'مامەڵە کۆنەکان باربکە',
    '_financialTimelineHasMore\n        ? const <String, double?>{}',
):