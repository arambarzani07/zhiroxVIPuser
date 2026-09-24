import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/screens/shared/payment_receipt_actions.dart';
import 'package:zhirox/services/financial_ui_state.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

/// Single source of truth for recording debt payments from every screen.
///
/// A payment opened from the customer profile is a general payment: it reduces
/// only the customer's effective total balance and never mutates individual
/// debt rows. A payment opened from one concrete debt remains debt-specific and
/// changes only that selected debt.
class FinancialPaymentFlow {
  FinancialPaymentFlow._();

  static const String _allDebtsId = '__all_open_debts__';

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

  static String _customerId(RecordModel debt) {
    final compat = debt.getStringValue('customer').trim();
    if (compat.isNotEmpty) return compat;
    return debt.getStringValue('customer_id').trim();
  }

  static Widget _buildPaymentProgress(
    FinancialPaymentStep step,
    bool isDark,
  ) {
    const steps = [
      (FinancialPaymentStep.target, 'قەرز'),
      (FinancialPaymentStep.amount, 'بڕ'),
      (FinancialPaymentStep.review, 'پشتڕاستکردنەوە'),
    ];
    final currentIndex = steps.indexWhere((entry) => entry.$1 == step);
    return Row(
      children: List.generate(steps.length * 2 - 1, (index) {
        if (index.isOdd) {
          final connectorIndex = index ~/ 2;
          final completed = connectorIndex < currentIndex;
          return Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              color: completed
                  ? AppColors.primary
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : const Color(0xFFE4E7EC)),
            ),
          );
        }
        final stepIndex = index ~/ 2;
        final active = stepIndex == currentIndex;
        final completed = stepIndex < currentIndex;
        final color = active || completed
            ? AppColors.primary
            : (isDark
                ? AppDarkColors.textSecondary
                : const Color(0xFF98A2B3));
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 25,
              height: 25,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active || completed
                    ? AppColors.primary.withValues(alpha: active ? 0.16 : 0.10)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : const Color(0xFFF2F4F7)),
                shape: BoxShape.circle,
                border: Border.all(
                  color: active || completed
                      ? AppColors.primary.withValues(alpha: 0.45)
                      : Colors.transparent,
                ),
              ),
              child: completed
                  ? Icon(Icons.check_rounded, size: 14, color: color)
                  : Text(
                      '${stepIndex + 1}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
            ),
            const SizedBox(height: 3),
            Text(
              steps[stepIndex].$2,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        );
      }),
    );
  }

  static Widget _buildInlineReview({
    required bool isGeneral,
    required RecordModel? debt,
    required double before,
    required double amount,
    required double after,
    required bool isDark,
  }) {
    final amountText = isGeneral
        ? AppHelpers.formatCurrency(amount)
        : _formatDisplay(debt!, amount);
    final beforeText = isGeneral
        ? AppHelpers.formatCurrency(before)
        : _formatDisplay(debt!, before);
    final afterText = isGeneral
        ? AppHelpers.formatCurrency(after)
        : _formatDisplay(debt!, after);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: isDark ? 0.09 : 0.055),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(
                Icons.fact_check_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              SizedBox(width: 7),
              Text(
                'پێداچوونەوەی کۆتایی',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _confirmationRow(
            'جۆری پارەدان',
            isGeneral ? 'پارەدانەوەی گشتی' : 'پارەدانەوەی مامەڵە',
            isDark,
          ),
          const SizedBox(height: 7),
          _confirmationRow('ماوەی پێش پارەدان', beforeText, isDark),
          const SizedBox(height: 7),
          _confirmationRow(
            'بڕی پارەدان',
            amountText,
            isDark,
            valueColor: Colors.green.shade700,
          ),
          const Divider(height: 18),
          _confirmationRow(
            'ماوەی دوای پارەدان',
            afterText,
            isDark,
            valueColor: after <= 0 ? Colors.green : Colors.orange,
            emphasized: true,
          ),
          const SizedBox(height: 8),
          Text(
            isGeneral
                ? 'تەنها کۆی گشتی قەرزی کڕیار کەم دەبێتەوە؛ هیچ مامەڵەیەکی تاکەکەسی دەستکاری ناکرێت.'
                : 'تەنها ئەم مامەڵەیە کەم دەبێتەوە و هیچ قەرزێکی تر کاریگەری وەرناگرێت.',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppDarkColors.textSecondary
                  : const Color(0xFF667085),
            ),
          ),
        ],
      ),
    );
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

  static Future<Map<String, dynamic>> _recordCustomerPayment({
    required String customerId,
    required double amount,
    required String note,
    String? referenceKind,
    String? referenceId,
  }) async {
    await PBService.ensureInitialized();
    final response = await PBService.client.functions.invoke(
      'record-payment',
      body: {
        'customer_id': customerId,
        'amount': amount,
        'note': note,
        'reference_kind': referenceKind,
        'reference_id': referenceId,
      },
    );
    final raw = response.data;
    if (raw is! Map) {
      throw Exception('پارەدانەوە تۆمار نەکرا');
    }
    final data = Map<String, dynamic>.from(raw);
    if (data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    return data;
  }

  static Future<void> _notifyCustomerPayment({
    required String customerId,
    required String senderId,
    required String senderName,
    required double amount,
    required double remaining,
  }) async {
    try {
      final amountText = AppHelpers.formatCurrency(amount);
      final remainingText = AppHelpers.formatCurrency(remaining);
      final message = remaining <= 0
          ? '✅ هەموو قەرزەکانت بە تەواوی دراونەتەوە!\nبڕی دراو: $amountText لەلایەن $senderName 🎉'
          : '💰 پارەدانەوەی $amountText تۆمارکرا.\nلەلایەن $senderName\nکۆی ماوە: $remainingText';
      await PBService.createNotification(
        customerId: customerId,
        message: message,
        senderId: senderId,
        type: 'payment',
      );
    } catch (_) {}
  }

  static Future<void> _showCustomerPaymentResult({
    required BuildContext context,
    required double amount,
    required double remaining,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green),
            SizedBox(width: 8),
            Expanded(child: Text('پارەدانەوەی گشتی تۆمارکرا')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _confirmationRow(
              'بڕی وەرگیراو',
              AppHelpers.formatCurrency(amount),
              isDark,
              valueColor: Colors.green.shade700,
              emphasized: true,
            ),
            const SizedBox(height: 10),
            _confirmationRow('جۆر', 'پارەدانەوەی گشتی', isDark),
            const SizedBox(height: 10),
            _confirmationRow(
              'کۆی ماوە',
              AppHelpers.formatCurrency(remaining),
              isDark,
              valueColor: remaining <= 0 ? Colors.green : Colors.orange,
            ),
            const SizedBox(height: 10),
            Text(
              'هیچ مامەڵەیەکی تاکەکەسی دەستکاری نەکرا.',
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? AppDarkColors.textSecondary
                    : const Color(0xFF667085),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('باشە'),
          ),
        ],
      ),
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

    final customerIds = openDebts
        .map(_customerId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final canPayAll = openDebts.length > 1 && customerIds.length == 1;
    final customerId = customerIds.length == 1 ? customerIds.first : '';
    final customerBalance = _customerOpenBalance(openDebts);

    final amountController = TextEditingController();
    final noteController = TextEditingController();
    var selectedDebtId = canPayAll ? _allDebtsId : openDebts.first.id;
    if (initialDebtId != null &&
        openDebts.any((debt) => debt.id == initialDebtId)) {
      selectedDebtId = initialDebtId;
    }

    RecordModel selectedDebt() => openDebts.firstWhere(
          (debt) => debt.id == selectedDebtId,
          orElse: () => openDebts.first,
        );

    if (initialStorageAmount != null && initialStorageAmount > 0) {
      if (selectedDebtId == _allDebtsId) {
        final safeStorage = initialStorageAmount
            .clamp(0.0, customerBalance)
            .toDouble();
        if (safeStorage > 0) amountController.text = _inputAmount(safeStorage);
      } else {
        final debt = selectedDebt();
        final remaining = debt.getDoubleValue('remaining');
        final safeStorage = initialStorageAmount.clamp(0.0, remaining).toDouble();
        if (safeStorage > 0) {
          amountController.text = _inputAmount(_storageToDisplay(debt, safeStorage));
        }
      }
    }

    var saving = false;
    var showNote = false;
    var reviewMode = false;
    String? localError;
    var saved = false;
    var customerWideSaved = false;
    var savedCustomerAmount = 0.0;
    var savedCustomerRemaining = 0.0;
    var savedAllocationCount = 0;
    RecordModel? savedPayment;
    RecordModel? savedDebt;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
            final isAll = selectedDebtId == _allDebtsId;
            final debt = isAll ? null : selectedDebt();
            final remainingStorage = isAll
                ? customerBalance
                : debt!.getDoubleValue('remaining');
            final currency = isAll ? 'IQD' : _currency(debt!);
            final typedDisplayAmount = double.tryParse(
                  amountController.text.trim().replaceAll(',', ''),
                ) ??
                0;
            final typedStorageAmount = isAll
                ? typedDisplayAmount
                : _displayToStorage(debt!, typedDisplayAmount);
            final remainingAfter = (remainingStorage - typedStorageAmount)
                .clamp(0.0, remainingStorage)
                .toDouble();
            final paymentStep = resolveFinancialPaymentStep(
              targetSelected: selectedDebtId.isNotEmpty,
              amount: typedStorageAmount,
              maximum: remainingStorage,
              reviewRequested: reviewMode,
            );
            var previewAllocationCount = 1;
            if (isAll &&
                typedStorageAmount > 0 &&
                typedStorageAmount <= remainingStorage + 0.0001) {
              try {
                previewAllocationCount =
                    _customerAllocations(openDebts, typedStorageAmount).length;
              } catch (_) {}
            }

            void applyQuickAmount(double storageValue) {
              final safeStorage = storageValue
                  .clamp(0.0, remainingStorage)
                  .toDouble();
              amountController.text = _inputAmount(
                isAll ? safeStorage : _storageToDisplay(debt!, safeStorage),
              );
              amountController.selection = TextSelection.collapsed(
                offset: amountController.text.length,
              );
              setSheetState(() {
                localError = null;
                reviewMode = false;
              });
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
                      isAll
                          ? 'بڕی پارەدان بنووسە؛ سیستەم بە خۆکار لە هەموو قەرزە ماوەکان دابەشی دەکات.'
                          : openDebts.length > 1
                              ? 'قەرز هەڵبژێرە و بڕی پارەدانەوە بنووسە.'
                              : 'بڕی پارەدانەوە بنووسە.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppDarkColors.textSecondary
                            : const Color(0xFF667085),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildPaymentProgress(paymentStep, isDark),
                    const SizedBox(height: 16),
                    if (openDebts.length > 1) ...[
                      DropdownButtonFormField<String>(
                        initialValue: selectedDebtId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'قەرز',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          if (canPayAll)
                            DropdownMenuItem<String>(
                              value: _allDebtsId,
                              child: Text(
                                'هەموو قەرزەکان • ${AppHelpers.formatCurrency(customerBalance)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ...openDebts.map((item) {
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
                          }),
                        ],
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value == null) return;
                                amountController.clear();
                                setSheetState(() {
                                  selectedDebtId = value;
                                  localError = null;
                                  reviewMode = false;
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
                                debt!.getStringValue('description').trim().isEmpty
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
                      onChanged: (_) => setSheetState(() {
                        localError = null;
                        reviewMode = false;
                      }),
                      decoration: InputDecoration(
                        labelText: 'بڕی پارەدانەوە',
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
                    const SizedBox(height: 10),
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
                          Expanded(
                            child: _confirmationRow(
                              isAll ? 'کۆی ماوەی ئێستا' : 'ماوەی ئێستا',
                              isAll
                                  ? AppHelpers.formatCurrency(remainingStorage)
                                  : _formatDisplay(debt!, remainingStorage),
                              isDark,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(Icons.arrow_back_rounded, size: 17),
                          ),
                          Expanded(
                            child: _confirmationRow(
                              'دوای پارەدان',
                              isAll
                                  ? AppHelpers.formatCurrency(remainingAfter)
                                  : _formatDisplay(debt!, remainingAfter),
                              isDark,
                              valueColor: remainingAfter <= 0
                                  ? Colors.green
                                  : Colors.orange,
                              emphasized: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isAll) ...[
                      const SizedBox(height: 8),
                      Text(
                        'هەموو قەرزەکان: ${openDebts.length} • کۆی ماوە: ${AppHelpers.formatCurrency(customerBalance)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppDarkColors.textSecondary
                              : const Color(0xFF667085),
                        ),
                      ),
                    ],
                    if (reviewMode &&
                        typedStorageAmount > 0 &&
                        typedStorageAmount <= remainingStorage + 0.0001) ...[
                      const SizedBox(height: 10),
                      _buildInlineReview(
                        isAll: isAll,
                        debt: debt,
                        before: remainingStorage,
                        amount: typedStorageAmount,
                        after: remainingAfter,
                        allocationCount: previewAllocationCount,
                        isDark: isDark,
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (showNote)
                      TextField(
                        controller: noteController,
                        enabled: !saving,
                        autofocus: true,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'تێبینی (ئارەزوومەندانە)',
                          prefixIcon: const Icon(Icons.notes_rounded),
                          suffixIcon: IconButton(
                            tooltip: 'لابردن',
                            onPressed: saving
                                ? null
                                : () {
                                    noteController.clear();
                                    setSheetState(() => showNote = false);
                                  },
                            icon: const Icon(Icons.close_rounded),
                          ),
                          border: const OutlineInputBorder(),
                        ),
                      )
                    else
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: saving
                              ? null
                              : () => setSheetState(() => showNote = true),
                          icon: const Icon(Icons.add_comment_outlined, size: 18),
                          label: const Text('زیادکردنی تێبینی'),
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

                              final storageAmount = isAll
                                  ? displayAmount
                                  : _displayToStorage(debt!, displayAmount);
                              if (storageAmount > remainingStorage + 0.0001) {
                                setSheetState(() => localError = isAll
                                    ? 'بڕی پارەدانەوە نابێت لە کۆی ماوەی کڕیار زیاتر بێت.'
                                    : 'بڕی پارەدانەوە نابێت لە ماوەی قەرز زیاتر بێت.');
                                return;
                              }

                              var allocationCount = 1;
                              if (isAll) {
                                try {
                                  allocationCount = _customerAllocations(
                                    openDebts,
                                    storageAmount,
                                  ).length;
                                } catch (_) {
                                  setSheetState(() => localError =
                                      'بڕی پارەدانەوە لە کۆی ماوەی کڕیار زیاترە.');
                                  return;
                                }
                              }

                              if (!reviewMode) {
                                FocusScope.of(sheetContext).unfocus();
                                setSheetState(() {
                                  reviewMode = true;
                                  localError = null;
                                });
                                return;
                              }

                              setSheetState(() {
                                saving = true;
                                localError = null;
                              });
                              try {
                                if (isAll) {
                                  if (customerId.isEmpty) {
                                    throw Exception('ناسنامەی کڕیار نەدۆزرایەوە');
                                  }
                                  final result = await _recordCustomerPayment(
                                    customerId: customerId,
                                    amount: storageAmount,
                                    note: noteController.text.trim(),
                                    referenceKind: referenceKind,
                                    referenceId: referenceId,
                                  );
                                  savedCustomerAmount =
                                      (result['amount'] as num?)?.toDouble() ?? storageAmount;
                                  savedCustomerRemaining =
                                      (result['remaining'] as num?)?.toDouble() ??
                                          (customerBalance - storageAmount)
                                              .clamp(0.0, customerBalance)
                                              .toDouble();
                                  savedAllocationCount = int.tryParse(
                                        '${result['allocation_count'] ?? allocationCount}',
                                      ) ??
                                      allocationCount;
                                  customerWideSaved = true;
                                  saved = true;

                                  final rawPayments = result['payments'];
                                  if (savedAllocationCount == 1 &&
                                      rawPayments is List &&
                                      rawPayments.isNotEmpty &&
                                      rawPayments.first is Map) {
                                    final row = Map<String, dynamic>.from(
                                      rawPayments.first as Map,
                                    );
                                    final paymentId = row['id']?.toString() ?? '';
                                    final debtId = row['debt_id']?.toString() ?? '';
                                    if (paymentId.isNotEmpty && debtId.isNotEmpty) {
                                      try {
                                        savedPayment = await PBService.pb
                                            .collection('payments')
                                            .getOne(paymentId);
                                        savedDebt = await PBService.getDebt(debtId);
                                      } catch (_) {}
                                    }
                                  }

                                  await _notifyCustomerPayment(
                                    customerId: customerId,
                                    senderId: createdBy,
                                    senderName: createdByName.isEmpty
                                        ? 'بەڕێوەبەر'
                                        : createdByName,
                                    amount: savedCustomerAmount,
                                    remaining: savedCustomerRemaining,
                                  );
                                } else {
                                  final payment = await PBService.createPayment(
                                    debtId: debt!.id,
                                    amount: storageAmount,
                                    note: noteController.text.trim(),
                                    createdBy: createdBy,
                                    createdByName: createdByName,
                                    referenceKind: referenceKind,
                                    referenceId: referenceId,
                                  );
                                  savedPayment = payment;
                                  try {
                                    savedDebt = await PBService.getDebt(debt.id);
                                  } catch (_) {
                                    savedDebt = debt;
                                  }
                                  saved = true;
                                }
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
                          : Icon(
                              reviewMode
                                  ? Icons.check_rounded
                                  : Icons.navigate_next_rounded,
                            ),
                      label: Text(
                        saving
                            ? 'تۆمار دەکرێت...'
                            : reviewMode
                                ? 'تۆمارکردنی پارەدانەوە'
                                : 'پێداچوونەوە',
                      ),
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
        customerWideSaved && savedAllocationCount > 1
            ? 'پارەدانەوە بە سەرکەوتوویی لە $savedAllocationCount قەرز دابەش کرا'
            : 'پارەدانەوە بە سەرکەوتوویی تۆمارکرا',
      );

      if (customerWideSaved && savedAllocationCount > 1) {
        await _showCustomerPaymentResult(
          context: context,
          amount: savedCustomerAmount,
          remaining: savedCustomerRemaining,
          allocationCount: savedAllocationCount,
        );
      } else {
        final payment = savedPayment;
        final debt = savedDebt;
        if (payment != null && debt != null && context.mounted) {
          await PaymentReceiptActions.show(
            context,
            payment: payment,
            debt: debt,
          );
        }
      }
    }
    return saved;
  }
}
