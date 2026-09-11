from pathlib import Path
import re


def require(condition: bool, label: str) -> None:
    if not condition:
        raise SystemExit(f'{label} marker not found')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise SystemExit(f'{label} marker not found')


# ---------- Shared finance math ----------
helpers_path = Path('lib/utils/helpers.dart')
helpers = helpers_path.read_text(encoding='utf-8')
if 'debtSummaryInIqd(' not in helpers:
    marker = '  // فۆرماتی بەروار\n'
    addition = r'''  /// Normalize one debt field to IQD using the rate stored on that debt.
  /// A USD debt without a valid historical rate is unknown, never silently mixed.
  static double? debtValueInIqd(RecordModel debt, String field) {
    final value = debt.getDoubleValue(field);
    final rawCurrency = debt.getStringValue('currency').trim();
    final currency = rawCurrency.isEmpty ? 'IQD' : rawCurrency.toUpperCase();
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
    var totalPaid = totalDebt - totalRemaining;
    if (totalPaid.abs() < 0.000001) totalPaid = 0;
    return (
      totalDebt: totalDebt,
      totalRemaining: totalRemaining,
      totalPaid: totalPaid,
      complete: complete,
    );
  }

'''
    helpers = replace_once(helpers, marker, addition + marker, 'helper insertion')
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
    'overview debt value',
)
profile = replace_once(
    profile,
    "                AppHelpers.formatCurrency(totalRemaining),\n",
    "                totalsComplete ? AppHelpers.formatCurrency(totalRemaining) : '—',\n",
    'overview remaining value',
)
profile = replace_once(
    profile,
    "              onPressed: () => _generateAccountStatement(\n                totalDebt: totalDebt,\n                totalRemaining: totalRemaining,\n                totalPaid: totalPaid,\n              ),\n",
    "              onPressed: totalsComplete\n                  ? () => _generateAccountStatement(\n                        totalDebt: totalDebt,\n                        totalRemaining: totalRemaining,\n                        totalPaid: totalPaid,\n                      )\n                  : _showIncompleteCurrencySummaryMessage,\n",
    'overview statement safety',
)
profile = replace_once(
    profile,
    "      _buildDebtLimitCard(),\n",
    "      if (!totalsComplete) _buildCurrencySummaryWarning(),\n      _buildDebtLimitCard(),\n",
    'overview currency warning',
)

# Reusable warning helpers are sliver-safe in Overview and normal in Chat.
if 'Widget _buildCurrencySummaryWarning' not in profile:
    marker = '  Future<void> _pickFinancialDateRange() async {\n'
    method = r'''  void _showIncompleteCurrencySummaryMessage() {
    AppHelpers.showSnackBar(
      context,
      'هەندێک قەرزی USD نرخی گۆڕینەوەی دروستی نییە؛ بۆ پاراستنی دروستی ژمارەکان کۆی گشتی پیشان نادرێت.',
      isError: true,
    );
  }

  Widget _buildCurrencySummaryWarning({bool compact = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final warning = Container(
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
    if (compact) return warning;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
        child: warning,
      ),
    );
  }

'''
    profile = replace_once(profile, marker, method + marker, 'profile warning helper')

# Scope Chat-card modifications to exactly that method.
start = profile.find('  Widget _buildCustomerChatTimelineCard({')
end = profile.find('\n  Widget _buildChatSummaryValue({', start)
require(start >= 0 and end > start, 'chat card region')
card = profile[start:end]
if 'final totalsComplete = AppHelpers.debtSummaryInIqd(_debts).complete;' not in card:
    card = replace_once(
        card,
        '    final health = _debtHealth(totalRemaining, totalDebt);\n',
        '    final totalsComplete = AppHelpers.debtSummaryInIqd(_debts).complete;\n    final health = _debtHealth(totalRemaining, totalDebt);\n',
        'chat completeness',
    )
    card = replace_once(card, '                        value: totalDebt,\n', '                        value: totalsComplete ? totalDebt : double.nan,\n', 'chat debt value')
    card = replace_once(card, '                        value: totalPaid,\n', '                        value: totalsComplete ? totalPaid : double.nan,\n', 'chat paid value')
    card = replace_once(
        card,
        '                        value: totalRemaining,\n                        color: totalRemaining > 0 ? Colors.red : Colors.green,\n',
        '                        value: totalsComplete ? totalRemaining : double.nan,\n                        color: totalsComplete && totalRemaining > 0\n                            ? Colors.red\n                            : Colors.green,\n',
        'chat remaining value',
    )
    card = replace_once(
        card,
        '''            _buildDebtHealthStrip(
              label: health.$1,
              color: health.$2,
              totalRemaining: totalRemaining,
              totalPaid: totalPaid,
            ),
''',
        '''            if (totalsComplete)
              _buildDebtHealthStrip(
                label: health.$1,
                color: health.$2,
                totalRemaining: totalRemaining,
                totalPaid: totalPaid,
              )
            else
              _buildCurrencySummaryWarning(compact: true),
''',
        'chat health warning',
    )
profile = profile[:start] + card + profile[end:]

# The summary chip uses NaN only as an internal sentinel to render an em dash.
summary_start = profile.find('  Widget _buildChatSummaryValue({')
summary_end = profile.find('\n  List<Widget> _buildFinancialChatMessages(', summary_start)
require(summary_start >= 0 and summary_end > summary_start, 'chat summary function')
summary_fn = profile[summary_start:summary_end]
summary_fn = replace_once(
    summary_fn,
    '              AppHelpers.formatCurrency(value),\n',
    "              value.isNaN ? '—' : AppHelpers.formatCurrency(value),\n",
    'chat summary formatter',
)
profile = profile[:summary_start] + summary_fn + profile[summary_end:]

# Scope composer modifications so reply UI cannot affect marker matching.
composer_start = profile.find('  Widget _buildFinancialChatComposer(')
composer_end = profile.find('\n  Future<void> _openAddDebtFromChat()', composer_start)
require(composer_start >= 0 and composer_end > composer_start, 'composer region')
composer = profile[composer_start:composer_end]
composer = re.sub(
    r"    final totalRemaining = _debts\.fold<double>\(\n      0,\n      \(sum, debt\) => sum \+ debt\.getDoubleValue\('remaining'\),\n    \);",
    "    final hasOutstandingDebt =\n        _debts.any((debt) => debt.getDoubleValue('remaining') > 0);",
    composer,
    count=1,
)
require('hasOutstandingDebt' in composer, 'composer outstanding debt')
composer = composer.replace('onPressed: totalRemaining > 0', 'onPressed: hasOutstandingDebt')
composer = composer.replace('color: totalRemaining > 0', 'color: hasOutstandingDebt')
profile = profile[:composer_start] + composer + profile[composer_end:]

# Debt limit is IQD-denominated, so its used/remaining values must be normalized.
limit_match = re.search(
    r"  Widget _buildDebtLimitCard\(\) \{.*?(?=\n  Widget _build|\n  Future<)",
    profile,
    re.S,
)
require(limit_match is not None, 'debt limit function')
limit_fn = limit_match.group(0)
limit_fn = re.sub(
    r"    final totalRemaining = _debts\.fold\(\n      0\.0,\n      \(sum, d\) => sum \+ d\.getDoubleValue\('remaining'\),\n    \);\n    final remainingLimit = hasLimit \? limit - totalRemaining : 0\.0;\n    final isOverLimit = hasLimit && remainingLimit < 0;\n    final usagePercent = hasLimit\n        \? \(totalRemaining / limit\)\.clamp\(0\.0, 1\.0\)\n        : 0\.0;",
    "    final debtSummary = AppHelpers.debtSummaryInIqd(_debts);\n    final totalRemaining = debtSummary.totalRemaining;\n    final totalsComplete = debtSummary.complete;\n    final remainingLimit =\n        hasLimit && totalsComplete ? limit - totalRemaining : 0.0;\n    final isOverLimit = hasLimit && totalsComplete && remainingLimit < 0;\n    final usagePercent = hasLimit && totalsComplete\n        ? (totalRemaining / limit).clamp(0.0, 1.0)\n        : 0.0;",
    limit_fn,
    count=1,
)
require('final totalsComplete = debtSummary.complete;' in limit_fn, 'debt limit normalized math')
limit_fn = limit_fn.replace(
    'AppHelpers.formatCurrency(remainingLimit.abs())',
    "totalsComplete ? AppHelpers.formatCurrency(remainingLimit.abs()) : '—'",
    1,
)
profile = profile[:limit_match.start()] + limit_fn + profile[limit_match.end():]

# Full statement fails closed rather than printing a false mixed-currency total.
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
profile = replace_once(profile, old_statement, new_statement, 'full statement safety')
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
dash = replace_once(
    dash,
    '''      final allDebts = await PBService.getDebts(customerId: auth.userId);
      double totalDebt = 0;
      double totalRemaining = 0;
      for (final debt in allDebts) {
        totalDebt += debt.getDoubleValue('amount');
        totalRemaining += debt.getDoubleValue('remaining');
      }
''',
    '''      final allDebts = await PBService.getDebts(customerId: auth.userId);
      final summary = AppHelpers.debtSummaryInIqd(allDebts);
      final totalDebt = summary.totalDebt;
      final totalRemaining = summary.totalRemaining;
''',
    'dashboard normalized summary',
)
dash = replace_once(
    dash,
    "        _totalRemainingAmount = totalRemaining;\n        _activeDebts = activeDebts;\n",
    "        _totalRemainingAmount = totalRemaining;\n        _totalsComplete = summary.complete;\n        _activeDebts = activeDebts;\n",
    'dashboard completeness state',
)
dash = replace_once(
    dash,
    "  Future<void> _printStatement() async {\n    if (_activeDebts.isEmpty) {\n",
    "  Future<void> _printStatement() async {\n    if (!_totalsComplete) {\n      AppHelpers.showSnackBar(\n        context,\n        'کەشف دروست ناکرێت تا نرخی گۆڕینەوەی هەموو قەرزە USD ـەکان دیاری بکرێت.',\n        isError: true,\n      );\n      return;\n    }\n    if (_activeDebts.isEmpty) {\n",
    'dashboard statement safety',
)
dash = replace_once(
    dash,
    '                      AppHelpers.formatCurrency(_totalRemaining),\n',
    "                      _totalsComplete\n                          ? AppHelpers.formatCurrency(_totalRemaining)\n                          : '—',\n",
    'dashboard remaining display',
)
dash = replace_once(
    dash,
    '                            value: AppHelpers.formatCurrency(totalPaid),\n',
    "                            value: _totalsComplete\n                                ? AppHelpers.formatCurrency(totalPaid)\n                                : '—',\n",
    'dashboard paid display',
)
if 'کۆی گشتی بۆ پاراستنی دروستی نیشان نادرێت' not in dash:
    anchor = '''                    const SizedBox(height: 14),
                    Row(
                      children: [
'''
    warning = r'''                    if (!_totalsComplete) ...[
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
    dash = replace_once(dash, anchor, warning, 'dashboard warning')
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
if "group('Currency-safe debt summaries'" not in test:
    block = r'''

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
        debt(id: 'iqd', amount: 100000, remaining: 60000, currency: 'IQD'),
        debt(id: 'usd', amount: 50, remaining: 20, currency: 'USD', rate: 1500),
      ]);
      expect(summary.complete, isTrue);
      expect(summary.totalDebt, 175000);
      expect(summary.totalRemaining, 90000);
      expect(summary.totalPaid, 85000);
    });

    test('fails closed when a USD debt has no valid historical rate', () {
      final summary = AppHelpers.debtSummaryInIqd([
        debt(id: 'usd-no-rate', amount: 50, remaining: 20, currency: 'USD'),
      ]);
      expect(summary.complete, isFalse);
    });
  });
'''
    pos = test.rfind('\n}')
    require(pos >= 0, 'test closing brace')
    test = test[:pos] + block + test[pos:]
test_path.write_text(test, encoding='utf-8')


# ---------- Permanent verifier ----------
verify_path = Path('scripts/verify_online_only.py')
verify = verify_path.read_text(encoding='utf-8')
if '# Currency-safe financial totals:' not in verify:
    marker = '\n\nif violations:\n'
    block = r'''

# Currency-safe financial totals: never add raw USD values into IQD summaries.
helpers_source = (LIB / 'utils/helpers.dart').read_text(encoding='utf-8')
dashboard_source = (LIB / 'screens/customer/customer_dashboard.dart').read_text(encoding='utf-8')
for marker in ('debtValueInIqd', 'debtSummaryInIqd'):
    if marker not in helpers_source:
        fail(f'lib/utils/helpers.dart: currency-safe finance marker missing: {marker}')
for marker in ('AppHelpers.debtSummaryInIqd(_debts)', '_buildCurrencySummaryWarning', '_showIncompleteCurrencySummaryMessage'):
    if marker not in profile:
        fail(f'lib/screens/shared/user_profile_screen.dart: currency-safe summary marker missing: {marker}')
for marker in ('AppHelpers.debtSummaryInIqd(allDebts)', '_totalsComplete'):
    if marker not in dashboard_source:
        fail(f'lib/screens/customer/customer_dashboard.dart: currency-safe dashboard marker missing: {marker}')
'''
    verify = replace_once(verify, marker, block + marker, 'currency verifier')
verify_path.write_text(verify, encoding='utf-8')
