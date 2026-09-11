from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise SystemExit(f'{label} marker not found')


# ---------- Shared finance math ----------
helpers_path = Path('lib/utils/helpers.dart')
helpers = helpers_path.read_text(encoding='utf-8')
marker = '  // فۆرماتی بەروار\n'
addition = r'''  /// Normalizes one debt field to IQD. USD values without a valid
  /// historical rate are deliberately unknown instead of being mixed into IQD.
  static double? debtValueInIqd(RecordModel debt, String field) {
    final value = debt.getDoubleValue(field);
    final currency = debt.getStringValue('currency').trim().isEmpty
        ? 'IQD'
        : debt.getStringValue('currency').trim().toUpperCase();
    if (currency != 'USD') return value;
    final rate = debt.getDoubleValue('dollar_rate');
    if (rate <= 0) return null;
    return value * rate;
  }

  static ({
    double totalDebt,
    double totalRemaining,
    double totalPaid,
    bool complete,
  }) debtSummaryInIqd(Iterable<RecordModel> debts) {
    var totalDebt = 0.0;
    var totalRemaining = 0.0;
    var complete = true;
    for (final debt in debts) {
      final amount = debtValueInIqd(debt, 'amount');
      final remaining = debtValueInIqd(debt, 'remaining');
      if (amount == null || remaining == null) {
        complete = false;
        continue;
      }
      totalDebt += amount;
      totalRemaining += remaining;
    }
    final totalPaid = totalDebt - totalRemaining;
    return (
      totalDebt: totalDebt,
      totalRemaining: totalRemaining,
      totalPaid: totalPaid.abs() < 0.000001 ? 0 : totalPaid,
      complete: complete,
    );
  }

'''
if 'debtSummaryInIqd(' not in helpers:
    helpers = replace_once(helpers, marker, addition + marker, 'helpers finance summary')
helpers_path.write_text(helpers, encoding='utf-8')


# ---------- Customer profile ----------
profile_path = Path('lib/screens/shared/user_profile_screen.dart')
profile = profile_path.read_text(encoding='utf-8')
raw_summary = '''  List<Widget> _buildCustomerBody() {
    final totalDebt = _debts.fold(
      0.0,
      (sum, d) => sum + d.getDoubleValue('amount'),
    );
    final totalRemaining = _debts.fold(
      0.0,
      (sum, d) => sum + d.getDoubleValue('remaining'),
    );
    final totalPaid = totalDebt - totalRemaining;
    final auth = context.read<AuthProvider>();
'''
safe_summary = '''  List<Widget> _buildCustomerBody() {
    final summary = AppHelpers.debtSummaryInIqd(_debts);
    final totalDebt = summary.totalDebt;
    final totalRemaining = summary.totalRemaining;
    final totalPaid = summary.totalPaid;
    final totalsComplete = summary.complete;
    final auth = context.read<AuthProvider>();
'''
profile = replace_once(profile, raw_summary, safe_summary, 'profile summary')
profile = replace_once(
    profile,
    "                AppHelpers.formatCurrency(totalDebt),\n",
    "                totalsComplete ? AppHelpers.formatCurrency(totalDebt) : '—',\n",
    'profile debt total display',
)
profile = replace_once(
    profile,
    "                AppHelpers.formatCurrency(totalRemaining),\n",
    "                totalsComplete ? AppHelpers.formatCurrency(totalRemaining) : '—',\n",
    'profile remaining display',
)
profile = replace_once(
    profile,
    "              onPressed: () => _generateAccountStatement(\n                totalDebt: totalDebt,\n                totalRemaining: totalRemaining,\n                totalPaid: totalPaid,\n              ),\n",
    "              onPressed: totalsComplete\n                  ? () => _generateAccountStatement(\n                        totalDebt: totalDebt,\n                        totalRemaining: totalRemaining,\n                        totalPaid: totalPaid,\n                      )\n                  : () => _showIncompleteCurrencySummaryMessage(),\n",
    'profile statement safety',
)
profile = replace_once(
    profile,
    "      _buildDebtLimitCard(),\n",
    "      if (!totalsComplete) _buildCurrencySummaryWarning(),\n      _buildDebtLimitCard(),\n",
    'profile warning card',
)
profile = replace_once(
    profile,
    "        totalPaid: totalPaid,\n      ),\n",
    "        totalPaid: totalPaid,\n        totalsComplete: totalsComplete,\n      ),\n",
    'profile chat summary completeness',
)
profile = replace_once(
    profile,
    "    required double totalPaid,\n  }) {\n    final isDark = Theme.of(context).brightness == Brightness.dark;\n",
    "    required double totalPaid,\n    required bool totalsComplete,\n  }) {\n    final isDark = Theme.of(context).brightness == Brightness.dark;\n",
    'chat card signature',
)
profile = replace_once(
    profile,
    "                        value: totalDebt,\n",
    "                        value: totalsComplete ? totalDebt : null,\n",
    'chat debt total',
)
profile = replace_once(
    profile,
    "                        value: totalPaid,\n",
    "                        value: totalsComplete ? totalPaid : null,\n",
    'chat paid total',
)
profile = replace_once(
    profile,
    "                        value: totalRemaining,\n                        color: totalRemaining > 0 ? Colors.red : Colors.green,\n",
    "                        value: totalsComplete ? totalRemaining : null,\n                        color: totalsComplete && totalRemaining > 0\n                            ? Colors.red\n                            : Colors.green,\n",
    'chat remaining total',
)
profile = replace_once(
    profile,
    "            _buildDebtHealthStrip(\n              label: health.$1,\n              color: health.$2,\n              totalRemaining: totalRemaining,\n              totalPaid: totalPaid,\n            ),\n",
    "            if (totalsComplete)\n              _buildDebtHealthStrip(\n                label: health.$1,\n                color: health.$2,\n                totalRemaining: totalRemaining,\n                totalPaid: totalPaid,\n              )\n            else\n              _buildCurrencySummaryWarning(compact: true),\n",
    'chat health safety',
)
profile = replace_once(
    profile,
    "    required double value,\n",
    "    required double? value,\n",
    'nullable chat summary value',
)
profile = replace_once(
    profile,
    "              AppHelpers.formatCurrency(value),\n",
    "              value == null ? '—' : AppHelpers.formatCurrency(value),\n",
    'nullable chat summary formatter',
)

# Add reusable warning and error action before date picker.
warning_marker = '  Future<void> _pickFinancialDateRange() async {\n'
warning_method = r'''  void _showIncompleteCurrencySummaryMessage() {
    AppHelpers.showSnackBar(
      context,
      'هەندێک قەرزی USD نرخی گۆڕینەوەی دروستی نییە؛ بۆ پاراستنی دروستی ژمارەکان کۆی گشتی پیشان نادرێت.',
      isError: true,
    );
  }

  Widget _buildCurrencySummaryWarning({bool compact = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: compact
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(16, 6, 16, 2),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 11 : 13,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: isDark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          const Icon(Icons.currency_exchange_rounded, size: 17, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'کۆی دارایی نیشان نادرێت چونکە هەندێک USD نرخی گۆڕینەوەی نییە.',
              style: TextStyle(
                fontSize: compact ? 9.5 : 10.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppDarkColors.textSecondary
                    : const Color(0xFF7A5B00),
              ),
            ),
          ),
        ],
      ),
    );
  }

'''
if '_showIncompleteCurrencySummaryMessage()' not in profile:
    profile = replace_once(profile, warning_marker, warning_method + warning_marker, 'currency warning helpers')

# Debt-limit math must use the same normalized summary.
profile = re.sub(
    r"    final totalRemaining = _debts\.fold\(\n      0\.0,\n      \(sum, d\) => sum \+ d\.getDoubleValue\('remaining'\),\n    \);\n    final remainingLimit = hasLimit \? limit - totalRemaining : 0\.0;\n    final isOverLimit = hasLimit && remainingLimit < 0;\n    final usagePercent = hasLimit\n        \? \(totalRemaining / limit\)\.clamp\(0\.0, 1\.0\)\n        : 0\.0;",
    "    final debtSummary = AppHelpers.debtSummaryInIqd(_debts);\n    final totalRemaining = debtSummary.totalRemaining;\n    final totalsComplete = debtSummary.complete;\n    final remainingLimit =\n        hasLimit && totalsComplete ? limit - totalRemaining : 0.0;\n    final isOverLimit =\n        hasLimit && totalsComplete && remainingLimit < 0;\n    final usagePercent = hasLimit && totalsComplete\n        ? (totalRemaining / limit).clamp(0.0, 1.0)\n        : 0.0;",
    profile,
    count=1,
)
profile = replace_once(
    profile,
    "                              AppHelpers.formatCurrency(remainingLimit.abs()),\n",
    "                              totalsComplete\n                                  ? AppHelpers.formatCurrency(remainingLimit.abs())\n                                  : '—',\n",
    'debt limit available display',
)

# Composer only needs to know if there is an unpaid debt; never sum mixed currencies.
profile = replace_once(
    profile,
    "    final totalRemaining = _debts.fold<double>(\n      0,\n      (sum, debt) => sum + debt.getDoubleValue('remaining'),\n    );\n",
    "    final hasOutstandingDebt =\n        _debts.any((debt) => debt.getDoubleValue('remaining') > 0);\n",
    'composer outstanding debt',
)
profile = replace_once(
    profile,
    "                onPressed: totalRemaining > 0\n                    ? () => _showFinancialPaymentSheet(auth)\n                    : null,\n",
    "                onPressed: hasOutstandingDebt\n                    ? () => _showFinancialPaymentSheet(auth)\n                    : null,\n",
    'composer payment condition',
)
profile = replace_once(
    profile,
    "                    color: totalRemaining > 0\n                        ? Colors.green.withValues(alpha: 0.32)\n                        : const Color(0xFFD0D5DD),\n",
    "                    color: hasOutstandingDebt\n                        ? Colors.green.withValues(alpha: 0.32)\n                        : const Color(0xFFD0D5DD),\n",
    'composer payment border',
)

# Full statement also fails closed on missing USD rate.
old_statement = '''  Future<void> _generateCurrentFinancialStatement() async {
    final totalDebt = _debts.fold<double>(
      0,
      (sum, debt) => sum + debt.getDoubleValue('amount'),
    );
    final totalRemaining = _debts.fold<double>(
      0,
      (sum, debt) => sum + debt.getDoubleValue('remaining'),
    );
    await _generateAccountStatement(
      totalDebt: totalDebt,
      totalRemaining: totalRemaining,
      totalPaid: totalDebt - totalRemaining,
    );
  }
'''
new_statement = '''  Future<void> _generateCurrentFinancialStatement() async {
    final summary = AppHelpers.debtSummaryInIqd(_debts);
    if (!summary.complete) {
      _showIncompleteCurrencySummaryMessage();
      return;
    }
    await _generateAccountStatement(
      totalDebt: summary.totalDebt,
      totalRemaining: summary.totalRemaining,
      totalPaid: summary.totalPaid,
    );
  }
'''
profile = replace_once(profile, old_statement, new_statement, 'current statement summary')
profile_path.write_text(profile, encoding='utf-8')


# ---------- Customer dashboard ----------
dash_path = Path('lib/screens/customer/customer_dashboard.dart')
dash = dash_path.read_text(encoding='utf-8')
dash = replace_once(
    dash,
    "  double _totalRemainingAmount = 0;\n  String _marketName = '';\n",
    "  double _totalRemainingAmount = 0;\n  bool _totalsComplete = true;\n  String _marketName = '';\n",
    'dashboard total state',
)
old_calc = '''      final allDebts = await PBService.getDebts(customerId: auth.userId);
      double totalDebt = 0;
      double totalRemaining = 0;
      for (final debt in allDebts) {
        totalDebt += debt.getDoubleValue('amount');
        totalRemaining += debt.getDoubleValue('remaining');
      }
'''
new_calc = '''      final allDebts = await PBService.getDebts(customerId: auth.userId);
      final summary = AppHelpers.debtSummaryInIqd(allDebts);
      final totalDebt = summary.totalDebt;
      final totalRemaining = summary.totalRemaining;
'''
dash = replace_once(dash, old_calc, new_calc, 'dashboard summary calculation')
dash = replace_once(
    dash,
    "        _totalRemainingAmount = totalRemaining;\n        _activeDebts = activeDebts;\n",
    "        _totalRemainingAmount = totalRemaining;\n        _totalsComplete = summary.complete;\n        _activeDebts = activeDebts;\n",
    'dashboard summary state',
)
dash = replace_once(
    dash,
    "  Future<void> _printStatement() async {\n    if (_activeDebts.isEmpty) {\n",
    "  Future<void> _printStatement() async {\n    if (!_totalsComplete) {\n      AppHelpers.showSnackBar(\n        context,\n        'کەشف دروست ناکرێت تا نرخی گۆڕینەوەی هەموو قەرزە USD ـەکان دیاری بکرێت.',\n        isError: true,\n      );\n      return;\n    }\n    if (_activeDebts.isEmpty) {\n",
    'dashboard statement fail closed',
)
dash = replace_once(
    dash,
    "                      AppHelpers.formatCurrency(_totalRemaining),\n",
    "                      _totalsComplete\n                          ? AppHelpers.formatCurrency(_totalRemaining)\n                          : '—',\n",
    'dashboard remaining display',
)
dash = replace_once(
    dash,
    "                            value: AppHelpers.formatCurrency(totalPaid),\n",
    "                            value: _totalsComplete\n                                ? AppHelpers.formatCurrency(totalPaid)\n                                : '—',\n",
    'dashboard paid display',
)
# Add a concise currency warning under the amount.
warning_anchor = """                    const SizedBox(height: 14),
                    Row(
                      children: [
"""
warning_insert = r'''                    if (!_totalsComplete) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'هەندێک قەرزی USD نرخی گۆڕینەوەی نییە؛ کۆی گشتی بۆ پاراستنی دروستی نیشان نادرێت.',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
'''
if 'کۆی گشتی بۆ پاراستنی دروستی نیشان نادرێت' not in dash:
    dash = replace_once(dash, warning_anchor, warning_insert, 'dashboard currency warning')
dash_path.write_text(dash, encoding='utf-8')


# ---------- Tests ----------
test_path = Path('test/widget_test.dart')
test = test_path.read_text(encoding='utf-8')
if "package:pocketbase/pocketbase.dart" not in test:
    test = test.replace(
        "import 'package:flutter_test/flutter_test.dart';\n",
        "import 'package:flutter_test/flutter_test.dart';\nimport 'package:pocketbase/pocketbase.dart';\n",
        1,
    )
insert = r'''

  group('Currency-safe debt summaries', () {
    RecordModel debt({
      required String id,
      required double amount,
      required double remaining,
      required String currency,
      double rate = 0,
    }) {
      return RecordModel.fromJson({
        'id': id,
        'collectionId': '',
        'collectionName': 'debts',
        'amount': amount,
        'remaining': remaining,
        'currency': currency,
        'dollar_rate': rate,
      });
    }

    test('normalizes mixed IQD and USD using the historical debt rate', () {
      final summary = AppHelpers.debtSummaryInIqd([
        debt(
          id: 'iqd',
          amount: 100000,
          remaining: 60000,
          currency: 'IQD',
        ),
        debt(
          id: 'usd',
          amount: 50,
          remaining: 20,
          currency: 'USD',
          rate: 1500,
        ),
      ]);
      expect(summary.complete, isTrue);
      expect(summary.totalDebt, 175000);
      expect(summary.totalRemaining, 90000);
      expect(summary.totalPaid, 85000);
    });

    test('fails closed when a USD debt has no valid historical rate', () {
      final summary = AppHelpers.debtSummaryInIqd([
        debt(
          id: 'usd-no-rate',
          amount: 50,
          remaining: 20,
          currency: 'USD',
        ),
      ]);
      expect(summary.complete, isFalse);
    });
  });
'''
if "group('Currency-safe debt summaries'" not in test:
    pos = test.rfind('\n}')
    if pos < 0:
        raise SystemExit('test closing marker not found')
    test = test[:pos] + insert + test[pos:]
test_path.write_text(test, encoding='utf-8')


# ---------- Permanent verifier ----------
verify_path = Path('scripts/verify_online_only.py')
verify = verify_path.read_text(encoding='utf-8')
verify_marker = '\n\nif violations:\n'
verify_block = r'''

# Currency-safe financial totals: never add USD raw values into IQD summaries.
helpers_source = (LIB / 'utils/helpers.dart').read_text(encoding='utf-8')
dashboard_source = (LIB / 'screens/customer/customer_dashboard.dart').read_text(encoding='utf-8')
for marker in ('debtValueInIqd', 'debtSummaryInIqd'):
    if marker not in helpers_source:
        fail(f'lib/utils/helpers.dart: currency-safe finance marker missing: {marker}')
for marker in ('AppHelpers.debtSummaryInIqd(_debts)', 'totalsComplete', '_buildCurrencySummaryWarning'):
    if marker not in profile:
        fail(f'lib/screens/shared/user_profile_screen.dart: currency-safe summary marker missing: {marker}')
for marker in ('AppHelpers.debtSummaryInIqd(allDebts)', '_totalsComplete'):
    if marker not in dashboard_source:
        fail(f'lib/screens/customer/customer_dashboard.dart: currency-safe dashboard marker missing: {marker}')
'''
if '# Currency-safe financial totals:' not in verify:
    verify = replace_once(verify, verify_marker, verify_block + verify_marker, 'currency verifier')
verify_path.write_text(verify, encoding='utf-8')
