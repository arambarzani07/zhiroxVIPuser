import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/admin/admin_settings_screen.dart';
import 'package:zhirox/screens/shared/debt_detail_screen.dart';
import 'package:zhirox/screens/shared/user_list_screen.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/services/pdf_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/services/connectivity_service.dart';
import 'package:zhirox/widgets/app_async_state.dart';
import 'package:zhirox/widgets/zhirox_shell.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  static const BoxConstraints _compactDialogConstraints = BoxConstraints(
    maxWidth: 420,
  );
  int _currentIndex = 0;
  final Set<int> _visitedTabs = <int>{0};
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;
  String? _statsError;
  Future<void>? _statsLoad;
  StreamSubscription<bool>? _connectivitySub;
  RealtimeChannel? _dashboardRealtimeChannel;
  Timer? _dashboardRealtimeDebounce;
  bool _dashboardRealtimeRefreshPending = false;
  String _recentActivityFilter = 'debt';

  @override
  void initState() {
    super.initState();
    unawaited(_loadStats());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_subscribeDashboardRealtime());
    });
    _connectivitySub = ConnectivityService.instance.statusStream.listen((online) {
      if (online && mounted) unawaited(_loadStats());
    });
  }

  @override
  void dispose() {
    _dashboardRealtimeDebounce?.cancel();
    _dashboardRealtimeRefreshPending = false;
    final channel = _dashboardRealtimeChannel;
    if (channel != null) {
      unawaited(PBService.client.removeChannel(channel));
    }
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _subscribeDashboardRealtime() async {
    try {
      await PBService.ensureInitialized();
      if (!mounted) return;
      final previous = _dashboardRealtimeChannel;
      if (previous != null) {
        try {
          await PBService.client.removeChannel(previous);
        } catch (_) {}
      }
      final channel = PBService.client
          .channel('admin-dashboard:${DateTime.now().microsecondsSinceEpoch}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'profiles',
            callback: (_) => _scheduleDashboardRealtimeRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'debts',
            callback: (_) => _scheduleDashboardRealtimeRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'payments',
            callback: (_) => _scheduleDashboardRealtimeRefresh(),
          )
          .subscribe();
      if (!mounted) {
        await PBService.client.removeChannel(channel);
        return;
      }
      _dashboardRealtimeChannel = channel;
    } catch (_) {
      // Pull-to-refresh and reconnect remain available if Realtime is offline.
    }
  }

  void _scheduleDashboardRealtimeRefresh() {
    if (!mounted) return;
    _dashboardRealtimeDebounce?.cancel();
    _dashboardRealtimeDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) unawaited(_refreshDashboardAfterRealtime());
    });
  }

  Future<void> _refreshDashboardAfterRealtime() async {
    if (!mounted) return;
    final activeLoad = _statsLoad;
    if (activeLoad != null) {
      if (_dashboardRealtimeRefreshPending) return;
      _dashboardRealtimeRefreshPending = true;
      try {
        await activeLoad;
      } catch (_) {}
      _dashboardRealtimeRefreshPending = false;
      if (!mounted) return;
    }
    await _loadStats();
  }

  Future<void> _loadStats() {
    final activeLoad = _statsLoad;
    if (activeLoad != null) return activeLoad;

    final load = _loadStatsOnce();
    _statsLoad = load;
    unawaited(
      load.whenComplete(() {
        if (identical(_statsLoad, load)) _statsLoad = null;
      }),
    );
    return load;
  }

  Future<void> _loadStatsOnce() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.userId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statsError = null;
        });
      }
      return;
    }

    // Only block the dashboard on the first load. Refreshes keep the current
    // UI visible so tab changes/reconnects do not flash a full-screen spinner.
    if (_stats.isEmpty && !_isLoading) {
      setState(() => _isLoading = true);
    }

    Map<String, dynamic>? freshStats;
    String? loadError;
    try {
      freshStats = await PBService.getDashboardStats(adminId: auth.userId);
    } catch (error) {
      loadError = AppHelpers.backendErrorMessage(
        error,
        fallback: 'نەتوانرا زانیارییەکانی داشبۆرد نوێ بکرێنەوە. دووبارە هەوڵ بدە.',
      );
    }

    if (!mounted) return;
    setState(() {
      if (freshStats != null) {
        _stats = freshStats;
        _statsError = null;
      } else {
        _statsError = loadError;
      }
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final pendingNavCount = (_stats['pendingRequests'] as num?)?.toInt() ?? 0;

    final screens = [
      _buildNewDashboard(auth),
      UserListScreen(
        key: const ValueKey('customers'),
        role: 'customer',
        adminId: auth.userId,
      ),
      AdminSettingsScreen(
        key: ValueKey('settings_${auth.userId}'),
        pendingCount: pendingNavCount,
        onOpenReports: () => unawaited(_showReportMenu(auth)),
        onChangePhone: () => _showChangePhoneDialog(auth),
        onChangePassword: () => _showChangePasswordDialog(auth),
      ),
    ];

    return ZhiroxAppShell(
      index: _currentIndex,
      pages: List<Widget>.generate(
        screens.length,
        (index) => _visitedTabs.contains(index)
            ? screens[index]
            : const SizedBox.shrink(),
      ),
      destinations: [
        const ZhiroxDestination(
          label: 'سەرەکی',
          icon: Icons.space_dashboard_outlined,
          selectedIcon: Icons.space_dashboard_rounded,
        ),
        const ZhiroxDestination(
          label: 'کڕیار',
          icon: Icons.people_outline_rounded,
          selectedIcon: Icons.people_rounded,
        ),
        ZhiroxDestination(
          label: 'زیاتر',
          icon: Icons.grid_view_outlined,
          selectedIcon: Icons.grid_view_rounded,
          badgeCount: pendingNavCount,
        ),
      ],
      onSelected: (index) {
        if (_currentIndex == index) {
          if (index == 0) unawaited(_loadStats());
          return;
        }
        setState(() {
          _visitedTabs.add(index);
          _currentIndex = index;
        });
        if (index == 0) unawaited(_loadStats());
      },
    );
  }

  Widget _buildNewDashboard(AuthProvider auth) {
    if (_isLoading && _stats.isEmpty) {
      return const AppAsyncStateView(
        state: AppAsyncState.loading,
        loadingLabel: 'داشبۆرد ئامادە دەکرێت...',
        child: SizedBox.shrink(),
      );
    }
    if (_stats.isEmpty && _statsError != null) {
      return AppAsyncStateView(
        state: AppAsyncState.error,
        message: _statsError,
        onRetry: _loadStats,
        child: const SizedBox.shrink(),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final recentActivity = _stats['recentActivity'] as List<RecordModel>? ?? [];
    final debtActivity = recentActivity
        .where((activity) => activity.getStringValue('event_type') != 'payment')
        .toList(growable: false);
    final paymentActivity = recentActivity
        .where((activity) => activity.getStringValue('event_type') == 'payment')
        .toList(growable: false);
    final filteredRecentActivity = _recentActivityFilter == 'payment'
        ? paymentActivity
        : debtActivity;
    final debtActivityTotals = _sumRecentActivityByCurrency(debtActivity);
    final paymentActivityTotals = _sumRecentActivityByCurrency(paymentActivity);
    final totalCustomers = (_stats['totalCustomers'] ?? 0).toDouble();
    final totalDebt = (_stats['totalDebt'] ?? 0).toDouble();
    final totalRemaining = (_stats['totalRemaining'] ?? 0).toDouble();
    final totalPayments = (_stats['totalPayments'] ?? 0).toDouble();
    final totalDebtUsd = (_stats['totalDebtUsd'] ?? 0).toDouble();
    final totalRemainingUsd = (_stats['totalRemainingUsd'] ?? 0).toDouble();
    final totalPaymentsUsd = (_stats['totalPaymentsUsd'] ?? 0).toDouble();

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: CustomScrollView(
        key: const PageStorageKey('admin-dashboard-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverList(
            delegate: SliverChildListDelegate([
        // ───── Gradient Header with Stats (fixed) ─────
        Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.primary.withValues(alpha: 0.8),
                    AppColors.primary.withValues(alpha: 0.6),
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
                    // Compact top bar: secondary actions live in Settings.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Row(
                        children: [
                          Text(
                            AppStrings.appName,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),

                    // Welcome - Tappable for profile menu
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _currentIndex = 2;
                          _visitedTabs.add(2);
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: Row(
                          children: [
                            // Avatar
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
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
                                      color: Colors.white.withValues(alpha: 0.7),
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
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
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
                                usdValue: totalDebtUsd,
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
                                usdValue: totalRemainingUsd,
                              ),
                              const SizedBox(width: 10),
                              _buildHeaderStat(
                                Icons.payments,
                                'وەرگیراو',
                                totalPayments,
                                true,
                                usdValue: totalPaymentsUsd,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // ───── Subscription Warning (inside gradient) ─────
                    if (auth.subscriptionDaysLeft <= 10)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: const Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.amberAccent,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
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
                                        color: Colors.white.withValues(alpha: 0.8),
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


        // ───── Recent Activity Header (fixed) ─────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Row(
            children: [
              Icon(
                Icons.history,
                size: 18,
                color: isDark
                    ? AppDarkColors.textSecondary
                    : Colors.black54,
              ),
              const SizedBox(width: 8),
              Text(
                'چالاکییە تازەکان',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
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
                  '${filteredRecentActivity.length}',
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
              Text(
                '٢٤ کاتژمێر',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppDarkColors.textSecondary
                      : const Color(0xFF98A2B3),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: _buildRecentActivityFilterButton(
                  value: 'debt',
                  label: 'قەرزەکان',
                  icon: Icons.receipt_long_outlined,
                  count: debtActivity.length,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildRecentActivityFilterButton(
                  value: 'payment',
                  label: 'پارەدانەوەکان',
                  icon: Icons.payments_outlined,
                  count: paymentActivity.length,
                ),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: _buildRecentActivityTotalCard(
                  label: 'کۆی قەرزە تازەکان',
                  icon: Icons.receipt_long_rounded,
                  totals: debtActivityTotals,
                  accent: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildRecentActivityTotalCard(
                  label: 'کۆی پارەدانەوە تازەکان',
                  icon: Icons.payments_rounded,
                  totals: paymentActivityTotals,
                  accent: Colors.green,
                ),
              ),
            ],
          ),
        ),

        // One vertical scroll keeps the full dashboard reachable on every phone.
        if (filteredRecentActivity.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 32,
                  color: Colors.grey[300],
                ),
                const SizedBox(height: 10),
                Text(
                  _recentActivityFilter == 'payment'
                      ? 'لە ٢٤ کاتژمێری ڕابردوودا هیچ پارەدانەوەیەک نییە'
                      : 'لە ٢٤ کاتژمێری ڕابردوودا هیچ قەرزێکی تازە نییە',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          )
        else
          ...List<Widget>.generate(
            filteredRecentActivity.length,
            (index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildActivityCard(filteredRecentActivity[index], index),
            ),
          ),
        const SizedBox(height: 14),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _showReportMenu(AuthProvider auth) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).brightness == Brightness.dark
                ? AppDarkColors.card
                : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'کەشفی حیساب',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: Icon(Icons.select_all_rounded, color: AppColors.primary),
                title: const Text(
                  'هەموو ماوەکان',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('ڕاپۆرتی تەواوی قەرزەکان'),
                onTap: () => Navigator.pop(ctx, 'all'),
              ),
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: const Icon(Icons.date_range_rounded, color: Colors.orange),
                title: const Text(
                  'دیاریکردنی بەروار',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('لە بەروارێکەوە تا بەروارێکی تر'),
                onTap: () => Navigator.pop(ctx, 'custom'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;

    DateTime? fromDate;
    DateTime? toDate;
    DateTime? reportToDate;
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
      );
      if (picked == null || !mounted) return;
      fromDate = picked.start;
      reportToDate = picked.end;
      toDate = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day + 1,
      );
    }

    try {
      final allDebts = await PBService.getAllAdminDebts(
        adminId: auth.userId,
        fromDate: fromDate,
        toDate: toDate,
      );
      double reportDebt = 0;
      double reportRemaining = 0;
      double reportPaid = 0;
      final customerIds = <String>{};
      for (final debt in allDebts) {
        final amount = debt.getDoubleValue('amount');
        final remaining = debt.getDoubleValue('remaining');
        reportDebt += amount;
        reportRemaining += remaining;
        reportPaid += amount - remaining;
        customerIds.add(debt.getStringValue('customer'));
      }
      await PdfService.generateAdminReport(
        allDebts: allDebts,
        marketName: AppStrings.appName,
        adminName: auth.userName,
        adminPhone: auth.user?.getStringValue('phone') ?? '',
        totalDebt: reportDebt,
        totalRemaining: reportRemaining,
        totalPaid: reportPaid,
        totalCustomers: customerIds.length,
        fromDate: fromDate,
        toDate: reportToDate,
      );
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          'نەتوانرا ڕاپۆرت دروست بکرێت',
          isError: true,
        );
      }
    }
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
            scrollable: true,
            constraints: _compactDialogConstraints,
            backgroundColor: isDark ? AppDarkColors.card : Colors.white,
            insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            contentPadding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
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
                          if (!ctx.mounted || !mounted) return;
                          if (existing.items.isNotEmpty) {
                            if (ctx.mounted) setDialogState(() => isSaving = false);
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
                          if (!ctx.mounted || !mounted) return;
                          if (mounted) {
                            Navigator.pop(ctx);
                            AppHelpers.showSnackBar(
                              context,
                              'ژمارە مۆبایل گۆڕا ✅',
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) setDialogState(() => isSaving = false);
                          if (mounted) {
                            AppHelpers.showSnackBar(
                              context,
                              'نەتوانرا گۆڕانکاری پاشەکەوت بکرێت',
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
            scrollable: true,
            constraints: _compactDialogConstraints,
            backgroundColor: isDark ? AppDarkColors.card : Colors.white,
            insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            contentPadding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
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
                          if (!ctx.mounted || !mounted) return;
                          if (mounted) {
                            Navigator.pop(ctx);
                            AppHelpers.showSnackBar(
                              context,
                              'وشەی نهێنی گۆڕا ✅',
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) setDialogState(() => isSaving = false);
                          if (mounted) {
                            AppHelpers.showSnackBar(
                              context,
                              'نەتوانرا گۆڕانکاری پاشەکەوت بکرێت',
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
    bool isCurrency, {
    double usdValue = 0,
  }) {
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 82),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isCurrency
                        ? AppHelpers.formatCurrency(value)
                        : value.toInt().toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  if (isCurrency && usdValue != 0) ...[
                    const SizedBox(height: 1),
                    Text(
                      AppHelpers.formatCurrencyWithType(
                        usdValue,
                        'USD',
                        showConversion: false,
                      ),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontWeight: FontWeight.w700,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, double> _sumRecentActivityByCurrency(
    Iterable<RecordModel> activities,
  ) {
    final totals = <String, double>{'IQD': 0, 'USD': 0};
    for (final activity in activities) {
      final rawCurrency = activity.getStringValue('currency').trim().toUpperCase();
      final currency = rawCurrency == 'USD' ? 'USD' : 'IQD';
      totals[currency] = (totals[currency] ?? 0) + activity.getDoubleValue('amount');
    }
    return totals;
  }

  Widget _buildRecentActivityTotalCard({
    required String label,
    required IconData icon,
    required Map<String, double> totals,
    required Color accent,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iqd = totals['IQD'] ?? 0;
    final usd = totals['USD'] ?? 0;

    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? AppDarkColors.cardBorder
              : const Color(0xFFE9EDF3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? AppDarkColors.textPrimary
                        : const Color(0xFF344054),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            AppHelpers.formatCurrencyWithType(
              iqd,
              'IQD',
              showConversion: false,
            ),
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            AppHelpers.formatCurrencyWithType(
              usd,
              'USD',
              showConversion: false,
            ),
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? AppDarkColors.textSecondary
                  : const Color(0xFF667085),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivityFilterButton({
    required String value,
    required String label,
    required IconData icon,
    required int count,
  }) {
    final isSelected = _recentActivityFilter == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isSelected
        ? Colors.white
        : (isDark ? AppDarkColors.textSecondary : const Color(0xFF667085));
    final background = isSelected
        ? AppColors.primary
        : (isDark ? AppDarkColors.card : Colors.white);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () {
          if (_recentActivityFilter == value) return;
          setState(() => _recentActivityFilter = value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : (isDark
                      ? AppDarkColors.cardBorder
                      : const Color(0xFFE4E7EC)),
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.16),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 22),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.18)
                      : AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDebtActivity(RecordModel activity) async {
    final debtId = activity.id.trim();
    if (debtId.isEmpty || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DebtDetailScreen(debtId: debtId),
      ),
    );
    if (mounted) await _loadStats();
  }

  Widget _buildActivityCard(RecordModel activity, int index) {
    final customer = AppHelpers.expandedRecord(activity, 'customer');
    final createdBy = AppHelpers.expandedRecord(activity, 'created_by');

    final amount = activity.getDoubleValue('amount');
    final date = activity.getStringValue('created');
    final currency = activity.getStringValue('currency').isEmpty
        ? 'IQD'
        : activity.getStringValue('currency');
    final eventType = activity.getStringValue('event_type');
    final isPayment = eventType == 'payment';
    final isByEmployee = createdBy?.getStringValue('role') == 'employee';
    final creatorName = createdBy?.getStringValue('name') ?? '';
    final customerName =
        customer?.getStringValue('name') ?? 'کڕیار سڕدراوەتەوە';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isPayment ? Colors.green.shade600 : AppColors.primary;
    final activityLabel = isPayment ? 'پارەدانەوە' : 'قەرز';

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: isPayment ? null : () => _openDebtActivity(activity),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isPayment
                  ? Icons.payments_outlined
                  : Icons.receipt_long_outlined,
              color: accent,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        customerName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppDarkColors.textPrimary
                              : const Color(0xFF344054),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        activityLabel,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (isByEmployee && creatorName.isNotEmpty) creatorName,
                    AppHelpers.formatDate(date),
                  ].join('  •  '),
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.4,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : const Color(0xFF98A2B3),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    AppHelpers.formatCurrencyWithType(
                      amount,
                      currency,
                      showConversion: false,
                    ),
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isPayment
                          ? accent
                          : (isDark
                                ? AppDarkColors.textPrimary
                                : const Color(0xFF101828)),
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ],
            ),
          ),
          if (!isPayment) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_left_rounded,
              size: 19,
              color: isDark
                  ? AppDarkColors.textSecondary
                  : const Color(0xFF98A2B3),
            ),
          ],
        ],
      ),
        ),
      ),
    );
  }

}
