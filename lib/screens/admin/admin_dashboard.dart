import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/providers/theme_provider.dart';
import 'package:zhirox/screens/admin/pending_requests_screen.dart';
import 'package:zhirox/screens/shared/debt_list_screen.dart';
import 'package:zhirox/screens/shared/user_list_screen.dart';
import 'package:zhirox/features/ai_quality/data_quality_screen.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/services/pdf_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/services/connectivity_service.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;
  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _connectivitySub = ConnectivityService.instance.statusStream.listen((online) {
      if (online && mounted) _loadStats();
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    if (auth.userId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final cacheKey = 'cached_admin_stats_${auth.userId}';

    try {
      _stats = await PBService.getDashboardStats(adminId: auth.userId);

      // Cache Stats
      final prefs = await SharedPreferences.getInstance();

      // Convert complex objects to JSON-encodable maps
      final statsJson = Map<String, dynamic>.from(_stats);
      if (statsJson['recentActivity'] is List) {
        statsJson['recentActivity'] = (statsJson['recentActivity'] as List)
            .map((e) => (e as RecordModel).toJson())
            .toList();
      }

      await prefs.setString(cacheKey, jsonEncode(statsJson));
    } catch (e) {
      // Offline fallback
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedString = prefs.getString(cacheKey);

        if (cachedString != null) {
          final decoded = jsonDecode(cachedString) as Map<String, dynamic>;

          // Restore RecordModel list
          if (decoded['recentActivity'] != null) {
            decoded['recentActivity'] = (decoded['recentActivity'] as List)
                .map((e) => RecordModel.fromJson(e))
                .toList();
          }

          _stats = decoded;
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final screens = [
      _buildNewDashboard(auth),
      UserListScreen(
        key: const ValueKey('customers'),
        role: 'customer',
        adminId: auth.userId,
      ),
      UserListScreen(
        key: const ValueKey('employees'),
        role: 'employee',
        adminId: auth.userId,
      ),
      DebtListScreen(key: const ValueKey('debts')),
      PendingRequestsScreen(
        key: ValueKey('pending_${auth.userId}'),
        adminId: auth.userId,
      ),
    ];

    return Scaffold(
      backgroundColor: isDark
          ? AppDarkColors.background
          : const Color(0xFFF5F7FA),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: screens[_currentIndex],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? AppDarkColors.card : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildNavItem(
                  0,
                  Icons.dashboard_outlined,
                  Icons.dashboard,
                  'داشبۆرد',
                ),
                _buildNavItem(1, Icons.people_outline, Icons.people, 'کڕیار'),
                _buildNavItem(2, Icons.badge_outlined, Icons.badge, 'کارمەند'),
                _buildNavItem(
                  3,
                  Icons.receipt_long_outlined,
                  Icons.receipt_long,
                  'قەرز',
                ),
                _buildNavItem(
                  4,
                  Icons.pending_actions_outlined,
                  Icons.pending_actions,
                  'داواکان',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    IconData icon,
    IconData activeIcon,
    String label,
  ) {
    final isSelected = _currentIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        setState(() => _currentIndex = index);
        if (index == 0) _loadStats();
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 16 : 12,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.primary.withOpacity(0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: isSelected ? 1.05 : 1.0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              child: Icon(
                isSelected ? activeIcon : icon,
                size: 24,
                color: isSelected
                    ? Colors.white
                    : (isDark ? AppDarkColors.textSecondary : Colors.grey[400]),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              child: isSelected
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewDashboard(AuthProvider auth) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final recentActivity = _stats['recentActivity'] as List<RecordModel>? ?? [];
    final pendingCount = _stats['pendingRequests'] as int? ?? 0;
    final totalCustomers = (_stats['totalCustomers'] ?? 0).toDouble();
    final totalDebt = (_stats['totalDebt'] ?? 0).toDouble();
    final totalRemaining = (_stats['totalRemaining'] ?? 0).toDouble();
    final totalPayments = (_stats['totalPayments'] ?? 0).toDouble();

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: CustomScrollView(
        slivers: [
          // ───── Gradient Header with Stats ─────
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.primary.withOpacity(0.8),
                    AppColors.primary.withOpacity(0.6),
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
                    // Top Bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                      child: Row(
                        children: [
                          Text(
                            AppStrings.appName,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
  icon: Icon(
    Icons.health_and_safety_rounded,
    color: Colors.white.withOpacity(0.7),
    size: 22,
  ),
  tooltip: 'پشکنینی ژیرانەی داتا',
  onPressed: () {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DataQualityScreen(),
      ),
    );
  },
),
                          IconButton(
                            icon: Icon(
                              Icons.print_rounded,
                              color: Colors.white.withOpacity(0.7),
                              size: 22,
                            ),
                            tooltip: 'چاپکردنی ڕاپۆرت',
                            onPressed: () async {
                              final choice = await showDialog<String>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  title: const Row(
                                    children: [
                                      Icon(
                                        Icons.print_rounded,
                                        color: Colors.blueGrey,
                                      ),
                                      SizedBox(width: 10),
                                      Text(
                                        'کەشفی حیساب',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ListTile(
                                        leading: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary
                                                .withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.select_all,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                        title: const Text(
                                          'هەمووی',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        subtitle: const Text(
                                          'ڕاپۆرتی تەواوی قەرزەکان',
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        onTap: () => Navigator.pop(ctx, 'all'),
                                      ),
                                      const SizedBox(height: 8),
                                      ListTile(
                                        leading: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withOpacity(
                                              0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.date_range,
                                            color: Colors.orange,
                                          ),
                                        ),
                                        title: const Text(
                                          'بە دەستی',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        subtitle: const Text(
                                          'بەرواری ئەوەندە بۆ ئەوەندە',
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        onTap: () =>
                                            Navigator.pop(ctx, 'custom'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                              if (choice == null || !mounted) return;

                              DateTime? fromDate;
                              DateTime? toDate;
                              String? dateFilter;

                              if (choice == 'custom') {
                                final now = DateTime.now();
                                final picked = await showDateRangePicker(
                                  context: context,
                                  firstDate: DateTime(2020),
                                  lastDate: now,
                                  initialDateRange: DateTimeRange(
                                    start: DateTime(now.year, now.month, 1),
                                    end: now,
                                  ),
                                  builder: (context, child) {
                                    return Theme(
                                      data: Theme.of(context).copyWith(
                                        colorScheme: ColorScheme.light(
                                          primary: AppColors.primary,
                                        ),
                                      ),
                                      child: child!,
                                    );
                                  },
                                );
                                if (picked == null || !mounted) return;
                                fromDate = picked.start;
                                toDate = picked.end;
                                final fromStr = DateFormat(
                                  'yyyy-MM-dd',
                                ).format(fromDate);
                                final toStr = DateFormat(
                                  'yyyy-MM-dd',
                                ).format(toDate.add(const Duration(days: 1)));
                                dateFilter =
                                    'created >= "$fromStr 00:00:00" && created <= "$toStr 00:00:00"';
                              }

                              setState(() => _isLoading = true);
                              try {
                                final allDebts = await PBService.getDebts(
                                  adminId: auth.userId,
                                  filter: dateFilter,
                                );

                                // Recalculate totals from fetched debts
                                double totalDebt = 0;
                                double totalRemaining = 0;
                                double totalPaid = 0;
                                final Set<String> customerIds = {};
                                for (var debt in allDebts) {
                                  totalDebt += debt.getDoubleValue('amount');
                                  totalRemaining += debt.getDoubleValue(
                                    'remaining',
                                  );
                                  totalPaid +=
                                      debt.getDoubleValue('amount') -
                                      debt.getDoubleValue('remaining');
                                  customerIds.add(
                                    debt.getStringValue('customer'),
                                  );
                                }

                                final adminPhone =
                                    auth.user?.getStringValue('phone') ?? '';

                                await PdfService.generateAdminReport(
                                  allDebts: allDebts,
                                  marketName: AppStrings.appName,
                                  adminName: auth.userName,
                                  adminPhone: adminPhone,
                                  totalDebt: totalDebt,
                                  totalRemaining: totalRemaining,
                                  totalPaid: totalPaid,
                                  totalCustomers: customerIds.length,
                                  fromDate: fromDate,
                                  toDate: toDate,
                                );
                              } catch (e) {
                                if (mounted) {
                                  AppHelpers.showSnackBar(
                                    context,
                                    'هەڵە لە دروستکردنی ڕاپۆرت: $e',
                                    isError: true,
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _isLoading = false);
                              }
                            },
                          ),
                          // Dark Mode Toggle
                          IconButton(
                            onPressed: () {
                              context.read<ThemeProvider>().toggleTheme();
                            },
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isDark
                                    ? Icons.light_mode_rounded
                                    : Icons.dark_mode_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.logout_rounded,
                              color: Colors.white.withOpacity(0.7),
                              size: 22,
                            ),
                            onPressed: () async {
                              final confirm =
                                  await AppHelpers.showConfirmDialog(
                                    context,
                                    title: AppStrings.logout,
                                    message: 'دڵنیایت لە چوونەدەرەوە؟',
                                  );
                              if (confirm) auth.logout();
                            },
                          ),
                        ],
                      ),
                    ),

                    // Welcome - Tappable for profile menu
                    GestureDetector(
                      onTap: () => _showAdminProfileMenu(auth),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                        child: Row(
                          children: [
                            // Avatar
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  (auth.user?.getStringValue('market_name') ??
                                              '')
                                          .isNotEmpty
                                      ? (auth.user?.getStringValue(
                                                  'market_name',
                                                ) ??
                                                '')[0]
                                            .toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'بەخێربێیتەوە 👋',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    auth.user?.getStringValue('market_name') ??
                                        'ناوی مارکێت نەدراوە',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Stats Grid inside header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _buildHeaderStat(
                                Icons.people,
                                'کڕیارەکان',
                                totalCustomers,
                                false,
                              ),
                              const SizedBox(width: 10),
                              _buildHeaderStat(
                                Icons.receipt_long,
                                'کۆی قەرز',
                                totalDebt,
                                true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _buildHeaderStat(
                                Icons.money_off,
                                'ماوە',
                                totalRemaining,
                                true,
                              ),
                              const SizedBox(width: 10),
                              _buildHeaderStat(
                                Icons.payments,
                                'وەرگیراو',
                                totalPayments,
                                true,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // ───── Subscription Warning (inside gradient) ─────
                    if (auth.subscriptionDaysLeft <= 10)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xCCE53935),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.red[300]!.withOpacity(0.6),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      auth.subscriptionDaysLeft <= 0
                                          ? 'ماوەی بەشداریت تەواو بووە!'
                                          : '${auth.subscriptionDaysLeft} ڕۆژ ماوە بۆ کۆتایی بەشداریت',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'تکایە پەیوەندی بکە بۆ نوێکردنەوە',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white.withOpacity(0.8),
                                      ),
                                    ),
                                  ],
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
          ),

          // ───── Pending Requests Alert ─────
          if (pendingCount > 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: GestureDetector(
                  onTap: () => setState(() => _currentIndex = 4),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.purple.withOpacity(0.1),
                          Colors.purple.withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.purple.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.purple.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.notifications_active,
                            color: Colors.purple,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'داواکاری چاوەڕوانکراو',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '$pendingCount داواکاری نوێ',
                                style: TextStyle(
                                  color: Colors.purple.withOpacity(0.6),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.purple,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'بینین',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ───── Recent Activity Header ─────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.history,
                    size: 20,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : Colors.black54,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'چالاکییە تازەکان',
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
                      color: isDark
                          ? AppDarkColors.cardBorder
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${recentActivity.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppDarkColors.textSecondary
                            : Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ───── Recent Activity List ─────
          if (recentActivity.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(Icons.history, size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    Text(
                      'هیچ چالاکیەک نییە',
                      style: TextStyle(color: Colors.grey[500], fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      _buildActivityCard(recentActivity[index], index),
                  childCount: recentActivity.length,
                ),
              ),
            ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 20)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // ── Admin Profile Menu ──
  // ═══════════════════════════════════════════

  void _showAdminProfileMenu(AuthProvider auth) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppDarkColors.card : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: isDark ? AppDarkColors.cardBorder : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Text(
              'تەنزیماتی هەژمار',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? AppDarkColors.textPrimary : Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            // Change Phone
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.phone_android, color: Colors.blue),
              ),
              title: Text(
                'گۆڕینی ژمارە مۆبایل',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppDarkColors.textPrimary : Colors.black87,
                ),
              ),
              subtitle: Text(
                auth.user?.getStringValue('phone') ?? 'نەدراوە',
                style: TextStyle(
                  color: isDark
                      ? AppDarkColors.textSecondary
                      : Colors.grey[500],
                  fontSize: 12,
                ),
                textDirection: TextDirection.ltr,
              ),
              trailing: Icon(
                Icons.chevron_left,
                color: isDark ? AppDarkColors.textSecondary : Colors.grey,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _showChangePhoneDialog(auth);
              },
            ),
            const SizedBox(height: 8),
            // Change Password
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.lock_outline, color: Colors.orange),
              ),
              title: Text(
                'گۆڕینی وشەی نهێنی',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppDarkColors.textPrimary : Colors.black87,
                ),
              ),
              subtitle: Text(
                'وشەی نهێنیی نوێ دابنێ',
                style: TextStyle(
                  color: isDark
                      ? AppDarkColors.textSecondary
                      : Colors.grey[500],
                  fontSize: 12,
                ),
              ),
              trailing: Icon(
                Icons.chevron_left,
                color: isDark ? AppDarkColors.textSecondary : Colors.grey,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _showChangePasswordDialog(auth);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showChangePhoneDialog(AuthProvider auth) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController(
      text: auth.user?.getStringValue('phone') ?? '',
    );
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: isDark ? AppDarkColors.card : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.phone_android,
                    color: Colors.blue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'گۆڕینی ژمارە مۆبایل',
                  style: TextStyle(
                    color: isDark ? AppDarkColors.textPrimary : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            content: Form(
              key: formKey,
              child: TextFormField(
                controller: controller,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? AppDarkColors.textPrimary : Colors.black87,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: '07XXXXXXXXX',
                  hintStyle: TextStyle(
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : Colors.grey[400],
                  ),
                  prefixIcon: const Icon(Icons.phone, size: 20),
                  filled: true,
                  fillColor: isDark ? AppDarkColors.surface : Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'ژمارە بنووسە';
                  final digits = v.trim().replaceAll(RegExp(r'[^0-9]'), '');
                  if (digits.length < 7) {
                    return 'ژمارە دەبێت لە ٧ ژمارە کەمتر نەبێت';
                  }
                  return null;
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'پاشگەزبوونەوە',
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setDialogState(() => isSaving = true);
                        try {
                          final newPhone = controller.text.trim();
                          // Check uniqueness
                          final existing = await PBService.pb
                              .collection('users')
                              .getList(
                                filter:
                                    'phone = "$newPhone" && id != "${auth.userId}"',
                                perPage: 1,
                              );
                          if (existing.items.isNotEmpty) {
                            setDialogState(() => isSaving = false);
                            if (mounted) {
                              AppHelpers.showSnackBar(
                                context,
                                'ئەم ژمارەیە پێشتر بەکارهێنراوە',
                                isError: true,
                              );
                            }
                            return;
                          }
                          await PBService.updateUser(auth.userId, {
                            'phone': newPhone,
                          });
                          // Refresh auth user data
                          await auth.refreshUser();
                          if (mounted) {
                            Navigator.pop(ctx);
                            AppHelpers.showSnackBar(
                              context,
                              'ژمارە مۆبایل گۆڕا ✅',
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isSaving = false);
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
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('پاشەکەوتکردن'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangePasswordDialog(AuthProvider auth) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final oldPassController = TextEditingController();
    final passController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;
    bool obscureOldPass = true;
    bool obscurePass = true;
    bool obscureConfirm = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: isDark ? AppDarkColors.card : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    color: Colors.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'گۆڕینی وشەی نهێنی',
                  style: TextStyle(
                    color: isDark ? AppDarkColors.textPrimary : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: oldPassController,
                    obscureText: obscureOldPass,
                    style: TextStyle(
                      color: isDark
                          ? AppDarkColors.textPrimary
                          : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      labelText: 'وشەی نهێنیی ئێستا',
                      prefixIcon: const Icon(Icons.lock_open, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureOldPass ? Icons.visibility_off : Icons.visibility,
                          size: 20,
                        ),
                        onPressed: () =>
                            setDialogState(() => obscureOldPass = !obscureOldPass),
                      ),
                      filled: true,
                      fillColor: isDark
                          ? AppDarkColors.surface
                          : Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'وشەی نهێنیی ئێستا بنووسە';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: passController,
                    obscureText: obscurePass,
                    style: TextStyle(
                      color: isDark
                          ? AppDarkColors.textPrimary
                          : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      labelText: 'وشەی نهێنیی نوێ',
                      prefixIcon: const Icon(Icons.lock, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePass ? Icons.visibility_off : Icons.visibility,
                          size: 20,
                        ),
                        onPressed: () =>
                            setDialogState(() => obscurePass = !obscurePass),
                      ),
                      filled: true,
                      fillColor: isDark
                          ? AppDarkColors.surface
                          : Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'وشەی نهێنی بنووسە';
                      if (v.length < 8) return 'لانی کەم ٨ پیت دەبێت';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: confirmController,
                    obscureText: obscureConfirm,
                    style: TextStyle(
                      color: isDark
                          ? AppDarkColors.textPrimary
                          : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      labelText: 'دووبارەکردنەوەی وشەی نهێنی',
                      prefixIcon: const Icon(Icons.lock_reset, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureConfirm
                              ? Icons.visibility_off
                              : Icons.visibility,
                          size: 20,
                        ),
                        onPressed: () => setDialogState(
                          () => obscureConfirm = !obscureConfirm,
                        ),
                      ),
                      filled: true,
                      fillColor: isDark
                          ? AppDarkColors.surface
                          : Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'دووبارەکردنەوە بنووسە';
                      }
                      if (v != passController.text) return 'وشەی نهێنی یەک نین';
                      return null;
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'پاشگەزبوونەوە',
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setDialogState(() => isSaving = true);
                        try {
                          await PBService.changePassword(
                            userId: auth.userId,
                            oldPassword: oldPassController.text,
                            newPassword: passController.text,
                          );
                          if (mounted) {
                            Navigator.pop(ctx);
                            AppHelpers.showSnackBar(
                              context,
                              'وشەی نهێنی گۆڕا ✅',
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isSaving = false);
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
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('پاشەکەوتکردن'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderStat(
    IconData icon,
    String label,
    double value,
    bool isCurrency,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: value),
                    duration: const Duration(milliseconds: 1500),
                    curve: Curves.easeOut,
                    builder: (context, val, _) {
                      return Text(
                        isCurrency
                            ? AppHelpers.formatCurrency(val)
                            : val.toInt().toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityCard(RecordModel debt, int index) {
    final customers = debt.expand['customer'];
    final customer = (customers != null && customers.isNotEmpty)
        ? customers.first
        : null;
    final creators = debt.expand['created_by'];
    final createdBy = (creators != null && creators.isNotEmpty)
        ? creators.first
        : null;

    final amount = debt.getDoubleValue('amount');
    final date = debt.getStringValue('created');
    final isByEmployee = createdBy?.getStringValue('role') == 'employee';
    final creatorName = createdBy?.getStringValue('name') ?? 'Unknown';
    final customerName =
        customer?.getStringValue('name') ?? 'کارمەند/کڕیار سڕدراوەتەوە';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 400 + (index * 50).clamp(0, 600)),
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
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isByEmployee
                        ? [
                            Colors.orange.withOpacity(0.15),
                            Colors.orange.withOpacity(0.05),
                          ]
                        : [
                            Colors.blue.withOpacity(0.15),
                            Colors.blue.withOpacity(0.05),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isByEmployee ? Icons.badge : Icons.admin_panel_settings,
                  color: isByEmployee ? Colors.orange : Colors.blue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customerName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark
                            ? AppDarkColors.textPrimary
                            : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (isByEmployee) ...[
                          Icon(
                            Icons.person_outline,
                            size: 12,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(width: 3),
                          Text(
                            creatorName,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(width: 3),
                        Text(
                          AppHelpers.formatDate(date),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Amount
              Text(
                AppHelpers.formatCurrency(amount),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? AppDarkColors.textPrimary : Colors.black87,
                ),
                textDirection: TextDirection.ltr,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
