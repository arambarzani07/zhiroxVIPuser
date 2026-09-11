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
    "'get_customer_finance_snapshot'",
    "'get_customer_financial_timeline_page'",
    "'p_cursor_at'",
    "'p_cursor_kind'",
    "'p_cursor_id'",
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
    if marker not in profile:
        fail(f'lib/screens/shared/user_profile_screen.dart: Financial Chat pagination marker missing: {marker}')
load_data_match = re.search(
    r'Future<void>\s+_loadData\(\)\s+async\s*\{(.*?)(?=\s*Future<void>\s+_subscribeFinancialRealtime)',
    profile,
    re.S,
)
if not load_data_match:
    fail('lib/screens/shared/user_profile_screen.dart: _loadData pagination implementation not found')
else:
    load_body = load_data_match.group(1)
    for forbidden in ('PBService.getDebts(', 'PBService.getPayments(', 'PBService.getFinancialEvents('):
        if forbidden in load_body:
            fail(f'lib/screens/shared/user_profile_screen.dart: initial customer load must not bulk-load history: {forbidden}')
    for required in ('PBService.getCustomerFinanceSnapshot', 'PBService.getCustomerFinancialTimelinePage', 'limit: 50'):
        if required not in load_body:
            fail(f'lib/screens/shared/user_profile_screen.dart: initial paginated load marker missing: {required}')

# Financial Chat Phase 4 must remain live-only and keep its integrated search,
# date/type filters, debt references, receipt preview and statement/share action.
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


# Financial Chat must remain the single customer debt/payment workspace.
customer_list_source = (ROOT / 'lib/screens/shared/user_list_screen.dart').read_text(encoding='utf-8')
if 'openFinancialChat' not in profile:
    fail('Customer profile must support direct Financial Chat entry')
if "openFinancialChat: widget.role == 'customer'" not in customer_list_source:
    fail('Customer list tap must open Financial Chat directly')
if '_showPaymentDialog(RecordModel user)' in customer_list_source:
    fail('Customer list must not duplicate payment recording outside Financial Chat')

# Customer Inbox must batch summaries and avoid request storms from text search
# or realtime financial-event bursts.
for marker in (
    'PBService.getCustomerInboxRows(ids)',
    'Timer? _customerSearchDebounce;',
    '_scheduleCustomerSearch',
    'Duration(milliseconds: 300)',
    '_inboxRefreshInFlight',
    '_inboxRefreshPending',
    '_markFinancialChatReadBestEffort',
):
    if marker not in customer_list_source:
        fail(f'lib/screens/shared/user_list_screen.dart: Customer Inbox performance marker missing: {marker}')
if 'onChanged: (value) => _loadUsers(search: value)' in customer_list_source:
    fail('lib/screens/shared/user_list_screen.dart: customer search must not query on every keypress')
for marker in ('getCustomerInboxRows(', 'markFinancialChatRead('):
    if marker not in pb:
        fail(f'lib/services/pb_service.dart: Customer Inbox RPC marker missing: {marker}')

inbox_schema = ROOT / 'supabase/migrations/20260911090854_add_financial_chat_inbox.sql'
inbox_grants = ROOT / 'supabase/migrations/20260911093112_harden_financial_chat_inbox_grants.sql'
for migration_path in (inbox_schema, inbox_grants):
    if not migration_path.exists():
        fail(f'{migration_path.relative_to(ROOT)}: Customer Inbox migration must be tracked')
if inbox_grants.exists():
    grants_source = inbox_grants.read_text(encoding='utf-8')
    for marker in (
        'revoke all on table public.financial_chat_reads from anon;',
        'grant select, insert, update on table public.financial_chat_reads to authenticated;',
        'revoke execute on function public.get_customer_inbox_rows(uuid[]) from public, anon;',
        'revoke execute on function public.mark_financial_chat_read(uuid) from public, anon;',
    ):
        if marker not in grants_source:
            fail(f'{inbox_grants.relative_to(ROOT)}: least-privilege marker missing: {marker}')
# First-unread semantics must avoid both extremes: historical activity from
# before Inbox launch must not flood users as unread, while the first new
# activity after the viewer's effective baseline must not be silently hidden.
inbox_first_unread = ROOT / 'supabase/migrations/20260911100158_baseline_customer_inbox_first_unread.sql'
if not inbox_first_unread.exists():
    fail(f'{inbox_first_unread.relative_to(ROOT)}: Customer Inbox first-unread migration must be tracked')
else:
    first_unread_source = inbox_first_unread.read_text(encoding='utf-8')
    for marker in (
        'with viewer_baseline as (',
        "'2026-09-11 09:08:54+00'::timestamptz",
        'when rd.last_read_at is not null then l.event_at > rd.last_read_at',
        'else l.event_at > vb.baseline_at',
        'cross join viewer_baseline vb',
    ):
        if marker not in first_unread_source:
            fail(f'{inbox_first_unread.relative_to(ROOT)}: first-unread marker missing: {marker}')
    if 'when rd.last_read_at is null then false' in first_unread_source:
        fail(f'{inbox_first_unread.relative_to(ROOT)}: first activity after baseline must not be forced read')

if 'DebtProvider' in customer_list_source:
    fail('Customer list must not own debt/payment mutation logic')

for marker in (
    '_showFinancialTransactionActions',
    'FinancialDocumentActions.openReceiptViewer(',
    'FinancialDocumentActions.generateDebtInvoice(',
    'onTap: () => _showFinancialTransactionActions(item)',
):
    if marker not in profile:
        fail(f'Financial Chat Phase 6 marker missing: {marker}')
for marker in (
    'generateDebtInvoice(',
    'receiptUrl(',
    'openReceiptViewer(',
    'PdfService.generateInvoice(',
    'InteractiveViewer(',
    'PBService.pb.getFileUrl(',
):
    if marker not in document_actions:
        fail(f'lib/screens/shared/financial_document_actions.dart: shared document marker missing: {marker}')
for source_name, source in (
    ('lib/screens/shared/user_profile_screen.dart', profile),
    ('lib/screens/shared/debt_detail_screen.dart', debt_detail_source),
):
    if 'PdfService.generateInvoice(' in source:
        fail(f'{source_name}: direct invoice generation duplicates shared document actions')
    if 'InteractiveViewer(' in source:
        fail(f'{source_name}: duplicate receipt viewer must not return')
    if 'PBService.pb.getFileUrl(' in source:
        fail(f'{source_name}: receipt URL resolution must stay centralized')


# Financial Chat ledger intelligence, overdue visibility, targeted payment
# and filter-aware PDF export must stay integrated in the customer chat.
for marker in (
    '_financialRunningBalances',
    '_timelineAmountInIqd',
    '_overdueDebtLabel',
    'ماوەی هەژمار',
    'پارەدانەوەی تەواو',
    'initialDebtId',
    'initialAmount',
    "case 'pay_full':",
    '_generateFilteredFinancialChatStatement',
    'PdfService.generateFinancialChatStatement',
):
    if marker not in profile:
        fail(f'Financial Chat Phase 7 marker missing: {marker}')
for marker in (
    'FinancialPaymentFlow',
    'initialStorageAmount',
    "const Text('25%')",
    "const Text('50%')",
    "const Text('تەواو')",
    '_storageToDisplay',
    '_displayToStorage',
):
    if marker not in payment_flow:
        fail(f'lib/screens/shared/financial_payment_flow.dart: shared payment marker missing: {marker}')
pdf_source = (LIB / 'services/pdf_service.dart').read_text(encoding='utf-8')
if 'generateFinancialChatStatement({' not in pdf_source:
    fail('lib/services/pdf_service.dart: filter-aware Financial Chat PDF export missing')


# Financial Chat reply/reference must be persisted server-side, not kept as
# ephemeral UI-only state.
profile_source = (LIB / 'screens/shared/user_profile_screen.dart').read_text(encoding='utf-8')
for marker in ('_financialReplyTarget', 'referenceKind:', 'referenceId:', 'reference_snapshot', 'وەک وەڵام / پەیوەستکردن'):
    if marker not in profile_source:
        fail(f'lib/screens/shared/user_profile_screen.dart: persistent Financial Chat reference marker missing: {marker}')
for marker in ('referenceKind', 'referenceId', "'p_reference_kind'", "'p_reference_id'"):
    if marker not in pb:
        fail(f'lib/services/pb_service.dart: persistent financial reference marker missing: {marker}')
for marker in ('referenceKind', 'referenceId'):
    if marker not in add_debt:
        fail(f'lib/screens/shared/add_debt_screen.dart: debt reference pass-through missing: {marker}')


# Currency-safe financial totals: canonical amount/remaining/payment values are
# stored in IQD; USD is display metadata and must never be multiplied twice.
helpers_source = (LIB / 'utils/helpers.dart').read_text(encoding='utf-8')
dashboard_source = (LIB / 'screens/customer/customer_dashboard.dart').read_text(encoding='utf-8')
for marker in (
    'debtValueInIqd',
    'storageAmountToDisplay',
    'formatStoredFinancialAmount',
    'debtSummaryInIqd',
):
    if marker not in helpers_source:
        fail(f'lib/utils/helpers.dart: currency-safe finance marker missing: {marker}')
for marker in (
    '_financeTotalDebtIqd',
    '_financeTotalRemainingIqd',
    '_financeTotalPaidIqd',
    '_financeSummaryComplete',
    'AppHelpers.formatStoredFinancialAmount',
    '_buildCurrencySummaryWarning',
    '_showIncompleteCurrencySummaryMessage',
):
    if marker not in profile:
        fail(f'lib/screens/shared/user_profile_screen.dart: currency-safe summary marker missing: {marker}')
for marker in ('AppHelpers.debtSummaryInIqd(allDebts)', '_totalsComplete'):
    if marker not in dashboard_source:
        fail(f'lib/screens/customer/customer_dashboard.dart: currency-safe dashboard marker missing: {marker}')


# One shared payment flow must own validation, currency conversion,
# confirmation and the transactional payment write for both entry screens.
for marker_name in (
    'ماوەی پێش پارەدان',
    'ماوەی دوای پارەدان',
    'پشتڕاستە — تۆمار بکە',
    'PBService.createPayment(',
):
    if marker_name not in payment_flow:
        fail(f'Shared payment flow marker missing: {marker_name}')
for source_name, source in (
    ('lib/screens/shared/user_profile_screen.dart', profile),
    ('lib/screens/shared/debt_detail_screen.dart', debt_detail_source),
):
    if 'FinancialPaymentFlow.show(' not in source:
        fail(f'{source_name}: must use FinancialPaymentFlow.show')
    if 'PBService.createPayment(' in source:
        fail(f'{source_name}: direct payment write duplicates the shared flow')
if '_confirmFinancialPayment' in profile or '_buildPaymentConfirmationRow' in profile:
    fail('Financial Chat must not retain a duplicate payment confirmation implementation')
if '_buildQuickPayBtn' in debt_detail_source or 'DebtProvider>().addPayment' in debt_detail_source:
    fail('Debt Detail must not retain its legacy duplicate payment form')




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

# Customer Inbox read receipts must be bounded by the last activity actually
# observed by the viewer. Marking through server now() can swallow a new event
# that arrives between tapping a chat and the read-receipt RPC completing.
read_receipt_migration = ROOT / 'supabase/migrations/20260911094437_mark_financial_chat_read_through_timestamp.sql'
if not read_receipt_migration.exists():
    fail(f'{read_receipt_migration.relative_to(ROOT)}: race-safe read-receipt migration must be tracked')
else:
    read_receipt_source = read_receipt_migration.read_text(encoding='utf-8')
    for marker in (
        'mark_financial_chat_read_through',
        'greatest(',
        'least(coalesce(p_read_through, now()), now())',
        'revoke all on function public.mark_financial_chat_read_through(uuid, timestamptz) from public, anon;',
    ):
        if marker not in read_receipt_source:
            fail(f'{read_receipt_migration.relative_to(ROOT)}: read-receipt marker missing: {marker}')
for marker in (
    "'mark_financial_chat_read_through'",
    'required DateTime readThrough',
    "'p_read_through'",
):
    if marker not in pb:
        fail(f'lib/services/pb_service.dart: race-safe read-receipt marker missing: {marker}')
for marker in (
    '_markFinancialChatReadBestEffort(user.id, readThrough)',
    "inbox?['last_activity_at']",
):
    if marker not in customer_list_source:
        fail(f'lib/screens/shared/user_list_screen.dart: bounded read-receipt marker missing: {marker}')
if 'PBService.markFinancialChatRead(user.id)' in customer_list_source:
    fail('lib/screens/shared/user_list_screen.dart: unbounded read receipt must not return')


# A read receipt must never advance without a concrete activity timestamp that
# the viewer actually observed. Null timestamps are fail-closed in both app and DB.
seen_read_migration = ROOT / 'supabase/migrations/20260911095127_require_seen_timestamp_for_financial_chat_read.sql'
if not seen_read_migration.exists():
    fail(f'{seen_read_migration.relative_to(ROOT)}: seen-timestamp read migration must be tracked')
else:
    seen_read_source = seen_read_migration.read_text(encoding='utf-8')
    for marker in (
        'where p_read_through is not null',
        'least(p_read_through, now())',
        'greatest(',
    ):
        if marker not in seen_read_source:
            fail(f'{seen_read_migration.relative_to(ROOT)}: fail-closed read marker missing: {marker}')
for marker in ('required DateTime readThrough', 'readThrough.toUtc().toIso8601String()'):
    if marker not in pb:
        fail(f'lib/services/pb_service.dart: required read-through marker missing: {marker}')
if 'if (readThrough == null) return;' not in customer_list_source:
    fail('lib/screens/shared/user_list_screen.dart: missing null read-through fail-closed guard')


# Customer-list async loads must ignore stale failures and preserve the active
# search query when connectivity returns.
if 'if (!mounted || generation != _loadGeneration) return;' not in customer_list_source:
    fail('lib/screens/shared/user_list_screen.dart: stale customer-list failures must be generation-guarded')
if 'if (online && mounted) _loadUsers();' in customer_list_source:
    fail('lib/screens/shared/user_list_screen.dart: reconnect must not discard the active customer search')
if "_loadUsers(search: _searchController.text.trim());" not in customer_list_source:
    fail('lib/screens/shared/user_list_screen.dart: reconnect/search-preserving reload marker missing')

# System Owner admin management must use the set-based, owner-checked RPCs.
for marker in (
    "'get_system_owner_admins_page'",
    "'renew_system_owner_admin_subscription'",
    "'employeeCount': asInt(row['employee_count'])",
    "'customerCount': asInt(row['customer_count'])",
):
    if marker not in pb:
        fail(f'lib/services/pb_service.dart: System Owner admin-management marker missing: {marker}')
admin_section = pb.split('// ==================== Admin Subscription Management ====================', 1)[-1]
admin_section = admin_section.split('// ==================== Admin Approval ====================', 1)[0]
if 'for (final admin in result.items)' in admin_section:
    fail('lib/services/pb_service.dart: Admin management must not restore per-admin N+1 queries')
if 'admin_id = "$adminId" && role = "employee"' in admin_section or 'admin_id = "$adminId" && role = "customer"' in admin_section:
    fail('lib/services/pb_service.dart: Admin management counts must stay set-based')
admin_rpc_migration = ROOT / 'supabase/migrations/20260911102326_system_owner_admin_management_rpcs.sql'
if not admin_rpc_migration.exists():
    fail(f'{admin_rpc_migration.relative_to(ROOT)}: System Owner admin-management migration must be tracked')
else:
    admin_rpc_source = admin_rpc_migration.read_text(encoding='utf-8')
    for marker in (
        'security definer',
        'p.is_system_owner = true',
        'a.is_system_owner = false',
        'get_system_owner_admins_page',
        'renew_system_owner_admin_subscription',
        'revoke all on function public.get_system_owner_admins_page(integer, integer) from public, anon;',
        'revoke all on function public.renew_system_owner_admin_subscription(uuid, integer) from public, anon;',
    ):
        if marker not in admin_rpc_source.lower():
            fail(f'{admin_rpc_migration.relative_to(ROOT)}: System Owner RPC security marker missing: {marker}')

# System Owner admin deletion must use its JWT-verified dedicated Edge Function.
admin_section = pb.split('// ==================== Admin Subscription Management ====================', 1)[-1]
admin_section = admin_section.split('// ==================== Admin Approval ====================', 1)[0]
if "'delete-account'" not in admin_section:
    fail('lib/services/pb_service.dart: System Owner admin deletion must use delete-account')
if "'account-admin'" in admin_section and "'action': 'delete_user'" in admin_section:
    fail('lib/services/pb_service.dart: System Owner admin deletion must not use the legacy account-admin delete path')
secure_delete_edge = ROOT / 'supabase/functions/delete-account/index.ts'
if not secure_delete_edge.exists():
    fail('supabase/functions/delete-account/index.ts: secure admin deletion Edge Function must be tracked')
else:
    secure_delete_source = secure_delete_edge.read_text(encoding='utf-8')
    for marker in (
        'requesterProfile.is_system_owner !== true',
        'target.role !== "admin"',
        'target.is_system_owner === true',
        'admin.auth.admin.deleteUser(userId)',
        'admin.auth.admin.deleteUser(targetId)',
        'admin.storage.from("receipts").remove(batch)',
    ):
        if marker not in secure_delete_source:
            fail(f'supabase/functions/delete-account/index.ts: secure deletion marker missing: {marker}')
    for forbidden in (
        '.from("payments").delete()',
        '.from("debts").delete()',
        '.from("notifications").delete()',
    ):
        if forbidden in secure_delete_source:
            fail(f'supabase/functions/delete-account/index.ts: relational cleanup must stay FK-cascade driven, found {forbidden}')

if violations:
    print('ONLINE-ONLY POLICY FAILED')
    for item in violations:
        print(f' - {item}')
    sys.exit(1)

print('Online-only policy verification passed.')
