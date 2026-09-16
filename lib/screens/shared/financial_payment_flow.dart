import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/screens/shared/payment_receipt_actions.dart';
import 'package:zhirox/services/customer_payment_allocator.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

/// Single source of truth for recording debt payments from every screen.
///
/// When opened from the customer-level payment action and more than one debt is
/// open, the default target is the customer's full open balance. The backend
/// distributes that amount atomically from the oldest open debt to the newest.
/// A payment opened from one concrete debt remains debt-specific.
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

  static DateTime _debtSortAt(RecordModel debt) {
    for (final key in const ['custom_date', 'created', 'created_at', 'updated']) {
      final raw = debt.getStringValue(key).trim();
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  static double _customerOpenBalance(List<RecordModel> debts) {
    return debts.fold<double>(
      0,
      (sum, debt) => sum + debt.getDoubleValue('remaining'),
    );
  }

  static List<CustomerPaymentAllocation> _customerAllocations(
    List<RecordModel> debts,
    double amount,
  ) {
    return allocateCustomerPayment(
      amount: amount,
      debts: debts
          .map(
            (debt) => CustomerPaymentDebt(
              id: debt.id,
              remaining: debt.getDoubleValue('remaining'),
              sortAt: _debtSortAt(debt),
            ),
          )
          .toList(growable: false),
    );
  }

  static Future<bool> _confirmSingle({
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
              _successHint('ئەم پارەدانە قەرزەکە بە تەواوی دادەخات.'),
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

  static Future<bool> _confirmCustomer({
    required BuildContext context,
    required double currentBalance,
    required double amount,
    required int allocationCount,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final after = (currentBalance - amount).clamp(0.0, currentBalance).toDouble();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.verified_outlined, color: Colors.green),
            SizedBox(width: 8),
            Expanded(child: Text('پشتڕاستکردنەوەی پارەدانی کڕیار')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _confirmationRow(
              'کۆی ماوەی کڕیار',
              AppHelpers.formatCurrency(currentBalance),
              isDark,
            ),
            const SizedBox(height: 8),
            _confirmationRow(
              'بڕی پارەدان',
              AppHelpers.formatCurrency(amount),
              isDark,
              valueColor: Colors.green.shade700,
            ),
            const SizedBox(height: 8),
            _confirmationRow(
              'ژمارەی قەرزی کاریگەر',
              '$allocationCount',
              isDark,
            ),
            const Divider(height: 20),
            _confirmationRow(
              'کۆی ماوە دوای پارەدان',
              AppHelpers.formatCurrency(after),
              isDark,
              valueColor: after > 0 ? Colors.orange.shade800 : Colors.green.shade700,
              emphasized: true,
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.account_tree_outlined, color: AppColors.primary, size: 18),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'بڕەکە بە خۆکار لە قەرزە کۆنترەکانەوە بەرەو نوێترەکان دابەش دەکرێت.',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (after <= 0) ...[
              const SizedBox(height: 10),
              _successHint('ئەم پارەدانە هەموو قەرزە ماوەکان دادەخات.'),
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

  static Widget _successHint(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.done_all_rounded, color: Colors.green, size: 18),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.green,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
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
    required int allocationCount,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green),
            SizedBox(width: 8),
            Expanded(child: Text('پارەدانەوە تۆمارکرا')),
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
            _confirmationRow(
              'لەسەر ژمارەی قەرز',
              '$allocationCount',
              isDark,
            ),
            const SizedBox(height: 10),
            _confirmationRow(
              'کۆی ماوە',
              AppHelpers.formatCurrency(remaining),
              isDark,
              valueColor: remaining <= 0 ? Colors.green : Colors.orange,
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
                      onChanged: (_) => setSheetState(() => localError = null),
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
                              bool confirmed;
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
                                confirmed = await _confirmCustomer(
                                  context: sheetContext,
                                  currentBalance: customerBalance,
                                  amount: storageAmount,
                                  allocationCount: allocationCount,
                                );
                              } else {
                                confirmed = await _confirmSingle(
                                  context: sheetContext,
                                  debt: debt!,
                                  storageAmount: storageAmount,
                                );
                              }
                              if (!confirmed || !sheetContext.mounted) return;

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
                          : const Icon(Icons.check_rounded),
                      label: Text(
                        saving ? 'تۆمار دەکرێت...' : 'پێداچوونەوە و تۆمارکردن',
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
