from pathlib import Path

ROOT = Path('.')
profile_path = ROOT / 'lib/screens/shared/user_profile_screen.dart'
detail_path = ROOT / 'lib/screens/shared/debt_detail_screen.dart'
verify_path = ROOT / 'scripts/verify_online_only.py'

# ---- Customer Financial Chat: replace the full inline payment implementation
# with a thin wrapper around the shared flow.
profile = profile_path.read_text(encoding='utf-8')
import_marker = "import 'package:zhirox/screens/shared/debt_detail_screen.dart';\n"
shared_import = "import 'package:zhirox/screens/shared/financial_payment_flow.dart';\n"
if shared_import not in profile:
    assert import_marker in profile, 'profile import marker missing'
    profile = profile.replace(import_marker, import_marker + shared_import, 1)

start = profile.index('  Future<bool> _confirmFinancialPayment(')
end = profile.index('  (String, Color) _debtHealth', start)
profile_wrapper = '''  Future<void> _showFinancialPaymentSheet(
    AuthProvider auth, {
    String? initialDebtId,
    double? initialAmount,
  }) async {
    final replyTarget = _financialReplyTarget;
    final saved = await FinancialPaymentFlow.show(
      context: context,
      debts: _debts,
      createdBy: auth.userId,
      createdByName: auth.userName,
      initialDebtId: initialDebtId,
      initialStorageAmount: initialAmount,
      referenceKind: replyTarget == null
          ? null
          : (replyTarget.isPayment ? 'payment' : 'debt'),
      referenceId: replyTarget?.record.id,
    );
    if (!mounted || !saved) return;
    if (_financialReplyTarget != null) {
      setState(() => _financialReplyTarget = null);
    }
    await _refreshFinancialData(autoJump: true);
  }

'''
profile = profile[:start] + profile_wrapper + profile[end:]
profile_path.write_text(profile, encoding='utf-8')

# ---- Debt Detail: remove its second payment form and call the same shared flow.
detail = detail_path.read_text(encoding='utf-8')
detail_import_marker = "import 'package:zhirox/screens/shared/add_debt_screen.dart';\n"
if shared_import not in detail:
    assert detail_import_marker in detail, 'debt detail import marker missing'
    detail = detail.replace(
        detail_import_marker,
        detail_import_marker + shared_import,
        1,
    )
detail = detail.replace(
    "import 'package:zhirox/providers/debt_provider.dart';\n",
    '',
)
detail = detail.replace(
    'await context.read<DebtProvider>().removeDebt(widget.debtId);',
    'await PBService.deleteDebt(widget.debtId);',
    1,
)
start = detail.index('  Future<void> _showAddPaymentDialog() async {')
end = detail.rfind('\n}')
assert end > start, 'debt detail class end not found'
detail_wrapper = '''  Future<void> _showAddPaymentDialog({double? initialStorageAmount}) async {
    final debt = _debt;
    if (debt == null) return;
    final auth = context.read<AuthProvider>();
    final saved = await FinancialPaymentFlow.show(
      context: context,
      debts: [debt],
      createdBy: auth.userId,
      createdByName: auth.userName,
      initialDebtId: widget.debtId,
      initialStorageAmount: initialStorageAmount,
    );
    if (saved && mounted) {
      await _loadData();
    }
  }
'''
detail = detail[:start] + detail_wrapper + detail[end:]
detail_path.write_text(detail, encoding='utf-8')

# ---- CI policy: enforce the new single payment source of truth.
verify = verify_path.read_text(encoding='utf-8')
profile_decl = "profile = (LIB / 'screens/shared/user_profile_screen.dart').read_text(encoding='utf-8')\n"
flow_decl = "payment_flow = (LIB / 'screens/shared/financial_payment_flow.dart').read_text(encoding='utf-8')\ndebt_detail_source = (LIB / 'screens/shared/debt_detail_screen.dart').read_text(encoding='utf-8')\n"
assert profile_decl in verify, 'profile declaration missing in verifier'
if 'payment_flow = ' not in verify:
    verify = verify.replace(profile_decl, profile_decl + flow_decl, 1)

old_phase = '''# Financial Chat ledger intelligence, overdue visibility, targeted payment
# and filter-aware PDF export must stay integrated in the customer chat.
for marker in (
    '_financialRunningBalances',
    '_timelineAmountInIqd',
    '_overdueDebtLabel',
    'ماوەی هەژمار',
    'پارەدانەوەی تەواو',
    'initialDebtId',
    'initialAmount',
    "const Text('25%')",
    "const Text('50%')",
    "const Text('تەواو')",
    "case 'pay_full':",
    '_generateFilteredFinancialChatStatement',
    'PdfService.generateFinancialChatStatement',
):
    if marker not in profile:
        fail(f'Financial Chat Phase 7 marker missing: {marker}')
'''
new_phase = '''# Financial Chat ledger intelligence, overdue visibility, targeted payment
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
'''
assert old_phase in verify, 'Phase 7 verifier block changed unexpectedly'
verify = verify.replace(old_phase, new_phase, 1)

old_confirm = '''# Financial Chat payment confirmation: destructive/full-balance payment actions
# must show a confirmation summary before the live transaction is submitted.
for marker_name in (
    '_confirmFinancialPayment',
    '_buildPaymentConfirmationRow',
    'ماوەی پێش پارەدان',
    'ماوەی دوای پارەدان',
    'پشتڕاستە — تۆمار بکە',
):
    if marker_name not in profile:
        fail(f'Financial Chat payment confirmation marker missing: {marker_name}')
'''
new_confirm = '''# One shared payment flow must own validation, currency conversion,
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
'''
assert old_confirm in verify, 'payment confirmation verifier block changed unexpectedly'
verify = verify.replace(old_confirm, new_confirm, 1)
verify_path.write_text(verify, encoding='utf-8')

print('Payment flow deduplication applied')
