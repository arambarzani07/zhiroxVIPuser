import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/screens/shared/add_debt_screen.dart';
import 'package:zhirox/screens/shared/financial_payment_flow.dart';
import 'package:zhirox/screens/shared/financial_document_actions.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class DebtDetailScreen extends StatefulWidget {
  final String debtId;

  const DebtDetailScreen({super.key, required this.debtId});

  @override
  State<DebtDetailScreen> createState() => _DebtDetailScreenState();
}

class _DebtDetailScreenState extends State<DebtDetailScreen>
    with SingleTickerProviderStateMixin {
  RecordModel? _debt;
  List<RecordModel> _payments = [];
  List<Map<String, dynamic>> _installments = const [];
  double? _customerTotalPaidIqd;
  double? _customerTotalRemainingIqd;
  bool _isLoading = true;
  String? _loadError;
  final Set<String> _deletingPaymentIds = <String>{};
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _loadData();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final debt = await PBService.getDebt(widget.debtId);
      final paymentsFuture = PBService.getPayments(debtId: widget.debtId);
      final installmentsFuture = PBService.getDebtInstallments(widget.debtId)
          .catchError((_) => <Map<String, dynamic>>[]);
      final customerId = debt.getStringValue('customer').trim();
      Map<String, dynamic>? customerSnapshot;
      if (customerId.isNotEmpty) {
        try {
          customerSnapshot = await PBService.getCustomerFinanceSnapshot(customerId);
        } catch (_) {
          // Debt details remain usable if the aggregate summary is temporarily
          // unavailable; never replace it with a misleading debt-only total.
        }
      }
      final payments = await paymentsFuture;
      final installments = await installmentsFuture;
      if (!mounted) return;

      setState(() {
        _debt = debt;
        _payments = payments;
        _installments = installments;
        _customerTotalPaidIqd =
            (customerSnapshot?['totalPaidIqd'] as num?)?.toDouble();
        _customerTotalRemainingIqd =
            (customerSnapshot?['totalRemainingIqd'] as num?)?.toDouble();
        _isLoading = false;
        _loadError = null;
      });
      _animController.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _debt = null;
        _payments = [];
        _installments = const [];
        _customerTotalPaidIqd = null;
        _customerTotalRemainingIqd = null;
        _isLoading = false;
        _loadError = AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا وردەکاری قەرز لە سێرڤەر وەربگیرێت. دووبارە هەوڵ بدە.',
        );
      });
    }
  }

  Future<void> _printDebtInvoice() async {
    final debt = _debt;
    if (debt == null) return;
    await FinancialDocumentActions.generateDebtInvoice(context, debt);
  }

  Future<void> _editCurrentDebt() async {
    if (_debt == null) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddDebtScreen(
          debt: _debt,
          customerId: _debt!.getStringValue('customer'),
        ),
      ),
    );
    if (result == true && mounted) {
      await _loadData();
    }
  }

  Future<void> _showInstallmentDialog() async {
    final debt = _debt;
    if (debt == null) return;

    final remaining = debt.getDoubleValue('remaining');
    if (remaining <= 0) {
      AppHelpers.showSnackBar(context, 'ئەم قەرزە تەواو دراوەتەوە.');
      return;
    }

    final pending = _installments
        .where((item) => item['status']?.toString() == 'pending')
        .toList(growable: false);
    var count = pending.length >= 2 ? pending.length.clamp(2, 12).toInt() : 2;
    var intervalDays = 30;

    DateTime firstDue = DateTime.now().add(const Duration(days: 30));
    if (pending.isNotEmpty) {
      firstDue = DateTime.tryParse(pending.first['due_date']?.toString() ?? '') ??
          firstDue;
      if (pending.length > 1) {
        final secondDue =
            DateTime.tryParse(pending[1]['due_date']?.toString() ?? '');
        if (secondDue != null) {
          intervalDays = secondDue.difference(firstDue).inDays.clamp(1, 90).toInt();
        }
      }
    } else {
      final debtDue = DateTime.tryParse(debt.getStringValue('due_date'));
      if (debtDue != null && debtDue.isAfter(DateTime.now())) {
        firstDue = debtDue;
      }
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final previewAmount = remaining / count;
          return AlertDialog(
            scrollable: true,
            title: const Text('پلانی قسط'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: count,
                  decoration: const InputDecoration(
                    labelText: 'ژمارەی قسطەکان',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (var value = 2; value <= 12; value++)
                      DropdownMenuItem(
                        value: value,
                        child: Text('${value} قسط'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => count = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: intervalDays,
                  decoration: const InputDecoration(
                    labelText: 'ماوەی نێوان قسطەکان',
                    border: OutlineInputBorder(),
                  ),
                  items: const [7, 14, 30, 45, 60, 90]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('${value} ڕۆژ'),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => intervalDays = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('بەرواری یەکەم قسط'),
                  subtitle: Text(
                    '${firstDue.year.toString().padLeft(4, '0')}-'
                    '${firstDue.month.toString().padLeft(2, '0')}-'
                    '${firstDue.day.toString().padLeft(2, '0')}',
                  ),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: firstDue,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(
                        const Duration(days: 3650),
                      ),
                    );
                    if (picked != null) {
                      setDialogState(() => firstDue = picked);
                    }
                  },
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    'بڕی نزیکەی هەر قسط: ${AppHelpers.formatCurrency(previewAmount)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('پاشگەزبوونەوە'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop({
                  'count': count,
                  'interval_days': intervalDays,
                  'first_due': firstDue,
                }),
                icon: const Icon(Icons.save_outlined),
                label: const Text('پاشەکەوتکردن'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || result == null) return;

    final selectedCount = result['count'] as int;
    final selectedInterval = result['interval_days'] as int;
    final selectedFirstDue = result['first_due'] as DateTime;
    final baseAmount =
        double.parse((remaining / selectedCount).toStringAsFixed(2));
    final schedule = <Map<String, dynamic>>[];
    var allocated = 0.0;
    for (var index = 0; index < selectedCount; index++) {
      final isLast = index == selectedCount - 1;
      final installmentAmount = isLast
          ? double.parse((remaining - allocated).toStringAsFixed(2))
          : baseAmount;
      allocated += installmentAmount;
      final due =
          selectedFirstDue.add(Duration(days: selectedInterval * index));
      schedule.add({
        'amount': installmentAmount,
        'due_date':
            '${due.year.toString().padLeft(4, '0')}-'
            '${due.month.toString().padLeft(2, '0')}-'
            '${due.day.toString().padLeft(2, '0')}',
      });
    }

    try {
      final installments = await PBService.setDebtInstallmentSchedule(
        widget.debtId,
        schedule,
      );
      if (!mounted) return;
      setState(() => _installments = installments);
      AppHelpers.showSnackBar(
        context,
        'پلانی ${selectedCount} قسط پاشەکەوت کرا؛ هەر قسط reminder ـی خۆی هەیە.',
      );
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'پاشەکەوتکردنی پلانی قسط سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _handleDebtAction(String action) async {
    try {
      switch (action) {
        case 'print':
          await _printDebtInvoice();
          break;
        case 'edit':
          await _editCurrentDebt();
          break;
        case 'installments':
          await _showInstallmentDialog();
          break;
        case 'delete':
          await _confirmDelete();
          break;
      }
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا کردارەکە ئەنجام بدرێت. دووبارە هەوڵ بدە.',
        ),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isCustomer = auth.userRole == 'customer';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark
            ? AppDarkColors.background
            : const Color(0xFFF5F7FA),
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        backgroundColor: isDark
            ? AppDarkColors.background
            : const Color(0xFFF5F7FA),
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 42, color: Colors.orange),
                const SizedBox(height: 12),
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    height: 1.6,
                    color: isDark
                        ? AppDarkColors.textPrimary
                        : const Color(0xFF344054),
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('دووبارە هەوڵ بدە'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_debt == null) {
      return Scaffold(
        backgroundColor: isDark
            ? AppDarkColors.background
            : const Color(0xFFF5F7FA),
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(child: Text('قەرز نەدۆزرایەوە')),
      );
    }

    final status = _debt!.getStringValue('status');
    final amount = _debt!.getDoubleValue('amount');
    final remaining = _debt!.getDoubleValue('remaining');
    final currency = _debt!.getStringValue('currency');
    final dollarRate = _debt!.getDoubleValue('dollar_rate');
    final paid = amount - remaining;
    final paidPercent = amount > 0 ? paid / amount : 0.0;
    final statusColor = AppHelpers.statusColor(status);

    final customer = AppHelpers.expandedRecord(_debt!, 'customer');
    final customerName = customer?.getStringValue('name') ?? '';

    return Scaffold(
      backgroundColor: isDark
          ? AppDarkColors.background
          : const Color(0xFFF5F7FA),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              color: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'گەڕانەوە',
                            icon: Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 20,
                              color: isDark
                                  ? AppDarkColors.textPrimary
                                  : const Color(0xFF344054),
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                          Expanded(
                            child: Text(
                              'وردەکاری قەرز',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? AppDarkColors.textPrimary
                                    : const Color(0xFF101828),
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'کردارەکان',
                            onSelected: _handleDebtAction,
                            icon: Icon(
                              Icons.more_horiz_rounded,
                              color: isDark
                                  ? AppDarkColors.textPrimary
                                  : const Color(0xFF344054),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'print',
                                child: Row(
                                  children: [
                                    Icon(Icons.print_outlined, size: 19),
                                    SizedBox(width: 10),
                                    Text('چاپ / وەسڵ'),
                                  ],
                                ),
                              ),
                              if (!isCustomer && auth.canEditDebts)
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined, size: 19),
                                      SizedBox(width: 10),
                                      Text('دەستکاری'),
                                    ],
                                  ),
                                ),
                              if (!isCustomer &&
                                  (auth.userRole == 'admin' ||
                                      auth.canEditDebts) &&
                                  status != 'paid')
                                const PopupMenuItem(
                                  value: 'installments',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_month_outlined,
                                        size: 19,
                                      ),
                                      SizedBox(width: 10),
                                      Text('پلانی قسط'),
                                    ],
                                  ),
                                ),
                              if (!isCustomer && auth.userRole == 'admin')
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete_outline_rounded,
                                        size: 19,
                                        color: Colors.red,
                                      ),
                                      SizedBox(width: 10),
                                      Text(
                                        'سڕینەوە',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        status == 'paid' ? 'کۆی قەرز' : 'ماوەی قەرز',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.78),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        AppHelpers.formatCurrencyWithType(
                                          (currency == 'USD' && dollarRate > 0)
                                              ? (status == 'paid' ? amount : remaining) /
                                                  dollarRate
                                              : (status == 'paid' ? amount : remaining),
                                          (currency == 'USD' && dollarRate > 0)
                                              ? 'USD'
                                              : 'IQD',
                                          dollarRate: dollarRate,
                                          showConversion: false,
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                          height: 1.1,
                                        ),
                                        textDirection: TextDirection.ltr,
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          color: statusColor,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        AppHelpers.statusName(status),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (customerName.isNotEmpty ||
                                _debt!.getStringValue('description').isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                [
                                  if (customerName.isNotEmpty) customerName,
                                  if (_debt!.getStringValue('description').isNotEmpty)
                                    _debt!.getStringValue('description'),
                                ].join('  •  '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.82),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: paidPercent.clamp(0.0, 1.0),
                                minHeight: 5,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.20),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  '${(paidPercent.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}% دراوەی ئەم قەرزە',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.76),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'دراوەی ئەم قەرزە: ${AppHelpers.formatCurrency(paid)}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.76),
                                    fontSize: 10.5,
                                  ),
                                  textDirection: TextDirection.ltr,
                                ),
                              ],
                            ),
                            if (_customerTotalPaidIqd != null) ...[
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  Text(
                                    'کۆی هەموو پارەدانەوەکان',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.90),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    AppHelpers.formatCurrency(
                                      _customerTotalPaidIqd!,
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                    textDirection: TextDirection.ltr,
                                  ),
                                ],
                              ),
                            ],
                            if (_customerTotalRemainingIqd != null) ...[
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Text(
                                    'کۆی قەرزی ماوەی کڕیار',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.78),
                                      fontSize: 10.5,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    AppHelpers.formatCurrency(
                                      _customerTotalRemainingIqd!,
                                    ),
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.90),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textDirection: TextDirection.ltr,
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? AppDarkColors.card : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFE9EDF3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildMetaCell(
                          Icons.monetization_on_outlined,
                          'کۆی قەرز',
                          AppHelpers.formatCurrency(amount),
                          AppColors.primary,
                        ),
                        _buildMetaCell(
                          Icons.event_outlined,
                          'بەرواری دانەوە',
                          _debt!.getStringValue('due_date').isEmpty
                              ? 'دیاری نەکراوە'
                              : AppHelpers.formatDate(
                                  _debt!.getStringValue('due_date'),
                                ),
                          Colors.orange,
                        ),
                      ],
                    ),
                    Divider(
                      height: 1,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFF0F2F5),
                    ),
                    Row(
                      children: [
                        _buildMetaCell(
                          Icons.calendar_month_outlined,
                          'بەرواری قەرز',
                          AppHelpers.formatDate(
                            _debt!.getStringValue('custom_date').isNotEmpty
                                ? _debt!.getStringValue('custom_date')
                                : _debt!.getStringValue('created'),
                          ),
                          Colors.purple,
                        ),
                        _buildMetaCell(
                          Icons.schedule_outlined,
                          'کاتژمێر',
                          AppHelpers.formatTime(
                            _debt!.getStringValue('custom_date').isNotEmpty
                                ? _debt!.getStringValue('custom_date')
                                : _debt!.getStringValue('created'),
                          ),
                          Colors.teal,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          ..._buildItemsSliver(),

          ..._buildInstallmentSliver(
            isDark: isDark,
            canEdit: !isCustomer &&
                (auth.userRole == 'admin' || auth.canEditDebts) &&
                status != 'paid',
            currency: currency,
            dollarRate: dollarRate,
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.payments_outlined,
                      size: 19,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.payments,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? AppDarkColors.textPrimary
                                : const Color(0xFF1D2939),
                          ),
                        ),
                        Text(
                          '${_payments.length} تۆمار',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark
                                ? AppDarkColors.textSecondary
                                : const Color(0xFF98A2B3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isCustomer &&
                      (auth.userRole == 'admin' || auth.canRecordPayments) &&
                      status != 'paid')
                    TextButton.icon(
                      onPressed: _showAddPaymentDialog,
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('پارەدانەوە'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: Colors.green.withValues(alpha: 0.18),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          ..._buildReceiptSliver(isDark),

          if (_payments.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Column(
                  children: [
                    Icon(
                      Icons.payments_outlined,
                      size: 30,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'هیچ پارەدانەوەیەک نییە',
                      style: TextStyle(color: Colors.grey[500], fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      _buildPaymentCard(_payments[index], index),
                  childCount: _payments.length,
                ),
              ),
            ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 30)),
        ],
      ),
    );
  }

  Widget _buildMetaCell(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark
                          ? AppDarkColors.textSecondary
                          : const Color(0xFF98A2B3),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppDarkColors.textPrimary
                          : const Color(0xFF344054),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildItemsSliver() {
    if (_debt == null) return [];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    try {
      final rawItems = _debt!.data['items'];
      List itemsList = [];
      if (rawItems is String) {
        if (rawItems.isEmpty || rawItems == '[]') return [];
        itemsList = jsonDecode(rawItems);
      } else if (rawItems is List) {
        itemsList = rawItems;
      } else {
        return [];
      }
      if (itemsList.isEmpty) return [];

      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppDarkColors.card : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFE9EDF3),
                ),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.shopping_bag_outlined,
                          size: 17,
                          color: isDark
                              ? AppDarkColors.textSecondary
                              : const Color(0xFF667085),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'کاڵاکان',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppDarkColors.textPrimary
                                  : const Color(0xFF344054),
                            ),
                          ),
                        ),
                        Text(
                          '${itemsList.length}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppDarkColors.textSecondary
                                : const Color(0xFF98A2B3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF0F2F5),
                  ),
                  ...itemsList.asMap().entries.map((entry) {
                    final item = entry.value;
                    final name = (item is Map ? item['name'] : '') ?? '';
                    final qty =
                        (item is Map ? item['quantity'] ?? item['qty'] : 1) ?? 1;
                    final price = (item is Map ? item['price'] : 0) ?? 0;
                    final itemCurrency =
                        (item is Map ? item['currency'] : null) ??
                            _debt!.getStringValue('currency');
                    final total = (price is num ? price.toDouble() : 0.0) *
                        (qty is num ? qty.toDouble() : 1.0);

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        border: entry.key == itemsList.length - 1
                            ? null
                            : Border(
                                bottom: BorderSide(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.04)
                                      : const Color(0xFFF4F5F7),
                                ),
                              ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              '$qty×',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                              textDirection: TextDirection.ltr,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              '$name',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppDarkColors.textPrimary
                                    : const Color(0xFF344054),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppHelpers.formatCurrencyWithType(
                              total,
                              itemCurrency,
                              dollarRate: _debt!.getDoubleValue('dollar_rate'),
                              showConversion: false,
                            ),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppDarkColors.textSecondary
                                  : const Color(0xFF667085),
                            ),
                            textDirection: TextDirection.ltr,
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ];
    } catch (_) {
      return [];
    }
  }

  List<Widget> _buildReceiptSliver(bool isDark) {
    if (_debt == null || _debt!.getStringValue('receipt_image').isEmpty) {
      return [];
    }
    final imageUrl = FinancialDocumentActions.receiptUrl(_debt!);

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => FinancialDocumentActions.openReceiptViewer(context, _debt!),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? AppDarkColors.card : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFE9EDF3),
                ),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      imageUrl,
                      width: 58,
                      height: 58,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 58,
                        height: 58,
                        alignment: Alignment.center,
                        color: isDark
                            ? AppDarkColors.background
                            : const Color(0xFFF5F7FA),
                        child: const Icon(
                          Icons.broken_image_outlined,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'وێنەی وەسڵ',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppDarkColors.textPrimary
                                : const Color(0xFF344054),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'بۆ بینینی قەبارەی تەواو کلیک بکە',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark
                                ? AppDarkColors.textSecondary
                                : const Color(0xFF98A2B3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.open_in_full_rounded,
                    size: 18,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : const Color(0xFF98A2B3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildPaymentCard(RecordModel payment, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final paymentAmount = payment.getDoubleValue('amount');
    final currency = _debt!.getStringValue('currency');
    final dollarRate = _debt!.getDoubleValue('dollar_rate');
    final note = payment.getStringValue('note');
    final created = payment.getStringValue('created');
    final displayAmount = AppHelpers.formatCurrencyWithType(
      (currency == 'USD' && dollarRate > 0)
          ? paymentAmount / dollarRate
          : paymentAmount,
      (currency == 'USD' && dollarRate > 0) ? 'USD' : 'IQD',
      dollarRate: dollarRate,
      showConversion: false,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE9EDF3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.south_west_rounded,
              color: Colors.green,
              size: 17,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppHelpers.formatDateTime(created),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : const Color(0xFF98A2B3),
                  ),
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppDarkColors.textSecondary
                          : const Color(0xFF667085),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                displayAmount,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.green,
                ),
                textDirection: TextDirection.ltr,
              ),
              if (context.read<AuthProvider>().userRole == 'admin') ...[
                const SizedBox(height: 2),
                SizedBox(
                  width: 30,
                  height: 30,
                  child: IconButton(
                    tooltip: 'سڕینەوەی پارەدانەوە',
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    color: Colors.red,
                    onPressed: _deletingPaymentIds.contains(payment.id)
                        ? null
                        : () => _confirmDeletePayment(payment),
                    icon: _deletingPaymentIds.contains(payment.id)
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline_rounded),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeletePayment(RecordModel payment) async {
    final confirm = await AppHelpers.showConfirmDialog(
      context,
      title: 'سڕینەوەی پارەدانەوە',
      message:
          'بڕی ئەم پارەدانەوەیە دەگەڕێتەوە سەر ماوەی قەرز. دڵنیایت؟',
    );
    if (!mounted || !confirm) return;

    setState(() => _deletingPaymentIds.add(payment.id));
    try {
      await PBService.deletePayment(payment.id);
      if (!mounted) return;
      await _loadData();
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'پارەدانەوەکە سڕایەوە');
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا پارەدانەوەکە بسڕدرێتەوە. دووبارە هەوڵ بدە.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _deletingPaymentIds.remove(payment.id));
      }
    }
  }

  Future<void> _confirmDelete() async {
    final confirm = await AppHelpers.showConfirmDialog(
      context,
      title: 'سڕینەوەی قەرز',
      message: 'قەرزەکە دەخرێتە سەبەتە و دەتوانیت دواتر بیگەڕێنیتەوە. دڵنیایت؟',
    );
    if (!mounted || !confirm) return;
    try {
      await PBService.deleteDebt(widget.debtId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا قەرزەکە بسڕدرێتەوە. دووبارە هەوڵ بدە.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _showAddPaymentDialog({double? initialStorageAmount}) async {
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
}
