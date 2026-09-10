import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
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
  bool _isLoading = true;
  bool _loadInFlight = false;
  String? _loadError;
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
    try {
      PBService.pb.collection('debts').unsubscribe();
      PBService.pb.collection('payments').unsubscribe();
    } catch (_) {}
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
    if (!mounted) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) _loadAllDebts();
    });
  }

  Future<void> _loadAllDebts({bool showLoading = true}) async {
    if (!mounted || _loadInFlight) return;
    _loadInFlight = true;

    if (showLoading || _allDebts.isEmpty) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final auth = context.read<AuthProvider>();
      final debts = await PBService.getDebts(
        adminId: auth.adminId,
        perPage: 500,
      );
      if (!mounted) return;
      setState(() {
        _allDebts = debts;
        _loadError = null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _allDebts = [];
        _isLoading = false;
        _loadError =
            'نەتوانرا لیستی قەرزەکان باربکرێت. پەیوەندی ئینتەرنێت بپشکنە.';
      });
    } finally {
      _loadInFlight = false;
    }
  }

  List<RecordModel> _visibleDebts() {
    final query = _searchController.text.trim().toLowerCase();
    final debts = _allDebts.where((debt) {
      final customer = AppHelpers.expandedRecord(debt, 'customer');
      final customerName = customer?.getStringValue('name').toLowerCase() ?? '';
      final description = debt.getStringValue('description').toLowerCase();
      return query.isEmpty ||
          customerName.contains(query) ||
          description.contains(query);
    }).toList();

    switch (_sortMode) {
      case 'name':
        debts.sort((a, b) {
          final aName = AppHelpers.expandedRecord(a, 'customer')?.getStringValue('name') ?? '';
          final bName = AppHelpers.expandedRecord(b, 'customer')?.getStringValue('name') ?? '';
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
          return b.getStringValue('created').compareTo(a.getStringValue('created'));
        });
    }
    return debts;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canPay = auth.userRole == 'admin' || auth.userRole == 'employee';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final visibleDebts = _visibleDebts();

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
                                  '${visibleDebts.length} قەرز',
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
                              onChanged: (_) => setState(() {}),
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
                                          setState(() {});
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
              else if (_loadError != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildLoadErrorState(),
                )
              else if (visibleDebts.isEmpty)
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
                          _buildDebtTile(visibleDebts[index], canPay),
                      childCount: visibleDebts.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadErrorState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 42, color: Colors.orange[400]),
            const SizedBox(height: 12),
            Text(
              _loadError ?? 'نەتوانرا لیستی قەرزەکان باربکرێت.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: isDark
                    ? AppDarkColors.textSecondary
                    : const Color(0xFF667085),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _loadAllDebts,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('دووبارە هەوڵ بدە'),
            ),
          ],
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
  // ── Direct Debt Tile ──
  // ═══════════════════════════════════════════

  Widget _buildDebtTile(RecordModel debt, bool canPay) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customer = AppHelpers.expandedRecord(debt, 'customer');
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
        : debt.getStringValue('created');

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
                            ? AppDarkColors.textSecondary.withValues(alpha: 0.5)
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

                          if (!mounted) return;
                          if (ctx.mounted) Navigator.pop(ctx);
                          AppHelpers.showSnackBar(
                            context,
                            'پارەدانەوە تۆمارکرا',
                          );
                          await _loadAllDebts(showLoading: false);
                        } catch (e) {
                          if (!mounted) return;
                          AppHelpers.showSnackBar(
                            context,
                            AppHelpers.backendErrorMessage(
                              e,
                              fallback: 'نەتوانرا پارەدانەوە تۆمار بکرێت. دووبارە هەوڵ بدە.',
                            ),
                            isError: true,
                          );
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
