import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/providers/theme_provider.dart';
import 'package:zhirox/screens/admin/pending_requests_screen.dart';
import 'package:zhirox/screens/shared/debt_list_screen.dart';
import 'package:zhirox/screens/shared/user_list_screen.dart';
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
  final Set<int> _visitedTabs = <int>{0};
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;
  String? _statsError;
  Future<void>? _statsLoad;
  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStats());
    _connectivitySub = ConnectivityService.instance.statusStream.listen((online) {
      if (online && mounted) unawaited(_loadStats());
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
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
    } catch (_) {
      loadError =
          'نەتوانرا زانیارییەکانی داشبۆرد نوێ بکرێنەوە. پەیوەندی ئینتەرنێت بپشکنە.';
    }

    if (!mounted) return;
    setState(() {
      if (freshStats != null) {
        _stats = freshStats!;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pendingNavCount = (_stats['pendingRequests'] as num?)?.toInt() ?? 0;

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
      body: IndexedStack(
        index: _currentIndex,
        children: List<Widget>.generate(
          screens.length,
          (index) => _visitedTabs.contains(index)
              ? screens[index]
              : const SizedBox.shrink(),
        ),
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
                  badgeCount: pendingNavCount,
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
    String label, {
    int badgeCount = 0,
  }) {
    final isSelected = _currentIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor =
        isDark ? AppDarkColors.textSecondary : const Color(0xFF98A2B3);

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              if (_currentIndex == index) return;
              setState(() {
                _visitedTabs.add(index);
                _currentIndex = index;
              });
              if (index == 0) unawaited(_loadStats());
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withOpacity(isDark ? 0.18 : 0.10)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        isSelected ? activeIcon : icon,
                        size: 22,
                        color: isSelected ? AppColors.primary : inactiveColor,
                      ),
                      if (badgeCount > 0)
                        Positioned(
                          top: -6,
                          right: -9,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 17),
                            height: 17,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.red.shade600,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: isDark ? AppDarkColors.card : Colors.white,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              badgeCount > 99 ? '99+' : '$badgeCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                                height: 1,
                              ),
                              textDirection: TextDirection.ltr,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? AppColors.primary : inactiveColor,
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
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

  Widget _buildNewDashboard(AuthProvider auth) {
    if (_isLoading && _stats.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_stats.isEmpty && _statsError != null) {
      return RefreshIndicator(
        onRefresh: _loadStats,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          children: [
            const SizedBox(height: 120),
            const Icon(
              Icons.cloud_off_rounded,
              size: 58,
              color: Colors.orange,
            ),
            const SizedBox(height: 18),
            Text(
              _statsError!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.7),
            ),
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton.icon(
                onPressed: () => _loadStats(),
                icon: const Icon(Icons.refresh),
                label: const Text('دووبارە هەوڵ بدە'),
              ),
            ),
          ],
        ),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final recentActivity = _stats['recentActivity'] as List<RecordModel>? ?? [];
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
                    // Compact top bar: secondary actions live in Settings.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Row(
                        children: [
                          Text(
                            AppStrings.appName,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.72),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _showAdminProfileMenu(auth),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.16),
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.tune_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Welcome - Tappable for profile menu
                    GestureDetector(
                      onTap: () => _showAdminProfileMenu(auth),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
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
                                  color: Colors.white.withOpacity(0.10),
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


          // ───── Recent Activity Header ─────
          SliverToBoxAdapter(
            child: Padding(
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
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Column(
                  children: [
                    Icon(Icons.history_rounded, size: 32, color: Colors.grey[300]),
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
    final marketName = auth.user?.getStringValue('market_name') ?? AppStrings.appName;
    final phone = auth.user?.getStringValue('phone') ?? 'نەدراوە';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.74,
          ),
          decoration: BoxDecoration(
            color: isDark ? AppDarkColors.card : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: isDark ? AppDarkColors.cardBorder : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.storefront_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            marketName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? AppDarkColors.textPrimary
                                  : const Color(0xFF1F2937),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            phone,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppDarkColors.textSecondary
                                  : Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'ڕێکخستنەکان',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppDarkColors.textSecondary
                            : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _settingsTile(
                  isDark: isDark,
                  icon: Icons.summarize_outlined,
                  iconColor: AppColors.primary,
                  title: 'کەشفی حیساب و ڕاپۆرت',
                  subtitle: 'ڕاپۆرتی قەرز و پارەدانەوە چاپ بکە',
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_showReportMenu(auth));
                  },
                ),
                _settingsTile(
                  isDark: isDark,
                  icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  iconColor: Colors.indigo,
                  title: isDark ? 'ڕووناکی' : 'دۆخی تاریک',
                  subtitle: 'ڕووکار و ڕەنگی ئەپ بگۆڕە',
                  onTap: () {
                    Navigator.pop(ctx);
                    context.read<ThemeProvider>().toggleTheme();
                  },
                ),
                const Divider(height: 24),
                _settingsTile(
                  isDark: isDark,
                  icon: Icons.phone_android_rounded,
                  iconColor: Colors.blue,
                  title: 'گۆڕینی ژمارە مۆبایل',
                  subtitle: phone,
                  ltrSubtitle: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showChangePhoneDialog(auth);
                  },
                ),
                _settingsTile(
                  isDark: isDark,
                  icon: Icons.lock_outline_rounded,
                  iconColor: Colors.orange,
                  title: 'گۆڕینی وشەی نهێنی',
                  subtitle: 'وشەی نهێنیی نوێ دابنێ',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showChangePasswordDialog(auth);
                  },
                ),
                const Divider(height: 24),
                _settingsTile(
                  isDark: isDark,
                  icon: Icons.logout_rounded,
                  iconColor: Colors.red,
                  title: AppStrings.logout,
                  subtitle: 'لە هەژمارەکەت بچۆ دەرەوە',
                  destructive: true,
                  showChevron: false,
                  onTap: () async {
                    Navigator.pop(ctx);
                    final confirm = await AppHelpers.showConfirmDialog(
                      context,
                      title: AppStrings.logout,
                      message: 'دڵنیایت لە چوونەدەرەوە؟',
                    );
                    if (confirm && mounted) auth.logout();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsTile({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool destructive = false,
    bool showChevron = true,
    bool ltrSubtitle = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: iconColor, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: destructive
                              ? Colors.red
                              : isDark
                                  ? AppDarkColors.textPrimary
                                  : const Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        textDirection:
                            ltrSubtitle ? TextDirection.ltr : TextDirection.rtl,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark
                              ? AppDarkColors.textSecondary
                              : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                if (showChevron)
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 20,
                    color: isDark ? Colors.grey[600] : Colors.grey[350],
                  ),
              ],
            ),
          ),
        ),
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
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'کەشفی حیساب',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              ListTile(
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
      );
      if (picked == null || !mounted) return;
      fromDate = picked.start;
      toDate = picked.end;
      final fromStr = DateFormat('yyyy-MM-dd').format(fromDate);
      final toStr = DateFormat(
        'yyyy-MM-dd',
      ).format(toDate.add(const Duration(days: 1)));
      dateFilter =
          'created >= "$fromStr 00:00:00" && created <= "$toStr 00:00:00"';
    }

    try {
      final allDebts = await PBService.getDebts(
        adminId: auth.userId,
        filter: dateFilter,
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
        toDate: toDate,
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
            backgroundColor: isDark ? AppDarkColors.card : Colors.white,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
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
            backgroundColor: isDark ? AppDarkColors.card : Colors.white,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
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
    bool isCurrency,
  ) {
    return Expanded(
      child: Container(
        height: 82,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withOpacity(0.14)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.16),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.72),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isCurrency
                        ? AppHelpers.formatCurrency(value)
                        : value.toInt().toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
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
    final creatorName = createdBy?.getStringValue('name') ?? '';
    final customerName =
        customer?.getStringValue('name') ?? 'کڕیار سڕدراوەتەوە';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isByEmployee ? Colors.orange : AppColors.primary;

    return Container(
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
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isByEmployee ? Icons.badge_outlined : Icons.receipt_long_outlined,
              color: accent,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppDarkColors.textPrimary
                        : const Color(0xFF344054),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (isByEmployee && creatorName.isNotEmpty) creatorName,
                    AppHelpers.formatDate(date),
                  ].join('  •  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
          const SizedBox(width: 10),
          Text(
            AppHelpers.formatCurrency(amount),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: isDark
                  ? AppDarkColors.textPrimary
                  : const Color(0xFF101828),
            ),
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }
}
