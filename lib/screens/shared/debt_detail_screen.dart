import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/providers/debt_provider.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/services/pdf_service.dart';
import 'package:zhirox/screens/shared/add_debt_screen.dart';
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
  bool _isLoading = true;
  bool _isSaving = false;
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
    setState(() => _isLoading = true);
    try {
      _debt = await PBService.getDebt(widget.debtId);
      _payments = await PBService.getPayments(debtId: widget.debtId);
    } catch (_) {}
    setState(() => _isLoading = false);
    _animController.forward(from: 0);
  }

  Future<void> _printDebtInvoice() async {
    if (_debt == null) return;
    final auth = context.read<AuthProvider>();
    String marketName = auth.marketName;
    String adminPhone = '';

    if (marketName.isEmpty) {
      try {
        final admin = await PBService.getUser(auth.adminId);
        marketName = admin.getStringValue('market_name');
        adminPhone = admin.getStringValue('phone');
      } catch (_) {
        marketName = 'Zhirox System';
      }
    } else {
      adminPhone = auth.user?.getStringValue('phone') ?? '';
    }

    await PdfService.generateInvoice(
      debt: _debt!,
      marketName: marketName,
      adminName: auth.userName,
      adminPhone: adminPhone,
    );
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

  Future<void> _handleDebtAction(String action) async {
    switch (action) {
      case 'print':
        await _printDebtInvoice();
        break;
      case 'edit':
        await _editCurrentDebt();
        break;
      case 'delete':
        if (mounted) _confirmDelete();
        break;
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

    // Customer name
    String customerName = '';
    final expanded = _debt!.expand;
    if (expanded.containsKey('customer') && expanded['customer']!.isNotEmpty) {
      customerName = expanded['customer']!.first.getStringValue('name');
    }

    return Scaffold(
      backgroundColor: isDark
          ? AppDarkColors.background
          : const Color(0xFFF5F7FA),
      body: CustomScrollView(
        slivers: [
          // ───── Compact Debt Header ─────
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
                                    Text('چاپ / وەصڵ'),
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
                                  '${(paidPercent.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}% دراوە',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.76),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'دراوە: ${AppHelpers.formatCurrency(paid)}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.76),
                                    fontSize: 10.5,
                                  ),
                                  textDirection: TextDirection.ltr,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ───── Compact Metadata ─────
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
                                : _debt!.created,
                          ),
                          Colors.purple,
                        ),
                        _buildMetaCell(
                          Icons.schedule_outlined,
                          'کاتژمێر',
                          AppHelpers.formatTime(
                            _debt!.getStringValue('custom_date').isNotEmpty
                                ? _debt!.getStringValue('custom_date')
                                : _debt!.created,
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

          // ───── Items List (if any) ─────
          ..._buildItemsSliver(),

          // ───── Compact Payments Header ─────
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
                  if (!isCustomer && status != 'paid')
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

          // ───── Compact Receipt ─────
          ..._buildReceiptSliver(isDark),

          // ───── Payment List ─────
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

  // ═══════════════════════════════════════════
  // ── Widgets ──
  // ═══════════════════════════════════════════

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
    final imageUrl = PBService.pb
        .getFileUrl(_debt!, _debt!.getStringValue('receipt_image'))
        .toString();

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _showReceiptPreview(imageUrl),
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
                      errorBuilder: (_, __, ___) => Container(
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
                          'وێنەی وەصڵ',
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

  void _showReceiptPreview(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: InteractiveViewer(
                  child: Image.network(imageUrl, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton.filled(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      ),
    );
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
          Text(
            displayAmount,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: Colors.green,
            ),
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }

  // ───── Actions ─────

  void _confirmDelete() async {
    final confirm = await AppHelpers.showConfirmDialog(
      context,
      title: 'سڕینەوەی قەرز',
      message: 'دڵنیایت لە سڕینەوەی ئەم قەرزە؟',
    );
    if (confirm) {
      try {
        await context.read<DebtProvider>().removeDebt(widget.debtId);
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) {
          AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);
        }
      }
    }
  }

  void _showAddPaymentDialog() {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final remaining = _debt!.getDoubleValue('remaining');
    final currency = _debt!.getStringValue('currency');
    final dollarRate = _debt!.getDoubleValue('dollar_rate');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final isDark = Theme.of(sheetCtx).brightness == Brightness.dark;
          return Container(
            decoration: BoxDecoration(
              color: isDark ? AppDarkColors.card : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 8,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppDarkColors.cardBorder
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Title
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.payments,
                          color: Colors.green,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.addPayment,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? AppDarkColors.textPrimary : null,
                            ),
                          ),
                          Text(
                            'ماوە: ${AppHelpers.formatCurrencyWithType((currency == 'USD' && dollarRate > 0) ? remaining / dollarRate : remaining, (currency == 'USD' && dollarRate > 0) ? 'USD' : 'IQD', dollarRate: dollarRate, showConversion: false)}',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 13,
                            ),
                            textDirection: TextDirection.ltr,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ─── Quick Pay Buttons ───
                  Row(
                    children: [
                      _buildQuickPayBtn(
                        '25%',
                        (currency == 'USD' && dollarRate > 0)
                            ? (remaining * 0.25) / dollarRate
                            : remaining * 0.25,
                        amountController,
                      ),
                      const SizedBox(width: 8),
                      _buildQuickPayBtn(
                        '50%',
                        (currency == 'USD' && dollarRate > 0)
                            ? (remaining * 0.50) / dollarRate
                            : remaining * 0.50,
                        amountController,
                      ),
                      const SizedBox(width: 8),
                      _buildQuickPayBtn(
                        '75%',
                        (currency == 'USD' && dollarRate > 0)
                            ? (remaining * 0.75) / dollarRate
                            : remaining * 0.75,
                        amountController,
                      ),
                      const SizedBox(width: 8),
                      _buildQuickPayBtn(
                        '100%',
                        (currency == 'USD' && dollarRate > 0)
                            ? remaining / dollarRate
                            : remaining,
                        amountController,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Amount Field
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppDarkColors.inputFill : Colors.grey[50],
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? AppDarkColors.cardBorder
                            : Colors.grey[200]!,
                      ),
                    ),
                    child: TextFormField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.center,
                      autofocus: true,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppDarkColors.textPrimary : null,
                      ),
                      decoration: InputDecoration(
                        hintText: '0',
                        hintStyle: TextStyle(
                          color: Colors.grey[300],
                          fontSize: 24,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 16,
                        ),
                        suffixText: currency == 'USD' ? '\$' : 'د.ع',
                        suffixStyle: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 16,
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'بڕ بنووسە';
                        final amount = double.tryParse(v);
                        if (amount == null) return 'ژمارەیەکی دروست بنووسە';
                        if (amount <= 0) return 'بڕ دەبێت لە سفر زیاتر بێت';
                        final equivalent = (currency == 'USD' && dollarRate > 0)
                            ? amount * dollarRate
                            : amount;
                        // Allow small error margin for floating point
                        if (equivalent > remaining + 10) {
                          return 'لە قەرزی ماوە زیاترە';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Note Field
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppDarkColors.inputFill : Colors.grey[50],
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? AppDarkColors.cardBorder
                            : Colors.grey[200]!,
                      ),
                    ),
                    child: TextFormField(
                      controller: noteController,
                      decoration: InputDecoration(
                        hintText: 'تێبینی (ئارەزوومەندانە)...',
                        hintStyle: TextStyle(color: Colors.grey[400]),
                        prefixIcon: Icon(
                          Icons.sticky_note_2_outlined,
                          color: Colors.grey[400],
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSaving
                          ? null
                          : () async {
                              if (!formKey.currentState!.validate()) return;
                              setState(() => _isSaving = true);
                              try {
                                final auth = context.read<AuthProvider>();
                                final inputAmount = double.parse(
                                  amountController.text.trim(),
                                );
                                final storageAmount =
                                    (currency == 'USD' && dollarRate > 0)
                                    ? inputAmount * dollarRate
                                    : inputAmount;

                                await context.read<DebtProvider>().addPayment(
                                  debtId: widget.debtId,
                                  amount: storageAmount,
                                  note: noteController.text.trim(),
                                  createdBy: auth.userId,
                                );

                                // Close dialog IMMEDIATELY
                                if (mounted) {
                                  Navigator.pop(sheetCtx);
                                  AppHelpers.showSnackBar(
                                    context,
                                    'پارەدانەوە تۆمارکرا',
                                  );
                                  _loadData();
                                }
                              } catch (e) {
                                _isSaving = false;
                                if (mounted) {
                                  AppHelpers.showSnackBar(
                                    context,
                                    'هەڵە: $e',
                                    isError: true,
                                  );
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'تۆمارکردن',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuickPayBtn(
    String label,
    double amount,
    TextEditingController controller,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          controller.text = amount.toStringAsFixed(
            amount == amount.roundToDouble() ? 0 : 2,
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
