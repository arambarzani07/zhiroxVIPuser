import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/providers/debt_provider.dart';
import 'package:zhirox/screens/shared/debt_detail_screen.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/services/connectivity_service.dart';

class DebtListScreen extends StatefulWidget {
  const DebtListScreen({super.key});

  @override
  State<DebtListScreen> createState() => _DebtListScreenState();
}

class _DebtListScreenState extends State<DebtListScreen> {
  List<RecordModel> _allDebts = [];
  List<_CustomerInfo> _customers = [];
  bool _isLoading = true;
  bool _isPaying = false;
  Timer? _debounceTimer;
  final _searchController = TextEditingController();
  String _sortMode = 'default'; // 'default', 'name', 'amount'
  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _loadAllDebts();
    _subscribeToRealtimeEvents();
    _connectivitySub = ConnectivityService.instance.statusStream.listen((online) {
      if (online && mounted) _loadAllDebts();
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _subscribeToRealtimeEvents() {
    PBService.pb.collection('debts').subscribe('*', (e) {
      _debouncedReload();
    });
    PBService.pb.collection('payments').subscribe('*', (e) {
      _debouncedReload();
    });
  }

  void _debouncedReload() {
    if (_isPaying || !mounted) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && !_isPaying) _loadAllDebts();
    });
  }

  Future<void> _loadAllDebts({bool showLoading = true}) async {
    if (!mounted) return;
    if (showLoading) setState(() => _isLoading = true);

    final auth = context.read<AuthProvider>();
    final cacheKey = 'cached_debts_admin_${auth.adminId}';

    try {
      final debts = await PBService.getDebts(
        adminId: auth.adminId,
        perPage: 500,
      );
      _allDebts = debts;
      _extractCustomers();

      final prefs = await SharedPreferences.getInstance();
      final debtsJson = _allDebts.take(100).map((d) => d.toJson()).toList();
      await prefs.setString(cacheKey, jsonEncode(debtsJson));
    } catch (e) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString(cacheKey);
        if (cached != null) {
          final List<dynamic> decoded = jsonDecode(cached);
          _allDebts = decoded
              .map((item) => RecordModel.fromJson(item))
              .toList();
          _extractCustomers();
        }
      } catch (_) {}
    }

    if (mounted) setState(() => _isLoading = false);
  }

  /// Instantly updates local state, then syncs with server in background
  void _applyOptimisticUpdate(
    String customerId,
    double paidAmount, {
    int fullyPaidCount = 0,
  }) {
    final idx = _customers.indexWhere((c) => c.id == customerId);
    if (idx != -1) {
      final c = _customers[idx];
      c.totalRemaining = (c.totalRemaining - paidAmount).clamp(
        0,
        double.infinity,
      );
      c.debtCount = (c.debtCount - fullyPaidCount).clamp(0, c.debtCount);
      if (c.totalRemaining <= 0) {
        c.totalRemaining = 0;
        c.hasUnpaid = false;
        c.debtCount = 0;
      }
    }
    if (mounted) setState(() {});

    // Sync with server in background
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _loadAllDebts(showLoading: false);
    });
  }

  void _extractCustomers() {
    final Map<String, _CustomerInfo> map = {};

    for (final debt in _allDebts) {
      final customer = debt.expand['customer']?.first;
      if (customer == null) continue;
      final id = customer.id;
      final name = customer.getStringValue('name');
      final status = debt.getStringValue('status');

      if (!map.containsKey(id)) {
        map[id] = _CustomerInfo(id: id, name: name.isNotEmpty ? name : '—');
      }
      if (status != 'paid') {
        map[id]!.debtCount++;
        map[id]!.hasUnpaid = true;
      }
      map[id]!.totalRemaining += debt.getDoubleValue('remaining');
    }

    _customers = map.values.toList();

    // Apply sort mode
    switch (_sortMode) {
      case 'name':
        _customers.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'amount':
        _customers.sort((a, b) => b.totalRemaining.compareTo(a.totalRemaining));
        break;
      default:
        _customers.sort((a, b) {
          if (a.hasUnpaid != b.hasUnpaid) return a.hasUnpaid ? -1 : 1;
          return b.totalRemaining.compareTo(a.totalRemaining);
        });
    }

    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      _customers = _customers
          .where((c) => c.name.toLowerCase().contains(q))
          .toList();
    }
  }

  List<RecordModel> _getDebtsForCustomer(String customerId) {
    return _allDebts.where((d) {
      final c = d.expand['customer']?.first;
      return c?.id == customerId;
    }).toList()..sort((a, b) {
      final aP = a.getStringValue('status') == 'paid' ? 1 : 0;
      final bP = b.getStringValue('status') == 'paid' ? 1 : 0;
      if (aP != bP) return aP - bP;
      return b.created.compareTo(a.created);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canPay = auth.userRole == 'admin' || auth.userRole == 'employee';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark
            ? AppDarkColors.background
            : const Color(0xFFF5F7FA),
        body: RefreshIndicator(
          onRefresh: _loadAllDebts,
          child: CustomScrollView(
            slivers: [
              // ───── Header ─────
              SliverToBoxAdapter(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary,
                        AppColors.primary.withValues(alpha: 0.85),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(28),
                      bottomRight: Radius.circular(28),
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.list_alt_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'لیستی قەرزەکان',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${_customers.length} کڕیار',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          // Search
                          Container(
                            decoration: BoxDecoration(
                              color: isDark ? AppDarkColors.card : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: isDark
                                  ? []
                                  : [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.08,
                                        ),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                            ),
                            child: TextField(
                              controller: _searchController,
                              style: TextStyle(
                                color: isDark
                                    ? AppDarkColors.textPrimary
                                    : Colors.black87,
                              ),
                              onChanged: (_) =>
                                  setState(() => _extractCustomers()),
                              textAlignVertical: TextAlignVertical.center,
                              decoration: InputDecoration(
                                hintText: 'گەڕان بەدوای ناوی کڕیار...',
                                hintStyle: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 14,
                                ),
                                prefixIcon: const Icon(
                                  Icons.search,
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(
                                          Icons.clear,
                                          size: 18,
                                          color: Colors.grey[400],
                                        ),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _extractCustomers());
                                        },
                                      )
                                    : null,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Sort chips
                          Row(
                            children: [
                              _buildSortChip(
                                label: 'بنەڕەتی',
                                icon: Icons.swap_vert_rounded,
                                mode: 'default',
                              ),
                              const SizedBox(width: 8),
                              _buildSortChip(
                                label: 'بەپێی ناو',
                                icon: Icons.sort_by_alpha_rounded,
                                mode: 'name',
                              ),
                              const SizedBox(width: 8),
                              _buildSortChip(
                                label: 'زۆرترین قەرز',
                                icon: Icons.trending_up_rounded,
                                mode: 'amount',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ───── Content ─────
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_customers.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 60,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'هیچ قەرزێک نەدۆزرایەوە',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) =>
                          _buildCustomerTile(_customers[index], canPay),
                      childCount: _customers.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // ── Sort Chip ──
  // ═══════════════════════════════════════════

  Widget _buildSortChip({
    required String label,
    required IconData icon,
    required String mode,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _sortMode == mode;
    return GestureDetector(
      onTap: () {
        if (_sortMode != mode) {
          setState(() {
            _sortMode = mode;
            _extractCustomers();
          });
        }
      },
      child: AnimatedScale(
        scale: isSelected ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: isDark
                        ? [
                            AppColors.primary.withValues(alpha: 0.9),
                            AppColors.primary,
                          ]
                        : [Colors.white, const Color(0xFFF0F4FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isSelected ? null : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isSelected
                  ? (isDark ? Colors.white24 : Colors.white)
                  : Colors.white.withValues(alpha: 0.25),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: (isDark ? AppColors.primary : Colors.white)
                          .withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 13,
                  color: isSelected
                      ? (isDark ? Colors.white : AppColors.primary)
                      : Colors.white70,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? (isDark ? Colors.white : AppColors.primary)
                      : Colors.white.withValues(alpha: 0.9),
                  letterSpacing: isSelected ? 0.3 : 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // ── Customer Tile ──
  // ═══════════════════════════════════════════

  Widget _buildCustomerTile(_CustomerInfo customer, bool canPay) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Row(
        children: [
          // Avatar with debt count
          Stack(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: customer.hasUnpaid
                      ? Colors.red.withValues(alpha: 0.1)
                      : Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                  child: Text(
                    customer.name.isNotEmpty
                        ? customer.name[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: customer.hasUnpaid ? Colors.red : Colors.green,
                    ),
                  ),
                ),
              ),
              // Debt count badge
              Positioned(
                top: -2,
                left: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${customer.debtCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),

          // Name + amount
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.name.isNotEmpty ? customer.name : 'کڕیاری نەناسراو',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppDarkColors.textPrimary : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  AppHelpers.formatCurrency(customer.totalRemaining),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: customer.totalRemaining > 0
                        ? Colors.red
                        : Colors.green,
                  ),
                ),
              ],
            ),
          ),

          // Action buttons
          if (canPay && customer.hasUnpaid && customer.totalRemaining > 0)
            _actionIcon(
              Icons.payments_outlined,
              Colors.green,
              () => _showPayDialog(customer),
            ),
          const SizedBox(width: 6),
          _actionIcon(
            Icons.receipt_long_outlined,
            AppColors.primary,
            () => _showDebtsDialog(customer, canPay),
          ),
        ],
      ),
    );
  }

  Widget _actionIcon(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // ── Pay Dialog (centered) ──
  // ═══════════════════════════════════════════

  void _showPayDialog(_CustomerInfo customer) {
    final debts = _getDebtsForCustomer(
      customer.id,
    ).where((d) => d.getStringValue('status') != 'paid').toList();
    final totalRemaining = customer.totalRemaining;
    final amountController = TextEditingController(
      text: _formatWithCommas(totalRemaining),
    );
    final formKey = GlobalKey<FormState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final rawText = amountController.text.replaceAll(',', '').trim();
          final inputAmount = double.tryParse(rawText) ?? 0;
          final distribution = _calculateDistribution(debts, inputAmount);
          final fullyPaid = distribution.where((d) => d.fullyPaid).length;
          final partial = distribution.where((d) => !d.fullyPaid).length;

          return Directionality(
            textDirection: TextDirection.rtl,
            child: Dialog(
              backgroundColor: isDark ? AppDarkColors.card : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 40,
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Icon
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.payments,
                          color: Colors.green,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'پارەدانەوە بۆ ${customer.name}',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppDarkColors.textPrimary
                              : Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'کۆی ماوە: ${AppHelpers.formatCurrency(totalRemaining)}  ·  ${debts.length} قەرز',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                      const SizedBox(height: 20),

                      // Quick buttons
                      Row(
                        children: [
                          _qBtn(
                            '25%',
                            totalRemaining * 0.25,
                            amountController,
                            () => setDialogState(() {}),
                          ),
                          const SizedBox(width: 6),
                          _qBtn(
                            '50%',
                            totalRemaining * 0.50,
                            amountController,
                            () => setDialogState(() {}),
                          ),
                          const SizedBox(width: 6),
                          _qBtn(
                            '75%',
                            totalRemaining * 0.75,
                            amountController,
                            () => setDialogState(() {}),
                          ),
                          const SizedBox(width: 6),
                          _qBtn(
                            '100%',
                            totalRemaining,
                            amountController,
                            () => setDialogState(() {}),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Amount field
                      TextFormField(
                        controller: amountController,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.center,
                        autofocus: true,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppDarkColors.textPrimary
                              : Colors.black87,
                        ),
                        inputFormatters: [_ThousandsFormatter()],
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          hintText: '0',
                          hintStyle: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 26,
                          ),
                          filled: true,
                          fillColor: isDark
                              ? AppDarkColors.inputFill
                              : Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: isDark
                                  ? AppDarkColors.cardBorder
                                  : Colors.grey[200]!,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: isDark
                                  ? AppDarkColors.cardBorder
                                  : Colors.grey[200]!,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: isDark ? AppColors.primary : Colors.green,
                              width: 1.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 16,
                          ),
                          suffixText: 'د.ع',
                          suffixStyle: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'بڕ بنووسە';
                          final a = double.tryParse(v.replaceAll(',', ''));
                          if (a == null) return 'ژمارەیەکی دروست بنووسە';
                          if (a <= 0) return 'بڕ دەبێت لە سفر زیاتر بێت';
                          if (a > totalRemaining + 10) {
                            return 'لە کۆی قەرزەکان زیاترە';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),

                      // Distribution preview
                      if (inputAmount > 0 && distribution.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.blue.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (fullyPaid > 0)
                                Text(
                                  '✓ $fullyPaid قەرز تەواو دەدرێتەوە',
                                  style: TextStyle(
                                    color: Colors.green[700],
                                    fontSize: 12,
                                  ),
                                ),
                              if (partial > 0)
                                Text(
                                  '◐ $partial قەرز بەشێکی دەدرێتەوە',
                                  style: TextStyle(
                                    color: Colors.orange[700],
                                    fontSize: 12,
                                  ),
                                ),
                              if (inputAmount < totalRemaining)
                                Text(
                                  'ماوە: ${AppHelpers.formatCurrency(totalRemaining - inputAmount)}',
                                  style: TextStyle(
                                    color: Colors.red[400],
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 18),

                      // Save
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;
                            final amount = double.parse(
                              amountController.text.replaceAll(',', '').trim(),
                            );
                            Navigator.pop(ctx);
                            await _payAllDebts(debts, customer, amount);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'تۆمارکردن',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════
  // ── Debts List Dialog ──
  // ═══════════════════════════════════════════

  void _showDebtsDialog(_CustomerInfo customer, bool canPay) {
    final debts = _getDebtsForCustomer(customer.id);

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 40,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.receipt_long,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'قەرزەکانی ${customer.name}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 20),

              // Debt list
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                ),
                child: debts.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(30),
                        child: Text(
                          'هیچ قەرزێک نییە',
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: debts.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: Colors.grey[200]),
                        itemBuilder: (_, i) =>
                            _buildDebtRow(debts[i], canPay, ctx),
                      ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDebtRow(RecordModel debt, bool canPay, BuildContext dialogCtx) {
    final currency = debt.getStringValue('currency');
    final dollarRate = debt.getDoubleValue('dollar_rate');
    double total = debt.getDoubleValue('total_amount');
    if (total == 0) total = debt.getDoubleValue('amount');
    double remaining = debt.getDoubleValue('remaining');

    if (currency == 'USD' && dollarRate > 0) {
      total = total / dollarRate;
      remaining = remaining / dollarRate;
    }

    final status = debt.getStringValue('status');
    final isPaid = status == 'paid';
    final paid = total - remaining;
    final progress = total > 0 ? (paid / total).clamp(0.0, 1.0) : 0.0;

    Color statusColor = Colors.orange;
    if (isPaid) {
      statusColor = Colors.green;
    } else if (status == 'partial') {
      statusColor = Colors.blue;
    }

    String desc = debt.getStringValue('description');
    String creatorName = '';
    try {
      final creator = debt.expand['created_by']?.first;
      if (creator != null) {
        creatorName = creator.getStringValue('name');
      }
    } catch (_) {}
    try {
      final items = debt.getStringValue('items');
      if (items.isNotEmpty && items != '[]') {
        final List list = jsonDecode(items);
        if (list.isNotEmpty) {
          desc =
              '${list[0]['name'] ?? ''} ${list.length > 1 ? '+${list.length - 1}' : ''}';
        }
      }
    } catch (_) {}

    return InkWell(
      onTap: () {
        Navigator.pop(dialogCtx);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DebtDetailScreen(debtId: debt.id)),
        ).then((_) => _loadAllDebts());
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            // Status dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        AppHelpers.formatCurrencyWithType(
                          total,
                          currency,
                          dollarRate: dollarRate,
                          showConversion: false,
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppDarkColors.textPrimary
                              : Colors.black87,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          AppHelpers.statusName(status),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    desc,
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (creatorName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 12,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(width: 3),
                          Text(
                            creatorName,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!isPaid) ...[
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: Colors.grey[100],
                        valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!isPaid)
              Text(
                AppHelpers.formatCurrencyWithType(
                  remaining,
                  currency,
                  dollarRate: dollarRate,
                  showConversion: false,
                ),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.redAccent,
                ),
                textDirection: TextDirection.ltr,
              ),
            if (isPaid)
              const Icon(Icons.check_circle, color: Colors.green, size: 18),
            // Quick pay
            if (canPay && !isPaid) ...[
              const SizedBox(width: 6),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  Navigator.pop(dialogCtx);
                  _showSinglePaymentDialog(debt);
                },
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.payments_outlined,
                    color: Colors.green,
                    size: 16,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // ── Single Payment Dialog (centered) ──
  // ═══════════════════════════════════════════

  void _showSinglePaymentDialog(RecordModel debt) {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final formKey = GlobalKey<FormState>();
    final remaining = debt.getDoubleValue('remaining');
    final currency = debt.getStringValue('currency');
    final dollarRate = debt.getDoubleValue('dollar_rate');

    final displayRemaining = (currency == 'USD' && dollarRate > 0)
        ? remaining / dollarRate
        : remaining;
    final displayCurrency = (currency == 'USD' && dollarRate > 0)
        ? 'USD'
        : 'IQD';

    String customerId = debt.getStringValue('customer');

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          backgroundColor: isDark ? AppDarkColors.card : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 40,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.payments,
                      color: Colors.green,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'پارەدانەوە',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppDarkColors.textPrimary
                          : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ماوە: ${AppHelpers.formatCurrencyWithType(displayRemaining, displayCurrency, dollarRate: dollarRate, showConversion: false)}',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 18),

                  // Quick buttons
                  Row(
                    children: [
                      _qBtn(
                        '25%',
                        displayRemaining * 0.25,
                        amountController,
                        () {},
                      ),
                      const SizedBox(width: 6),
                      _qBtn(
                        '50%',
                        displayRemaining * 0.50,
                        amountController,
                        () {},
                      ),
                      const SizedBox(width: 6),
                      _qBtn(
                        '75%',
                        displayRemaining * 0.75,
                        amountController,
                        () {},
                      ),
                      const SizedBox(width: 6),
                      _qBtn('100%', displayRemaining, amountController, () {}),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Amount
                  TextFormField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    autofocus: true,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppDarkColors.textPrimary
                          : Colors.black87,
                    ),
                    inputFormatters: [_ThousandsFormatter()],
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: TextStyle(
                        color: isDark
                            ? AppDarkColors.textSecondary.withOpacity(0.5)
                            : Colors.grey[300],
                        fontSize: 24,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? AppDarkColors.inputFill
                          : Colors.grey[50],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: isDark
                              ? AppDarkColors.cardBorder
                              : Colors.grey[200]!,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: isDark
                              ? AppDarkColors.cardBorder
                              : Colors.grey[200]!,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: isDark ? AppColors.primary : Colors.green,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 16,
                      ),
                      suffixText: currency == 'USD' ? '\$' : 'د.ع',
                      suffixStyle: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'بڕ بنووسە';
                      final a = double.tryParse(v.replaceAll(',', ''));
                      if (a == null) return 'ژمارەیەکی دروست بنووسە';
                      if (a <= 0) return 'بڕ دەبێت لە سفر زیاتر بێت';
                      final eq = (currency == 'USD' && dollarRate > 0)
                          ? a * dollarRate
                          : a;
                      if (eq > remaining + 10) return 'لە قەرزی ماوە زیاترە';
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),

                  // Note
                  TextFormField(
                    controller: noteController,
                    decoration: InputDecoration(
                      hintText: 'تێبینی...',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      prefixIcon: Icon(
                        Icons.sticky_note_2_outlined,
                        color: Colors.grey[400],
                        size: 18,
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey[200]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey[200]!),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Save
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        try {
                          final auth = context.read<AuthProvider>();
                          final inputAmount = double.parse(
                            amountController.text.replaceAll(',', '').trim(),
                          );
                          final storageAmount =
                              (currency == 'USD' && dollarRate > 0)
                              ? inputAmount * dollarRate
                              : inputAmount;

                          await context.read<DebtProvider>().addPayment(
                            debtId: debt.id,
                            amount: storageAmount,
                            note: noteController.text.trim(),
                            createdBy: auth.userId,
                          );

                          // Instantly update UI
                          if (mounted) {
                            Navigator.pop(ctx);
                            AppHelpers.showSnackBar(
                              context,
                              'پارەدانەوە تۆمارکرا',
                            );
                            _applyOptimisticUpdate(
                              customerId,
                              storageAmount,
                              fullyPaidCount: storageAmount >= remaining
                                  ? 1
                                  : 0,
                            );
                          }
                        } catch (e) {
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
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'تۆمارکردن',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // ── Smart Distribution Logic ──
  // ═══════════════════════════════════════════

  List<_PayDistribution> _calculateDistribution(
    List<RecordModel> debts,
    double amount,
  ) {
    final result = <_PayDistribution>[];
    double left = amount;

    final sorted = List<RecordModel>.from(debts)
      ..sort((a, b) => a.created.compareTo(b.created));

    for (final debt in sorted) {
      if (left <= 0) break;
      final remaining = debt.getDoubleValue('remaining');
      if (remaining <= 0) continue;

      final pay = left >= remaining ? remaining : left;
      result.add(
        _PayDistribution(
          debtId: debt.id,
          payAmount: pay,
          fullyPaid: pay >= remaining,
        ),
      );
      left -= pay;
    }
    return result;
  }

  Future<void> _payAllDebts(
    List<RecordModel> debts,
    _CustomerInfo customer,
    double totalAmount,
  ) async {
    _isPaying = true;
    try {
      final auth = context.read<AuthProvider>();
      final debtProvider = context.read<DebtProvider>();
      final distribution = _calculateDistribution(debts, totalAmount);

      for (final dist in distribution) {
        await debtProvider.addPayment(
          debtId: dist.debtId,
          amount: dist.payAmount,
          note: 'پارەدانەوەی کۆمەڵ',
          createdBy: auth.userId,
        );
      }

      // Instantly update UI
      _isPaying = false;
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          'پارەدانەوە تۆمارکرا (${distribution.length} قەرز) ✓',
        );
        _applyOptimisticUpdate(
          customer.id,
          totalAmount,
          fullyPaidCount: distribution.where((d) => d.fullyPaid).length,
        );
      }
    } catch (e) {
      _isPaying = false;
      if (mounted) {
        AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);
      }
    }
  }

  // ═══════════════════════════════════════════
  // ── Helpers ──
  // ═══════════════════════════════════════════

  Widget _qBtn(
    String label,
    double amount,
    TextEditingController controller,
    VoidCallback onChanged,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          controller.text = _formatWithCommas(amount);
          onChanged();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatWithCommas(double value) {
    if (value == value.roundToDouble()) {
      final intStr = value.toInt().toString();
      return _addCommas(intStr);
    }
    final parts = value.toStringAsFixed(2).split('.');
    return '${_addCommas(parts[0])}.${parts[1]}';
  }

  String _addCommas(String s) {
    final result = StringBuffer();
    int count = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      result.write(s[i]);
      count++;
      if (count % 3 == 0 && i > 0 && s[i] != '-') {
        result.write(',');
      }
    }
    return result.toString().split('').reversed.join();
  }
}

// ═══════════════════════════════════════════
// ── Models ──
// ═══════════════════════════════════════════

class _CustomerInfo {
  final String id;
  final String name;
  double totalRemaining;
  int debtCount;
  bool hasUnpaid;

  _CustomerInfo({required this.id, required this.name})
    : totalRemaining = 0,
      debtCount = 0,
      hasUnpaid = false;
}

class _PayDistribution {
  final String debtId;
  final double payAmount;
  final bool fullyPaid;

  _PayDistribution({
    required this.debtId,
    required this.payAmount,
    required this.fullyPaid,
  });
}

/// Formats number input with thousand separators (commas)
class _ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    final raw = newValue.text.replaceAll(',', '');
    if (raw.isEmpty) return newValue;

    // Allow only digits and one decimal point
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(raw)) return oldValue;

    String formatted;
    if (raw.contains('.')) {
      final parts = raw.split('.');
      formatted = '${_addCommas(parts[0])}.${parts.length > 1 ? parts[1] : ''}';
    } else {
      formatted = _addCommas(raw);
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _addCommas(String s) {
    if (s.isEmpty) return s;
    final result = StringBuffer();
    int count = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      result.write(s[i]);
      count++;
      if (count % 3 == 0 && i > 0) {
        result.write(',');
      }
    }
    return result.toString().split('').reversed.join();
  }
}
