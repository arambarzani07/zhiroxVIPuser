import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/shared/debt_detail_screen.dart';
import 'package:zhirox/screens/shared/user_profile_screen.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/services/pdf_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

import 'package:zhirox/screens/customer/notifications_screen.dart';
import 'package:zhirox/services/connectivity_service.dart';

class CustomerDashboard extends StatefulWidget {
  const CustomerDashboard({super.key});

  @override
  State<CustomerDashboard> createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> {
  // Active debts (not paid) - loaded all at once (usually few)
  List<RecordModel> _activeDebts = [];
  // History debts (paid) - loaded with pagination
  List<RecordModel> _historyDebts = [];
  bool _isLoading = true;
  bool _loadInFlight = false;
  String? _loadError;
  int _selectedTab = 0; // 0: Active, 1: History
  int _unreadCount = 0;

  // Pagination state for history
  int _historyPage = 1;
  bool _hasMoreHistory = true;
  bool _isLoadingMore = false;
  int _historyTotalItems = 0;
  static const int _pageSize = 20;

  // Scroll controller for pagination
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<bool>? _connectivitySub;

  // Stats (calculated from ALL debts, not just loaded ones)
  double _totalDebtAmount = 0;
  double _totalRemainingAmount = 0;
  bool _totalsComplete = true;
  String _marketName = '';

  List<RecordModel> get _filteredDebts {
    return _selectedTab == 0 ? _activeDebts : _historyDebts;
  }

  int get _activeCount => _activeDebts.length;
  int get _historyCount => _historyTotalItems;

  double get _totalRemaining => _totalRemainingAmount;

  double get _totalDebt => _totalDebtAmount;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadDebts();
    _checkNotifications();
    _connectivitySub = ConnectivityService.instance.statusStream.listen((online) {
      if (online && mounted) {
        _loadDebts();
        _checkNotifications();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.user != null) {
        // Subscribe to debts changes
        PBService.pb.collection('debts').subscribe('*', (e) {
          if (!mounted) return;
          final action = e.action;
          if (action == 'create' || action == 'update' || action == 'delete') {
            if (mounted) {
              Future.delayed(const Duration(milliseconds: 500), () {
                _loadDebts();
              });
            }
          }
        });

        // Subscribe to notifications changes
        PBService.pb.collection('notifications').subscribe('*', (e) {
          if (mounted) {
            _checkNotifications();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    try {
      PBService.pb.collection('debts').unsubscribe('*');
      PBService.pb.collection('notifications').unsubscribe('*');
    } catch (_) {}
    super.dispose();
  }

  void _onScroll() {
    if (_selectedTab != 1) return; // Only paginate history tab
    if (_isLoadingMore || !_hasMoreHistory) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final threshold = maxScroll * 0.8; // Load more at 80% scroll

    if (currentScroll >= threshold) {
      _loadMoreHistory();
    }
  }

  Future<void> _checkNotifications() async {
    if (!mounted) return;
    try {
      final auth = context.read<AuthProvider>();
      if (auth.userId.isEmpty) return;

      final count = await PBService.getUnreadNotificationCount(auth.userId);

      if (mounted) {
        setState(() {
          _unreadCount = count;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDebts() async {
    if (!mounted || _loadInFlight) return;
    _loadInFlight = true;
    final showInitialLoading = _activeDebts.isEmpty && _historyDebts.isEmpty;
    if (showInitialLoading) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    final auth = context.read<AuthProvider>();
    if (auth.userId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      _loadInFlight = false;
      return;
    }

    try {
      if (_marketName.isEmpty && auth.adminId.isNotEmpty) {
        try {
          final admin = await PBService.getUser(auth.adminId);
          _marketName = admin.getStringValue('market_name');
        } catch (_) {}
      }

      final allDebts = await PBService.getDebts(customerId: auth.userId);
      final summary = AppHelpers.debtSummaryInIqd(allDebts);
      final totalDebt = summary.totalDebt;
      final totalRemaining = summary.totalRemaining;

      final activeDebts = allDebts
          .where((debt) => debt.getStringValue('status') != 'paid')
          .toList();
      final historyResult = await PBService.getDebtsPaginated(
        customerId: auth.userId,
        status: 'paid',
        page: 1,
        perPage: _pageSize,
      );

      if (!mounted) return;
      setState(() {
        _totalDebtAmount = totalDebt;
        _totalRemainingAmount = totalRemaining;
        _totalsComplete = summary.complete;
        _activeDebts = activeDebts;
        _historyDebts = historyResult['items'] as List<RecordModel>;
        _historyTotalItems = historyResult['totalItems'] as int;
        _historyPage = 1;
        _hasMoreHistory = _historyDebts.length < _historyTotalItems;
        _loadError = null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = ConnectivityService.instance.isOnline
            ? 'نەتوانرا زانیارییەکان بار بکرێن. دووبارە هەوڵ بدە.'
            : 'پەیوەندی ئینتەرنێت نییە. پەیوەندییەکەت بپشکنە.';
      });
    } finally {
      _loadInFlight = false;
    }
  }

  Future<void> _loadMoreHistory() async {
    if (_isLoadingMore || !_hasMoreHistory) return;
    setState(() => _isLoadingMore = true);

    try {
      final auth = context.read<AuthProvider>();
      final nextPage = _historyPage + 1;

      final result = await PBService.getDebtsPaginated(
        customerId: auth.userId,
        status: 'paid',
        page: nextPage,
        perPage: _pageSize,
      );

      final newItems = result['items'] as List<RecordModel>;

      if (mounted) {
        setState(() {
          _historyDebts.addAll(newItems);
          _historyPage = nextPage;
          _hasMoreHistory =
              _historyDebts.length < (result['totalItems'] as int);
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<void> _printStatement() async {
    if (!_totalsComplete) {
      AppHelpers.showSnackBar(
        context,
        'کەشف دروست ناکرێت تا نرخی گۆڕینەوەی هەموو قەرزە USD ـەکان دیاری بکرێت.',
        isError: true,
      );
      return;
    }
    if (_activeDebts.isEmpty) {
      AppHelpers.showSnackBar(
        context,
        'هیچ قەرزێکی چالاکت نییە بۆ چاپکردن',
        isError: true,
      );
      return;
    }

    try {
      AppHelpers.showLoadingDialog(context);
      final auth = context.read<AuthProvider>();

      // Fetch Admin Info
      String marketName = '';
      String adminName = '';
      String adminPhone = '';
      try {
        final admin = await PBService.getUser(auth.adminId);
        marketName = admin.getStringValue('market_name');
        adminName = admin.getStringValue('name');
        adminPhone = admin.getStringValue('phone');
      } catch (_) {
        marketName = 'Zhirox System';
        adminName = 'Admin';
      }

      if (mounted) Navigator.pop(context); // Close loading

      await PdfService.generateCustomerStatement(
        activeDebts: _activeDebts,
        customerName: auth.userName,
        marketName: marketName,
        adminName: adminName,
        adminPhone: adminPhone,
        totalDebt: _totalDebt,
        totalRemaining: _totalRemaining,
        totalPaid: _totalDebt - _totalRemaining,
      );
    } catch (e) {
      if (mounted) Navigator.pop(context); // Close loading
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          'هەڵەیەک ڕوویدا لە کاتی چاپکردن',
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final totalPaid = _totalDebt - _totalRemaining;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppDarkColors.card : Colors.white;
    final border = isDark ? AppDarkColors.cardBorder : const Color(0xFFEAECF0);
    final textPrimary = isDark ? AppDarkColors.textPrimary : const Color(0xFF1D2939);
    final textSecondary = isDark ? AppDarkColors.textSecondary : const Color(0xFF667085);

    return Scaffold(
      backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF7F8FA),
      body: RefreshIndicator(
        onRefresh: _loadDebts,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UserProfileScreen(userId: auth.userId),
                              ),
                            ).then((_) {
                              if (mounted) setState(() {});
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.person_outline_rounded,
                                    size: 20,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _marketName.isNotEmpty ? _marketName : 'ZHIROX',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        auth.userName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            tooltip: 'ئاگادارکردنەوەکان',
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const NotificationsScreen(),
                                ),
                              ).then((_) => _checkNotifications());
                            },
                            icon: Icon(
                              Icons.notifications_none_rounded,
                              color: textPrimary,
                            ),
                          ),
                          if (_unreadCount > 0)
                            Positioned(
                              right: 4,
                              top: 3,
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  _unreadCount > 99 ? '99+' : '$_unreadCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ماوەی قەرز',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _totalsComplete
                          ? AppHelpers.formatCurrency(_totalRemaining)
                          : '—',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 28,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                        color: textPrimary,
                      ),
                    ),
                    if (!_totalsComplete) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'هەندێک قەرزی USD نرخی گۆڕینەوەی نییە؛ کۆی گشتی بۆ پاراستنی دروستی نیشان نادرێت.',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryMetric(
                            label: 'دراوە',
                            value: _totalsComplete
                                ? AppHelpers.formatCurrency(totalPaid)
                                : '—',
                            icon: Icons.check_circle_outline_rounded,
                            accent: Colors.green,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildSummaryMetric(
                            label: 'هەموو قەرزەکان',
                            value: '${_activeCount + _historyCount}',
                            icon: Icons.receipt_long_outlined,
                            accent: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _activeDebts.isEmpty ? null : _printStatement,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          minimumSize: const Size.fromHeight(44),
                          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.22)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.description_outlined, size: 18),
                        label: const Text(
                          'کەشفی حیساب',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? AppDarkColors.surface : const Color(0xFFF0F2F5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      _buildTab(
                        index: 0,
                        label: 'قەرزە چالاکەکان',
                        count: _activeCount,
                        icon: Icons.receipt_long_outlined,
                      ),
                      _buildTab(
                        index: 1,
                        label: 'مێژوو',
                        count: _historyCount,
                        icon: Icons.history_rounded,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_loadError != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.wifi_off_rounded,
                            color: Colors.orange,
                            size: 25,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _loadError!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textSecondary,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _loadDebts,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('دووبارە هەوڵ بدە'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_filteredDebts.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          _selectedTab == 0
                              ? Icons.receipt_long_outlined
                              : Icons.history_rounded,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _selectedTab == 0
                            ? 'هیچ قەرزێکی چالاک نییە'
                            : 'هێشتا مێژووی قەرز نییە',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildDebtCard(_filteredDebts[index]),
                    childCount: _filteredDebts.length,
                  ),
                ),
              ),
            if (_selectedTab == 1 && _isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
            if (_selectedTab == 1 &&
                !_isLoadingMore &&
                !_hasMoreHistory &&
                _historyDebts.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Center(
                    child: Text(
                      '${_historyDebts.length} مامەڵە نیشان درا',
                      style: TextStyle(fontSize: 11.5, color: textSecondary),
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryMetric({
    required String label,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.surface : const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: accent, size: 16),
          ),
          const SizedBox(width: 8),
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
                        : const Color(0xFF667085),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? AppDarkColors.textPrimary
                        : const Color(0xFF1D2939),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab({
    required int index,
    required String label,
    required int count,
    required IconData icon,
  }) {
    final selected = _selectedTab == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = selected
        ? AppColors.primary
        : isDark
            ? AppDarkColors.textSecondary
            : const Color(0xFF667085);
    return Expanded(
      child: Material(
        color: selected
            ? (isDark
                ? AppColors.primary.withValues(alpha: 0.12)
                : Colors.white)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => setState(() => _selectedTab = index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: textColor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.09)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : const Color(0xFFE4E7EC)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDebtCard(RecordModel debt) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = debt.getStringValue('status');
    final remaining = debt.getDoubleValue('remaining');
    final amount = debt.getDoubleValue('amount');
    final currency = debt.getStringValue('currency');
    final dollarRate = debt.getDoubleValue('dollar_rate');
    final description = debt.getStringValue('description').trim();
    final customDate = debt.getStringValue('custom_date');
    final date = customDate.isNotEmpty ? customDate : debt.getStringValue('created');
    final updated = debt.getStringValue('updated');
    final isPaid = status == 'paid';
    final statusColor = AppHelpers.statusColor(status);
    final displayAmount = (currency == 'USD' && dollarRate > 0)
        ? (isPaid ? amount : remaining) / dollarRate
        : (isPaid ? amount : remaining);
    final displayCurrency =
        (currency == 'USD' && dollarRate > 0) ? 'USD' : 'IQD';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppDarkColors.cardBorder : const Color(0xFFEAECF0),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DebtDetailScreen(debtId: debt.id),
              ),
            ).then((_) => _loadDebts());
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    isPaid ? Icons.check_rounded : Icons.receipt_long_outlined,
                    color: statusColor,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        description.isEmpty ? 'قەرز' : description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppDarkColors.textPrimary
                              : const Color(0xFF344054),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            AppHelpers.formatDate(date),
                            style: TextStyle(
                              fontSize: 10.5,
                              color: isDark
                                  ? AppDarkColors.textSecondary
                                  : const Color(0xFF98A2B3),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              AppHelpers.getDaysCounter(date, updated, isPaid),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      AppHelpers.formatCurrencyWithType(
                        displayAmount,
                        displayCurrency,
                        dollarRate: dollarRate,
                        showConversion: false,
                      ),
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppDarkColors.textPrimary
                            : const Color(0xFF1D2939),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        AppHelpers.statusName(status),
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
