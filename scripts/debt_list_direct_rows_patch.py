from pathlib import Path

path = Path('lib/screens/shared/debt_list_screen.dart')
text = path.read_text()

# Add a direct debt filtering/sorting model before build().
marker = "\n  @override\n  Widget build(BuildContext context) {\n"
if "List<RecordModel> _visibleDebts()" not in text:
    visible_method = r'''
  List<RecordModel> _visibleDebts() {
    final query = _searchController.text.trim().toLowerCase();
    final debts = _allDebts.where((debt) {
      final customer = debt.expand['customer']?.first;
      final customerName = customer?.getStringValue('name').toLowerCase() ?? '';
      final description = debt.getStringValue('description').toLowerCase();
      return query.isEmpty ||
          customerName.contains(query) ||
          description.contains(query);
    }).toList();

    switch (_sortMode) {
      case 'name':
        debts.sort((a, b) {
          final aName = a.expand['customer']?.first.getStringValue('name') ?? '';
          final bName = b.expand['customer']?.first.getStringValue('name') ?? '';
          return aName.compareTo(bName);
        });
        break;
      case 'amount':
        debts.sort(
          (a, b) => b
              .getDoubleValue('remaining')
              .compareTo(a.getDoubleValue('remaining')),
        );
        break;
      default:
        debts.sort((a, b) {
          final aPaid = a.getStringValue('status') == 'paid';
          final bPaid = b.getStringValue('status') == 'paid';
          if (aPaid != bPaid) return aPaid ? 1 : -1;
          return b.created.compareTo(a.created);
        });
    }
    return debts;
  }
'''
    if marker not in text:
        raise SystemExit('build marker not found')
    text = text.replace(marker, visible_method + marker, 1)

# Make build render debts directly rather than grouped customers.
old = "    final isDark = Theme.of(context).brightness == Brightness.dark;\n\n    return Directionality("
new = "    final isDark = Theme.of(context).brightness == Brightness.dark;\n    final visibleDebts = _visibleDebts();\n\n    return Directionality("
if old not in text:
    raise SystemExit('build local marker not found')
text = text.replace(old, new, 1)

text = text.replace("'${_customers.length} کڕیار'", "'${visibleDebts.length} قەرز'", 1)
text = text.replace(
    "onChanged: (_) =>\n                                  setState(() => _extractCustomers()),",
    "onChanged: (_) => setState(() {}),",
    1,
)
text = text.replace(
    "_searchController.clear();\n                                          setState(() => _extractCustomers());",
    "_searchController.clear();\n                                          setState(() {});",
    1,
)
text = text.replace("else if (_customers.isEmpty)", "else if (visibleDebts.isEmpty)", 1)
text = text.replace(
    "_buildCustomerTile(_customers[index], canPay)",
    "_buildDebtTile(visibleDebts[index], canPay)",
    1,
)
text = text.replace("childCount: _customers.length,", "childCount: visibleDebts.length,", 1)
text = text.replace(
    "_sortMode = mode;\n            _extractCustomers();",
    "_sortMode = mode;",
    1,
)

# Replace grouped customer cards with one compact row per debt.
start_marker = "  // ═══════════════════════════════════════════\n  // ── Customer Tile ──"
end_marker = "  // ═══════════════════════════════════════════\n  // ── Pay Dialog (centered) ──"
start = text.find(start_marker)
end = text.find(end_marker, start)
if start == -1 or end == -1:
    raise SystemExit('customer tile block markers not found')

debt_tile = r'''  // ═══════════════════════════════════════════
  // ── Direct Debt Tile ──
  // ═══════════════════════════════════════════

  Widget _buildDebtTile(RecordModel debt, bool canPay) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customer = debt.expand['customer']?.first;
    final customerName = customer?.getStringValue('name').isNotEmpty == true
        ? customer!.getStringValue('name')
        : 'کڕیاری نەناسراو';
    final status = debt.getStringValue('status');
    final isPaid = status == 'paid';
    final statusColor = status == 'paid'
        ? Colors.green
        : status == 'partial'
            ? Colors.blue
            : Colors.orange;
    final currency = debt.getStringValue('currency').isNotEmpty
        ? debt.getStringValue('currency')
        : 'IQD';
    final dollarRate = debt.getDoubleValue('dollar_rate');
    double amount = debt.getDoubleValue('amount');
    double remaining = debt.getDoubleValue('remaining');
    String displayCurrency = currency;
    if (currency == 'USD' && dollarRate > 0) {
      amount /= dollarRate;
      remaining /= dollarRate;
      displayCurrency = 'USD';
    }
    final description = debt.getStringValue('description').trim();
    final dateSource = debt.getStringValue('custom_date').isNotEmpty
        ? debt.getStringValue('custom_date')
        : debt.created;

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE9EDF3),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DebtDetailScreen(debtId: debt.id),
              ),
            ).then((_) => _loadAllDebts(showLoading: false));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isPaid
                        ? Icons.check_rounded
                        : Icons.receipt_long_outlined,
                    color: statusColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              customerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? AppDarkColors.textPrimary
                                    : const Color(0xFF1D2939),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              AppHelpers.statusName(status),
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              description.isNotEmpty ? description : 'قەرز',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? AppDarkColors.textSecondary
                                    : const Color(0xFF667085),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            AppHelpers.formatDate(dateSource),
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark
                                  ? AppDarkColors.textSecondary
                                  : const Color(0xFF98A2B3),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Text(
                            AppHelpers.formatCurrencyWithType(
                              amount,
                              displayCurrency,
                              dollarRate: dollarRate,
                              showConversion: false,
                            ),
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppDarkColors.textSecondary
                                  : const Color(0xFF667085),
                            ),
                          ),
                          if (!isPaid) ...[
                            const SizedBox(width: 8),
                            Text(
                              'ماوە ${AppHelpers.formatCurrencyWithType(
                                remaining,
                                displayCurrency,
                                dollarRate: dollarRate,
                                showConversion: false,
                              )}',
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.redAccent,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (canPay && !isPaid) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _showSinglePaymentDialog(debt),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.payments_outlined,
                        color: Colors.green,
                        size: 18,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_left_rounded,
                  size: 20,
                  color: isDark
                      ? AppDarkColors.textSecondary
                      : const Color(0xFF98A2B3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

'''
text = text[:start] + debt_tile + text[end:]

# Remove the duplicate customer-debts dialog and its row renderer entirely.
dialog_start_marker = "  // ═══════════════════════════════════════════\n  // ── Debts List Dialog ──"
single_payment_marker = "  // ═══════════════════════════════════════════\n  // ── Single Payment Dialog (centered) ──"
dialog_start = text.find(dialog_start_marker)
single_start = text.find(single_payment_marker, dialog_start)
if dialog_start == -1 or single_start == -1:
    raise SystemExit('debt dialog removal markers not found')
text = text[:dialog_start] + text[single_start:]

path.write_text(text)
