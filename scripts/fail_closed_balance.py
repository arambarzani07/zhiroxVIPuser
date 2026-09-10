from pathlib import Path
import re
import sys


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('.')

# PBService must propagate server/network balance failures instead of turning them into 0.
pb = root / 'lib/services/pb_service.dart'
text = pb.read_text()
old = """  static Future<double> getCustomerBalance(String customerId) async {
    try {
      final debts = await getDebts(customerId: customerId);
      return debts.fold<double>(
        0,
        (sum, debt) => sum + debt.getDoubleValue('remaining'),
      );
    } catch (_) {
      return 0;
    }
  }
"""
new = """  static Future<double> getCustomerBalance(String customerId) async {
    final debts = await getDebts(customerId: customerId);
    return debts.fold<double>(
      0,
      (sum, debt) => sum + debt.getDoubleValue('remaining'),
    );
  }
"""
require(old in text, 'getCustomerBalance fail-open block missing')
text = text.replace(old, new)
pb.write_text(text)

# AddDebt: fail closed if customer/balance cannot be verified.
add = root / 'lib/screens/shared/add_debt_screen.dart'
text = add.read_text()
pattern = re.compile(
    r"      // Check Debt Limit\n      try \{.*?      \}\n\n      if \(widget\.debt != null\) \{",
    re.S,
)
replacement = r'''      // Check Debt Limit. This is fail-closed: if the selected customer or
      // current server balance cannot be verified, do not create/update a debt.
      RecordModel? selectedCustomer;
      for (final customer in _customers) {
        if (customer.id == _selectedCustomerId) {
          selectedCustomer = customer;
          break;
        }
      }

      if (selectedCustomer == null) {
        if (!mounted) return;
        AppHelpers.showSnackBar(
          context,
          'نەتوانرا زانیاریی کڕیار پشتڕاست بکرێتەوە. دووبارە هەوڵ بدە.',
          isError: true,
        );
        setState(() => _isLoading = false);
        return;
      }

      final debtLimit = selectedCustomer.getDoubleValue('debt_limit');
      if (debtLimit > 0) {
        double currentBalance;
        try {
          currentBalance = await PBService.getCustomerBalance(
            _selectedCustomerId!,
          );
        } catch (_) {
          if (!mounted) return;
          AppHelpers.showSnackBar(
            context,
            'نەتوانرا باڵانسی کڕیار پشتڕاست بکرێتەوە. ئینتەرنێت بپشکنە و دووبارە هەوڵ بدە.',
            isError: true,
          );
          setState(() => _isLoading = false);
          return;
        }
        if (!mounted) return;

        if (currentBalance + totalNewDebt > debtLimit) {
          final canOverride = auth.canSetDebtLimit;

          if (canOverride) {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('سنوری قەرز تێپەڕیوە'),
                content: Text(
                  'بەکارهێنەر سنوری قەرزی تێپەڕاندووە.\n'
                  'سنور: ${AppHelpers.formatCurrency(debtLimit)}\n'
                  'کۆی گشتی: ${AppHelpers.formatCurrency(currentBalance + totalNewDebt)}\n\n'
                  'ئایا دەتەوێت بەردەوام بیت؟',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('نەخێر'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('بەڵێ، بەردەوام بە'),
                  ),
                ],
              ),
            );
            if (!mounted) return;
            if (confirm != true) {
              setState(() => _isLoading = false);
              return;
            }
          } else {
            AppHelpers.showSnackBar(
              context,
              'ناتوانیت ئەم قەرزە زیاد بکەیت! بەکارهێنەر سنوری قەرزی تێپەڕاندووە.\n'
              'سنور: ${AppHelpers.formatCurrency(debtLimit)}\n'
              'کۆی گشتی دوای زیادکردن: ${AppHelpers.formatCurrency(currentBalance + totalNewDebt)}',
              isError: true,
            );
            setState(() => _isLoading = false);
            return;
          }
        }
      }

      if (widget.debt != null) {'''
text, count = pattern.subn(replacement, text, count=1)
require(count == 1, f'AddDebt limit enforcement replacement count={count}')

# Replace limit warning widget so balance failures are visible instead of silently hidden.
start = text.find('  Widget _buildLimitWarning() {')
end = text.find('  Widget _buildCurrencyCard() {', start)
require(start >= 0 and end > start, 'limit warning widget boundaries missing')
warning = r'''  Widget _buildLimitWarning() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<double>(
      future: PBService.getCustomerBalance(_selectedCustomerId!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'باڵانسی کڕیار دەپشکنرێت...',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.orange.withValues(alpha: 0.24),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.cloud_off_rounded, size: 18, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'نەتوانرا باڵانسی کڕیار پشتڕاست بکرێتەوە. پاشەکەوتکردن تا گەڕانەوەی پەیوەندی ڕادەوەستێت.',
                    style: TextStyle(fontSize: 11.5, height: 1.5),
                  ),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) return const SizedBox.shrink();

        RecordModel? selectedCustomer;
        for (final customer in _customers) {
          if (customer.id == _selectedCustomerId) {
            selectedCustomer = customer;
            break;
          }
        }
        if (selectedCustomer == null) {
          return Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'زانیاری کڕیار بەردەست نییە. دووبارە کڕیار هەڵبژێرە.',
              style: TextStyle(fontSize: 11.5),
            ),
          );
        }

        final limit = selectedCustomer.getDoubleValue('debt_limit');
        final currentBalance = snapshot.data!;
        if (limit <= 0) return const SizedBox.shrink();

        final remainingLimit = limit - currentBalance;
        final isOver = remainingLimit < 0;
        final usagePercent = (currentBalance / limit).clamp(0.0, 1.0).toDouble();

        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isOver
                ? Colors.red.withValues(alpha: 0.05)
                : Colors.green.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isOver
                  ? Colors.red.withValues(alpha: 0.3)
                  : Colors.green.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    isOver
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    color: isOver ? Colors.red : Colors.green,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'سنوری قەرز: ${AppHelpers.formatCurrency(limit)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppDarkColors.textSecondary
                                : Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'قەرزی ئێستا: ${AppHelpers.formatCurrency(currentBalance)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isOver
                                ? Colors.red
                                : (isDark
                                    ? AppDarkColors.textPrimary
                                    : Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        isOver ? 'تێپەڕیوە' : 'بەردەستە',
                        style: TextStyle(
                          fontSize: 11,
                          color: isOver ? Colors.red : Colors.green,
                        ),
                      ),
                      Text(
                        AppHelpers.formatCurrency(remainingLimit.abs()),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isOver ? Colors.red : Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: usagePercent,
                  minHeight: 4,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isOver
                        ? Colors.red
                        : usagePercent > 0.8
                            ? Colors.orange
                            : Colors.green,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

'''
text = text[:start] + warning + text[end:]
add.write_text(text)

# Profile deletion already blocks on balance errors; make the message non-raw/friendly.
profile = root / 'lib/screens/shared/user_profile_screen.dart'
text = profile.read_text()
old_delete_error = """      } catch (e) {
        if (mounted) {
          AppHelpers.showSnackBar(
            context,
            'هەڵە لە پشکنینی باڵانس: $e',
            isError: true,
          );
        }
        return;
      }
"""
new_delete_error = """      } catch (_) {
        if (mounted) {
          AppHelpers.showSnackBar(
            context,
            'نەتوانرا باڵانسی کڕیار پشتڕاست بکرێتەوە. کڕیار ناسڕدرێتەوە تا پەیوەندی سێرڤەر دروست بێت.',
            isError: true,
          );
        }
        return;
      }
"""
require(old_delete_error in text, 'profile balance deletion error block missing')
text = text.replace(old_delete_error, new_delete_error, 1)
profile.write_text(text)
