import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/providers/theme_provider.dart';
import 'package:zhirox/screens/admin/pending_requests_screen.dart';
import 'package:zhirox/screens/shared/debt_list_screen_clean.dart';
import 'package:zhirox/screens/shared/user_list_screen_clean.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class ManagerDashboardPhase1 extends StatefulWidget {
  const ManagerDashboardPhase1({super.key});

  @override
  State<ManagerDashboardPhase1> createState() => _ManagerDashboardPhase1State();
}

class _ManagerDashboardPhase1State extends State<ManagerDashboardPhase1> {
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
    try {
      final stats = await PBService.getDashboardStats(adminId: auth.userId);
      if (mounted) _stats = stats;
    } catch (_) {
      // Market-facing UI stays calm and keeps the last visible state.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final screens = [
      _ManagerHome(
        stats: _stats,
        isLoading: _isLoading,
        onRefresh: _loadStats,
        onOpenTab: (i) => setState(() => _currentIndex = i),
      ),
      UserListScreenClean(key: const ValueKey('customers_clean'), role: 'customer', adminId: auth.userId),
      UserListScreenClean(key: const ValueKey('employees_clean'), role: 'employee', adminId: auth.userId),
      const DebtListScreen(key: ValueKey('clean_debts')),
      PendingRequestsScreen(key: ValueKey('pending_${auth.userId}'), adminId: auth.userId),
    ];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
      body: AnimatedSwitcher(duration: const Duration(milliseconds: 280), child: screens[_currentIndex]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? AppDarkColors.card : Colors.white,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.18 : 0.06), blurRadius: 24, offset: const Offset(0, -6))],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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
    final selected = _currentIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        setState(() => _currentIndex = index);
        if (index == 0) _loadStats();
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: EdgeInsets.symmetric(horizontal: selected ? 12 : 8, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected ? LinearGradient(colors: [AppColors.primary, AppColors.primary.withOpacity(0.72)]) : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? activeIcon : icon, color: selected ? Colors.white : (isDark ? AppDarkColors.textSecondary : Colors.grey[400]), size: 22),
            if (selected) ...[
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
            ],
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

  const _ManagerHome({required this.stats, required this.isLoading, required this.onRefresh, required this.onOpenTab});

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

  int _score(double totalDebt, double totalRemaining, int requests) {
    if (totalDebt <= 0) return 100;
    final remainingRatio = (totalRemaining / totalDebt).clamp(0.0, 1.0);
    return (100 - (remainingRatio * 45) - (requests * 4)).clamp(35, 100).round();
  }

  String _scoreLabel(int score) {
    if (score >= 85) return 'پارەی مارکێت بە باشی پارێزراوە';
    if (score >= 70) return 'ڕەوش باشە، بەڵام چاودێری قەرزی ماوە بەردەوام بکە';
    if (score >= 50) return 'ئەمڕۆ پێویستە قەرزە دواکەوتووەکان پێش بخەیت';
    return 'پێویستە قەرزی نوێ کەم بکرێت و پارە وەرگرتنەوە پێش بخرێت';
  }

  String _missionText(double totalRemaining, double totalPayments, int requests) {
    if (requests > 0) return 'یەکەم داواکارییە گرنگەکان ببینە و بڕیار بدە.';
    if (totalRemaining > totalPayments && totalRemaining > 0) return 'ئەمڕۆ سەرەتا پەیوەندی بە کڕیارانی قەرزی ماوە بکە.';
    if (totalPayments > 0) return 'پارە وەرگرتنەوە باشە؛ قەرزی نوێ بە سنوور بەردەوام بکە.';
    return 'ڕۆژەکە بە پشکنینی کڕیارەکان و قەرزی ماوە دەست پێ بکە.';
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
    final requests = _int('pendingRequests');
    final score = _score(totalDebt, totalRemaining, requests);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroCard(
            marketName: auth.marketName.isEmpty ? AppStrings.appName : auth.marketName,
            score: score,
            scoreLabel: _scoreLabel(score),
            onToggleTheme: () => context.read<ThemeProvider>().toggleTheme(),
          ),
          const SizedBox(height: 16),
          if (isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else ...[
            _MissionCard(
              cardColor: cardColor,
              textColor: textColor,
              subColor: subColor,
              mission: _missionText(totalRemaining, totalPayments, requests),
              requests: requests,
              onOpenApprovals: () => onOpenTab(4),
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 1.18,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _StatCard(title: 'کڕیارەکان', value: totalCustomers.toInt().toString(), icon: Icons.people, color: AppColors.primary, cardColor: cardColor, textColor: textColor, subColor: subColor),
                _StatCard(title: 'کۆی قەرز', value: AppHelpers.formatCurrency(totalDebt), icon: Icons.receipt_long, color: AppColors.warning, cardColor: cardColor, textColor: textColor, subColor: subColor),
                _StatCard(title: 'قەرزی ماوە', value: AppHelpers.formatCurrency(totalRemaining), icon: Icons.account_balance_wallet, color: AppColors.danger, cardColor: cardColor, textColor: textColor, subColor: subColor),
                _StatCard(title: 'پارەی وەرگیراو', value: AppHelpers.formatCurrency(totalPayments), icon: Icons.payments, color: AppColors.secondary, cardColor: cardColor, textColor: textColor, subColor: subColor),
              ],
            ),
            const SizedBox(height: 14),
            _DecisionCard(
              cardColor: cardColor,
              textColor: textColor,
              subColor: subColor,
              requests: requests,
              totalRemaining: totalRemaining,
              onOpenApprovals: () => onOpenTab(4),
            ),
            const SizedBox(height: 14),
            _QuickActionsCard(
              cardColor: cardColor,
              textColor: textColor,
              subColor: subColor,
              onCustomers: () => onOpenTab(1),
              onEmployees: () => onOpenTab(2),
              onDebts: () => onOpenTab(3),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final String marketName;
  final int score;
  final String scoreLabel;
  final VoidCallback onToggleTheme;

  const _HeroCard({required this.marketName, required this.score, required this.scoreLabel, required this.onToggleTheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.primary, AppColors.primary.withOpacity(0.72)], begin: Alignment.topRight, end: Alignment.bottomLeft),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.22), blurRadius: 20, offset: const Offset(0, 10))],
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
                      Text('ناوەندی پاراستنی پارە', style: TextStyle(color: Colors.white.withOpacity(0.76))),
                      const SizedBox(height: 5),
                      Text(marketName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                IconButton(onPressed: onToggleTheme, icon: const Icon(Icons.contrast_rounded, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle),
                    child: Center(child: Text('$score', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('خاڵی پاراستنی پارە', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(scoreLabel, style: TextStyle(color: Colors.white.withOpacity(0.82), height: 1.45)),
                      ],
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
}

class _MissionCard extends StatelessWidget {
  final Color cardColor;
  final Color textColor;
  final Color subColor;
  final String mission;
  final int requests;
  final VoidCallback onOpenApprovals;

  const _MissionCard({required this.cardColor, required this.textColor, required this.subColor, required this.mission, required this.requests, required this.onOpenApprovals});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [const Icon(Icons.flag_rounded, color: AppColors.secondary), const SizedBox(width: 8), Text('ئەرکی پارەی ئەمڕۆ', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16))]),
          const SizedBox(height: 10),
          Text(mission, style: TextStyle(color: subColor, height: 1.6)),
          if (requests > 0) ...[
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: onOpenApprovals, icon: const Icon(Icons.verified_rounded), label: const Text('بڕیاری داواکارییەکان بدە')),
          ],
        ],
      ),
    );
  }
}

class _DecisionCard extends StatelessWidget {
  final Color cardColor;
  final Color textColor;
  final Color subColor;
  final int requests;
  final double totalRemaining;
  final VoidCallback onOpenApprovals;

  const _DecisionCard({required this.cardColor, required this.textColor, required this.subColor, required this.requests, required this.totalRemaining, required this.onOpenApprovals});

  @override
  Widget build(BuildContext context) {
    final hasDebtToWatch = totalRemaining > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [const Icon(Icons.psychology_alt_rounded, color: AppColors.primary), const SizedBox(width: 8), Text('چی پێویستی بە بڕیاری منە؟', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16))]),
          const SizedBox(height: 12),
          _DecisionLine(icon: Icons.verified_rounded, text: requests > 0 ? '$requests داواکاری پێویستی بە ڕێگەپێدانی تۆ هەیە.' : 'ئێستا هیچ داواکارییەکی گرنگ نییە.', color: requests > 0 ? AppColors.warning : AppColors.secondary, subColor: subColor),
          const SizedBox(height: 8),
          _DecisionLine(icon: Icons.account_balance_wallet_rounded, text: hasDebtToWatch ? 'قەرزی ماوە بەردەوام چاودێری بکە.' : 'قەرزی ماوە نییە؛ ڕەوشی پارە پاکە.', color: hasDebtToWatch ? AppColors.danger : AppColors.secondary, subColor: subColor),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: onOpenApprovals, icon: const Icon(Icons.verified_rounded), label: const Text('کردنەوەی ڕێگەپێدانەکان')),
        ],
      ),
    );
  }
}

class _DecisionLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final Color subColor;

  const _DecisionLine({required this.icon, required this.text, required this.color, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: subColor, height: 1.5))),
      ],
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  final Color cardColor;
  final Color textColor;
  final Color subColor;
  final VoidCallback onCustomers;
  final VoidCallback onEmployees;
  final VoidCallback onDebts;

  const _QuickActionsCard({required this.cardColor, required this.textColor, required this.subColor, required this.onCustomers, required this.onEmployees, required this.onDebts});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('کاری خێرای بەڕێوەبەر', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _QuickAction(label: 'کڕیارەکان', icon: Icons.people_rounded, onTap: onCustomers)),
              const SizedBox(width: 8),
              Expanded(child: _QuickAction(label: 'قەرزەکان', icon: Icons.receipt_long_rounded, onTap: onDebts)),
              const SizedBox(width: 8),
              Expanded(child: _QuickAction(label: 'کارمەندان', icon: Icons.badge_rounded, onTap: onEmployees)),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickAction({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11)),
          ],
        ),
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

  const _StatCard({required this.title, required this.value, required this.icon, required this.color, required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color)),
          const Spacer(),
          Text(title, style: TextStyle(color: subColor, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 17), textDirection: TextDirection.ltr),
        ],
      ),
    );
  }
}
