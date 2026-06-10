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
    final amountUsd = _debt!.getDoubleValue('amount_usd');
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
          // ───── Gradient Header ─────
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    statusColor.withOpacity(0.9),
                    statusColor.withOpacity(0.6),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    // Nav Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back_ios,
                              color: Colors.white,
                              size: 22,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Spacer(),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.print_outlined,
                                color: Colors.white,
                                size: 20,
                              ),
                              onPressed: () async {
                                final auth = context.read<AuthProvider>();
                                String marketName = auth.marketName;
                                String adminPhone = '';
                                if (marketName.isEmpty) {
                                  try {
                                    final admin = await PBService.getUser(
                                      auth.adminId,
                                    );
                                    marketName = admin.getStringValue(
                                      'market_name',
                                    );
                                    adminPhone = admin.getStringValue('phone');
                                  } catch (_) {
                                    marketName = 'Zhirox System';
                                  }
                                } else {
                                  adminPhone =
                                      auth.user?.getStringValue('phone') ?? '';
                                }
                                await PdfService.generateInvoice(
                                  debt: _debt!,
                                  marketName: marketName,
                                  adminName: auth.userName,
                                  adminPhone: adminPhone,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              AppHelpers.statusName(status),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (!isCustomer && auth.canEditDebts) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(
                                Icons.edit,
                                color: Colors.white.withOpacity(0.9),
                                size: 22,
                              ),
                              onPressed: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AddDebtScreen(
                                      debt: _debt,
                                      customerId: _debt!.getStringValue(
                                        'customer',
                                      ),
                                    ),
                                  ),
                                );
                                if (result == true) _loadData();
                              },
                            ),
                          ],
                          if (!isCustomer && auth.userRole == 'admin') ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: Colors.white.withOpacity(0.8),
                                size: 22,
                              ),
                              onPressed: () => _confirmDelete(),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Main Amount
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: Column(
                        children: [
                          Text(
                            _debt!.getStringValue('description').isNotEmpty
                                ? _debt!.getStringValue('description')
                                : 'قەرز',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            AppHelpers.formatCurrency(
                              status == 'paid' ? amount : remaining,
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                            textDirection: TextDirection.ltr,
                          ),
                          if (currency == 'USD' && amountUsd > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              '\$${(amount > 0 ? (remaining / amount) * amountUsd : 0).toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                              textDirection: TextDirection.ltr,
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            'ماوە لە ${AppHelpers.formatCurrency(amount)}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 13,
                            ),
                            textDirection: TextDirection.ltr,
                          ),
                          if (customerName.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.person_outline,
                                  size: 16,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  customerName,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          // Progress
                          const SizedBox(height: 20),
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: paidPercent),
                            duration: const Duration(milliseconds: 1000),
                            curve: Curves.easeOutCubic,
                            builder: (context, val, _) {
                              return Column(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: val,
                                      minHeight: 8,
                                      backgroundColor: Colors.white.withOpacity(
                                        0.2,
                                      ),
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${(val * 100).toStringAsFixed(0)}% دراوە',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.8),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        AppHelpers.formatCurrencyWithType(
                                          (currency == 'USD' && dollarRate > 0)
                                              ? paid / dollarRate
                                              : paid,
                                          (currency == 'USD' && dollarRate > 0)
                                              ? 'USD'
                                              : 'IQD',
                                          dollarRate: dollarRate,
                                          showConversion: false,
                                        ),
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.8),
                                          fontSize: 12,
                                        ),
                                        textDirection: TextDirection.ltr,
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ───── Info Cards ─────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      _buildInfoChip(
                        Icons.monetization_on_outlined,
                        'کۆی قەرز',
                        AppHelpers.formatCurrency(amount),
                        Colors.blue,
                      ),
                      const SizedBox(width: 10),
                      _buildInfoChip(
                        Icons.calendar_today_outlined,
                        'دوایین بەروار',
                        AppHelpers.formatDate(
                          _debt!.getStringValue('due_date'),
                        ),
                        Colors.orange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildInfoChip(
                        Icons.edit_calendar_outlined,
                        'بەرواری پێدانی قەرز',
                        AppHelpers.formatDate(
                          _debt!.getStringValue('custom_date').isNotEmpty
                              ? _debt!.getStringValue('custom_date')
                              : _debt!.created,
                        ),
                        Colors.purple,
                      ),
                      const SizedBox(width: 10),
                      _buildInfoChip(
                        Icons.access_time_rounded,
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

          // ───── Items List (if any) ─────
          ..._buildItemsSliver(),

          // ───── Payments Header ─────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.payments_outlined,
                    size: 20,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppStrings.payments,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppDarkColors.textPrimary
                          : Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? AppDarkColors.card : Colors.grey[200],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_payments.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppDarkColors.textSecondary
                            : Colors.grey[600],
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (!isCustomer && status != 'paid')
                    GestureDetector(
                      onTap: _showAddPaymentDialog,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary,
                              AppColors.primary.withOpacity(0.7),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add, color: Colors.white, size: 18),
                            SizedBox(width: 4),
                            Text(
                              'پارەدانەوە',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ───── Receipt Image ─────
          if (_debt!.getStringValue('receipt_image').isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? AppDarkColors.card : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: isDark
                        ? []
                        : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.receipt_long_rounded,
                            color: Colors.teal.shade600,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'وێنەی وەصڵ',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () {
                          final imageUrl = PBService.pb
                              .getFileUrl(
                                _debt!,
                                _debt!.getStringValue('receipt_image'),
                              )
                              .toString();
                          showDialog(
                            context: context,
                            builder: (ctx) => Dialog(
                              backgroundColor: Colors.transparent,
                              insetPadding: const EdgeInsets.all(16),
                              child: Stack(
                                children: [
                                  Center(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: InteractiveViewer(
                                        child: Image.network(
                                          imageUrl,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: GestureDetector(
                                      onTap: () => Navigator.pop(ctx),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            PBService.pb
                                .getFileUrl(
                                  _debt!,
                                  _debt!.getStringValue('receipt_image'),
                                )
                                .toString(),
                            width: double.infinity,
                            height: 180,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                height: 180,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stack) {
                              return Container(
                                height: 100,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: Colors.grey.shade400,
                                    size: 40,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ───── Payment List ─────
          if (_payments.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(
                      Icons.payments_outlined,
                      size: 48,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(height: 12),
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

  Widget _buildInfoChip(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppDarkColors.card : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: color.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isDark
                          ? AppDarkColors.textPrimary
                          : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
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
      // PocketBase may return items as a JSON string or already-parsed List
      // depending on the field type (text vs json)
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? AppDarkColors.card : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: isDark
                    ? []
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.shopping_bag_outlined,
                        size: 18,
                        color: Colors.purple[400],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'کاڵاکان',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppDarkColors.textSecondary
                              : Colors.grey[700],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.purple.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${itemsList.length}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple[400],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  ...itemsList.map((item) {
                    final name = (item is Map ? item['name'] : '') ?? '';
                    final qty =
                        (item is Map ? item['quantity'] ?? item['qty'] : 1) ??
                        1;
                    final price = (item is Map ? item['price'] : 0) ?? 0;
                    final itemCurrency =
                        (item is Map ? item['currency'] : null) ??
                        _debt!.getStringValue('currency');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.purple.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                '$qty×',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple[400],
                                ),
                                textDirection: TextDirection.ltr,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$name',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? AppDarkColors.textPrimary
                                    : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            AppHelpers.formatCurrencyWithType(
                              (price is num ? price.toDouble() : 0) *
                                  (qty is num ? qty.toDouble() : 1),
                              itemCurrency,
                              dollarRate: _debt!.getDoubleValue('dollar_rate'),
                              showConversion:
                                  false, // Items are usually in original currency
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                              fontWeight: FontWeight.w500,
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

  Widget _buildPaymentCard(RecordModel payment, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final paymentAmount = payment.getDoubleValue('amount');
    final currency = _debt!.getStringValue('currency');
    final dollarRate = _debt!.getDoubleValue('dollar_rate');
    final note = payment.getStringValue('note');
    final created = payment.getStringValue('created');

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 400 + (index * 50).clamp(0, 500)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isDark ? AppDarkColors.card : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.green.withValues(alpha: 0.15),
                      Colors.green.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.payments,
                  color: Colors.green,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppHelpers.formatCurrencyWithType(
                        (currency == 'USD' && dollarRate > 0)
                            ? paymentAmount / dollarRate
                            : paymentAmount,
                        (currency == 'USD' && dollarRate > 0) ? 'USD' : 'IQD',
                        dollarRate: dollarRate,
                        showConversion: false,
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.green,
                      ),
                      textDirection: TextDirection.ltr,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          AppHelpers.formatDateTime(created),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[400],
                          ),
                        ),
                        if (note.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Icon(
                            Icons.sticky_note_2_outlined,
                            size: 12,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              note,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
