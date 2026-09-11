import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

/// Single source of truth for recording debt payments from every screen.
///
/// Debt/payment amounts are stored in the backend's base IQD amount. Legacy
/// debts that still carry `currency = USD` are displayed/entered in USD and
/// converted back to their stored IQD amount using `dollar_rate` before the
/// transactional `record_payment` RPC is called.
class FinancialPaymentFlow {
  FinancialPaymentFlow._();

  static String _currency(RecordModel debt) {
    final raw = debt.getStringValue('currency').trim().toUpperCase();
    if (raw == 'USD' && debt.getDoubleValue('dollar_rate') > 0) return 'USD';
    return 'IQD';
  }

  static double _storageToDisplay(RecordModel debt, double amount) {
    if (_currency(debt) != 'USD') return amount;
    final rate = debt.getDoubleValue('dollar_rate');
    return rate > 0 ? amount / rate : amount;
  }

  static double _displayToStorage(RecordModel debt, double amount) {
    if (_currency(debt) != 'USD') return amount;
    final rate = debt.getDoubleValue('dollar_rate');
    return rate > 0 ? amount * rate : amount;
  }

  static String _inputAmount(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }

  static String _formatDisplay(RecordModel debt, double storageAmount) {
    return AppHelpers.formatCurrencyWithType(
      _storageToDisplay(debt, storageAmount),
      _currency(debt),
      dollarRate: debt.getDoubleValue('dollar_rate'),
      showConversion: false,
    );
  }

  static Future<bool> _confirm({
    required BuildContext context,
    required RecordModel debt,
    required double storageAmount,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final remaining = debt.getDoubleValue('remaining');
    final after = (remaining - storageAmount).clamp(0.0, remaining).toDouble();
    final description = debt.getStringValue('description').trim();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.verified_outlined, color: Colors.green),
            SizedBox(width: 8),
            Expanded(child: Text('پشتڕاستکردنەوەی پارەدان')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (description.isNotEmpty) ...[
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
            ],
            _confirmationRow(
              'ماوەی پێش پارەدان',
              _formatDisplay(debt, remaining),
              isDark,
            ),
            const SizedBox(height: 8),
            _confirmationRow(
              'بڕی پارەدان',
              _formatDisplay(debt, storageAmount),
              isDark,
              valueColor: Colors.green.shade700,
            ),
            const Divider(height: 20),
            _confirmationRow(
              'ماوەی دوای پارەدان',
              _formatDisplay(debt, after),
              isDark,
              valueColor: after > 0 ? Colors.orange.shade800 : Colors.green.shade700,
              emphasized: true,
            ),
            if (after <= 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.done_all_rounded, color: Colors.green, size: 18),
                    SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'ئەم پارەدانە قەرزەکە بە تەواوی دادەخات.',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('پاشگەزبوونەوە'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('پشتڕاستە — تۆمار بکە'),
            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
          ),
        ],
      ),
    );
    return result == true;
  }

  static Widget _confirmationRow(
    String label,
    String value,
    bool isDark, {
    Color? valueColor,
    bool emphasized = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: emphasized ? 12.5 : 11.5,
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
              color: isDark
                  ? AppDarkColors.textSecondary
                  : const Color(0xFF667085),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: emphasized ? 14 : 12.5,
            fontWeight: FontWeight.w900,
            color: valueColor ??
                (isDark ? AppDarkColors.textPrimary : const Color(0xFF1D2939)),
          ),
        ),
      ],
    );
  }

  static Future<bool> show({
    required BuildContext context,
    required List<RecordModel> debts,
    required String createdBy,
    required String createdByName,
    String? initialDebtId,
    double? initialStorageAmount,
    String? referenceKind,
    String? referenceId,
  }) async {
    final openDebts = debts
        .where((debt) => debt.getDoubleValue('remaining') > 0)
        .toList(growable: false);
    if (openDebts.isEmpty) {
      AppHelpers.showSnackBar(context, 'هیچ قەرزێکی ماوە نییە');
      return false;
    }

    final amountController = TextEditingController();
    final noteController = TextEditingController();
    var selectedDebtId = openDebts.first.id;
    if (initialDebtId != null &&
        openDebts.any((debt) => debt.id == initialDebtId)) {
      selectedDebtId = initialDebtId;
    }

    RecordModel selectedDebt() => openDebts.firstWhere(
          (debt) => debt.id == selectedDebtId,
          orElse: () => openDebts.first,
        );

    if (initialStorageAmount != null && initialStorageAmount > 0) {
      final debt = selectedDebt();
      final remaining = debt.getDoubleValue('remaining');
      final safeStorage = initialStorageAmount.clamp(0.0, remaining).toDouble();
      if (safeStorage > 0) {
        amountController.text = _inputAmount(_storageToDisplay(debt, safeStorage));
      }
    }

    var saving = false;
    String? localError;
    var saved = false;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
            final debt = selectedDebt();
            final remainingStorage = debt.getDoubleValue('remaining');
            final remainingDisplay = _storageToDisplay(debt, remainingStorage);
            final currency = _currency(debt);

            void applyQuickAmount(double storageValue) {
              final safeStorage = storageValue
                  .clamp(0.0, remainingStorage)
                  .toDouble();
              amountController.text = _inputAmount(
                _storageToDisplay(debt, safeStorage),
              );
              amountController.selection = TextSelection.collapsed(
                offset: amountController.text.length,
              );
              setSheetState(() => localError = null);
            }

            return Container(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              decoration: BoxDecoration(
                color: isDark ? AppDarkColors.card : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD0D5DD),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'تۆمارکردنی پارەدانەوە',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      openDebts.length > 1
                          ? 'قەرز هەڵبژێرە و بڕی پارەدانەوە بنووسە.'
                          : 'بڕی پارەدانەوە بنووسە.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppDarkColors.textSecondary
                            : const Color(0xFF667085),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (openDebts.length > 1) ...[
                      DropdownButtonFormField<String>(
                        initialValue: selectedDebtId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'قەرز',
                          border: OutlineInputBorder(),
                        ),
                        items: openDebts.map((item) {
                          final description = item.getStringValue('description').trim();
                          final balance = item.getDoubleValue('remaining');
                          return DropdownMenuItem<String>(
                            value: item.id,
                            child: Text(
                              description.isEmpty
                                  ? 'ماوە: ${_formatDisplay(item, balance)}'
                                  : '$description • ${_formatDisplay(item, balance)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value == null) return;
                                amountController.clear();
                                setSheetState(() {
                                  selectedDebtId = value;
                                  localError = null;
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.07)
                                : const Color(0xFFE4E7EC),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.receipt_long_outlined, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                debt.getStringValue('description').trim().isEmpty
                                    ? 'قەرز'
                                    : debt.getStringValue('description').trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              _formatDisplay(debt, remainingStorage),
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: amountController,
                      enabled: !saving,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: 'بڕی پارەدانەوە',
                        helperText:
                            'ماوە: ${AppHelpers.formatCurrencyWithType(remainingDisplay, currency, showConversion: false)}',
                        suffixText: currency == 'USD' ? '\$' : 'د.ع',
                        prefixIcon: const Icon(Icons.payments_outlined),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: saving
                                ? null
                                : () => applyQuickAmount(remainingStorage * 0.25),
                            child: const Text('25%'),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: saving
                                ? null
                                : () => applyQuickAmount(remainingStorage * 0.50),
                            child: const Text('50%'),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: saving
                                ? null
                                : () => applyQuickAmount(remainingStorage),
                            child: const Text('تەواو'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      enabled: !saving,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'تێبینی (ئارەزوومەندانە)',
                        prefixIcon: Icon(Icons.notes_rounded),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (localError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        localError!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: saving
                          ? null
                          : () async {
                              final normalized = amountController.text
                                  .trim()
                                  .replaceAll(',', '');
                              final displayAmount = double.tryParse(normalized) ?? 0;
                              if (displayAmount <= 0) {
                                setSheetState(() => localError =
                                    'بڕێکی دروستی پارەدانەوە بنووسە.');
                                return;
                              }

                              final storageAmount =
                                  _displayToStorage(debt, displayAmount);
                              if (storageAmount > remainingStorage + 0.0001) {
                                setSheetState(() => localError =
                                    'بڕی پارەدانەوە نابێت لە ماوەی قەرز زیاتر بێت.');
                                return;
                              }

                              final confirmed = await _confirm(
                                context: sheetContext,
                                debt: debt,
                                storageAmount: storageAmount,
                              );
                              if (!confirmed || !sheetContext.mounted) return;

                              setSheetState(() {
                                saving = true;
                                localError = null;
                              });
                              try {
                                await PBService.createPayment(
                                  debtId: debt.id,
                                  amount: storageAmount,
                                  note: noteController.text.trim(),
                                  createdBy: createdBy,
                                  createdByName: createdByName,
                                  referenceKind: referenceKind,
                                  referenceId: referenceId,
                                );
                                saved = true;
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }
                              } catch (e) {
                                if (!sheetContext.mounted) return;
                                setSheetState(() {
                                  saving = false;
                                  localError = AppHelpers.backendErrorMessage(
                                    e,
                                    fallback:
                                        'پارەدانەوە تۆمار نەکرا. دووبارە هەوڵ بدە.',
                                  );
                                });
                              }
                            },
                      icon: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(saving ? 'تۆمار دەکرێت...' : 'تۆمارکردن'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: Colors.green.shade700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    } finally {
      amountController.dispose();
      noteController.dispose();
    }

    if (saved && context.mounted) {
      AppHelpers.showSnackBar(
        context,
        'پارەدانەوە بە سەرکەوتوویی تۆمارکرا',
      );
    }
    return saved;
  }
}
