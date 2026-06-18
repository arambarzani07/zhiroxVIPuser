import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/providers/theme_provider.dart';
import 'package:zhirox/screens/admin/pending_requests_screen.dart';
import 'package:zhirox/screens/shared/debt_list_screen.dart';
import 'package:zhirox/screens/shared/user_list_screen.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class ManagerDashboardClean extends StatefulWidget {
  const ManagerDashboardClean({super.key});

  @override
  State<ManagerDashboardClean> createState() => _ManagerDashboardCleanState();
}

class _ManagerDashboardCleanState extends State<ManagerDashboardClean> {
  int _currentIndex = 0;
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStats());
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    if (auth.userId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final stats = await PBService.getDashboardStats(adminId: auth.userId);
      if (mounted) _stats = stats;
    } catch (_) {
      // Market UI stays calm; old values remain visible when available.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screens = [
      _ManagerHome(
        stats: _stats,
        isLoading: _isLoading,
        onRefresh: _loadStats,
        onOpenTab: (index) => setState(() => _currentIndex = index),
      ),
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
      const DebtListScreen(key: ValueKey('debts')),
      PendingRequestsScreen(
        key: ValueKey('pending_${auth.userId}'),
        adminId: auth.userId,
      ),
    ];

    return Scaffold(
      backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
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
              color: Colors.black.withOpacity(isDark ? 0.18 : 0.06),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _nav(0, Icons.dashboard_outlined, Icons.dashboard_rounded, 'داشبۆرد'),
                _nav(1, Icons.people_outline, Icons.people_rounded, 'کڕیار'),
                _nav(2, Icons.badge_outlined, Icons.badge_rounded, 'کارمەند'),
                _nav(3, Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'قەرز'),
                _nav(4, Icons.verified_outlined, Icons.verified_rounded, 'ڕێگەپێدان'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _nav(int index, IconData icon, IconData activeIcon, String label) {
    final isSelected = _currentIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        setState(() => _currentIndex = index);
        if (index == 0) _loadStats();
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
        padding: EdgeInsets.symmetric(horizontal: isSelected ? 13 : 9, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [AppColors.primary, AppColors.primary.withOpacity(0.72)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.24),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              size: 23,
              color: isSelected ? Colors.white : (isDark ? AppDarkColors.textSecondary : Colors.grey[400]),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOutCubic,
              child: isSelected
                  ? Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
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
}

class _ManagerHome extends StatelessWidget {
  final Map<String, dynamic> stats;
  final bool isLoading;
  final Future<void> Function() onRefresh;
  final ValueChanged<int> onOpenTab;

  const _ManagerHome({
    required this.stats,
    required this.isLoading,
    required this.onRefresh,
    required this.onOpenTab,
  });

  double _num(String key) {
    final value = stats[key];
    if (value is num) return value.toDouble();
    return 0;
  }

  int _int(String key) {
    final value = stats[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  int _moneyProtectionScore(double totalDebt, double totalRemaining, int pendingCount) {
    if (totalDebt <= 0) return 100;
    final remainingRatio = (totalRemaining / totalDebt).clamp(0.0, 1.0);
    final score = 100 - (remainingRatio * 45) - (pendingCount * 4);
    return score.clamp(35, 100).round();
  }

  String _scoreLabel(int score) {
    if (score >= 80) return 'باش';
    if (score >= 60) return 'پێویستی بە چاودێری هەیە';
    return 'پێویستی بە بڕیاری خێرا هەیە';
  }

  Color _scoreColor(int score) {
    if (score >= 80) return AppColors.secondary;
    if (score >= 60) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppDarkColors.card : Colors.white;
    final textColor = isDark ? AppDarkColors.textPrimary : AppColors.textPrimary;
    final subColor = isDark ? AppDarkColors.textSecondary : AppColors.textSecondary;

    final totalCustomers = _num('totalCustomers');
    final totalDebt = _num('totalDebt');
    final totalRemaining = _num('totalRemaining');
    final totalPayments = _num('totalPayments');
    final pendingCount = _int('pendingRequests');
    final score = _moneyProtectionScore(totalDebt, totalRemaining, pendingCount);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primary.withOpacity(0.72)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.22),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('داشبۆردی بەڕێوەبەر', style: TextStyle(color: Colors.white.withOpacity(0.76))),
                            const SizedBox(height: 5),
                            Text(
                              auth.marketName.isEmpty ? AppStrings.appName : auth.marketName,
                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => context.read<ThemeProvider>().toggleTheme(),
                        icon: const Icon(Icons.contrast_rounded, color: Colors.white),
                        tooltip: 'گۆڕینی ڕووناکی',
                      ),
                      IconButton(
                        onPressed: () async {
                          final confirm = await AppHelpers.showConfirmDialog(
                            context,
                            title: AppStrings.logout,
                            message: 'دڵنیایت لە چوونەدەرەوە؟',
                          );
                          if (confirm && context.mounted) {
                            context.read<AuthProvider>().logout();
                          }
                        },
                        icon: const Icon(Icons.logout_rounded, color: Colors.white),
                        tooltip: AppStrings.logout,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(color: _scoreColor(score), shape: BoxShape.circle),
                          child: Center(
                            child: Text('$score', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('پاراستنی پارە', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 4),
                              Text(_scoreLabel(score), style: TextStyle(color: Colors.white.withOpacity(0.78), height: 1.4)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else
            GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 1.22,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _StatCard(title: 'کڕیارەکان', value: totalCustomers.toInt().toString(), icon: Icons.people, color: AppColors.primary, cardColor: cardColor, textColor: textColor, subColor: subColor),
                _StatCard(title: 'کۆی قەرز', value: AppHelpers.formatCurrency(totalDebt), icon: Icons.receipt_long, color: AppColors.warning, cardColor: cardColor, textColor: textColor, subColor: subColor),
                _StatCard(title: 'قەرزی ماوە', value: AppHelpers.formatCurrency(totalRemaining), icon: Icons.account_balance_wallet, color: AppColors.danger, cardColor: cardColor, textColor: textColor, subColor: subColor),
                _StatCard(title: 'وەرگیراو', value: AppHelpers.formatCurrency(totalPayments), icon: Icons.payments, color: AppColors.secondary, cardColor: cardColor, textColor: textColor, subColor: subColor),
              ],
            ),
          const SizedBox(height: 16),
          _DecisionCard(
            pendingCount: pendingCount,
            cardColor: cardColor,
            textColor: textColor,
            subColor: subColor,
            onTap: () => onOpenTab(4),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
            child: Row(
              children: [
                const Icon(Icons.shield_rounded, color: AppColors.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Zhirox کارە گرنگەکان بە شێوەی پارێزراو ڕێکدەخات و تەنها ئەو بڕیارانە دەهێنێتە پێش کە پەیوەندییان بە پارەی مارکێتەوە هەیە.',
                    style: TextStyle(color: subColor, height: 1.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DecisionCard extends StatelessWidget {
  final int pendingCount;
  final Color cardColor;
  final Color textColor;
  final Color subColor;
  final VoidCallback onTap;

  const _DecisionCard({
    required this.pendingCount,
    required this.cardColor,
    required this.textColor,
    required this.subColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_alt_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('چی پێویستی بە بڕیاری منە؟', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            pendingCount > 0
                ? '$pendingCount داواکاری پێویستی بە ڕێگەپێدانی تۆ هەیە.'
                : 'ئێستا هیچ داواکارییەکی گرنگ نییە. چاودێری قەرزی ماوە بەردەوام بکە.',
            style: TextStyle(color: subColor, height: 1.6),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.verified_rounded),
            label: const Text('کردنەوەی ڕێگەپێدانەکان'),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.cardColor,
    required this.textColor,
    required this.subColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color),
          ),
          const Spacer(),
          Text(title, style: TextStyle(color: subColor, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 17), textDirection: TextDirection.ltr),
        ],
      ),
    );
  }
}
