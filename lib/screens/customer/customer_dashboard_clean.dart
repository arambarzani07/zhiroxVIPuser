import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/providers/theme_provider.dart';
import 'package:zhirox/screens/shared/debt_detail_screen.dart';
import 'package:zhirox/screens/shared/user_profile_screen.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class CustomerDashboardClean extends StatefulWidget {
  const CustomerDashboardClean({super.key});

  @override
  State<CustomerDashboardClean> createState() => _CustomerDashboardCleanState();
}

class _CustomerDashboardCleanState extends State<CustomerDashboardClean> {
  int _currentIndex = 0;
  List<RecordModel> _debts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDebts());
  }

  Future<void> _loadDebts() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    if (auth.userId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final debts = await PBService.getDebts(customerId: auth.userId);
      if (mounted) _debts = debts;
    } catch (_) {
      // Customer view remains calm and keeps the last visible state.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final screens = [
      _CustomerHome(debts: _debts, isLoading: _isLoading, onRefresh: _loadDebts, onOpenWallet: () => setState(() => _currentIndex = 1)),
      _ReceiptWallet(debts: _debts, isLoading: _isLoading, onRefresh: _loadDebts),
      UserProfileScreen(key: const ValueKey('profile'), userId: auth.userId),
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
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _nav(0, Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'قەرزی من'),
                _nav(1, Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'وەصڵەکان'),
                _nav(2, Icons.person_outline, Icons.person_rounded, 'هەژمار'),
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
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: EdgeInsets.symmetric(horizontal: isSelected ? 18 : 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected ? LinearGradient(colors: [AppColors.primary, AppColors.primary.withOpacity(0.72)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isSelected ? activeIcon : icon, color: isSelected ? Colors.white : (isDark ? AppDarkColors.textSecondary : Colors.grey[400])),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

class _CustomerHome extends StatelessWidget {
  final List<RecordModel> debts;
  final bool isLoading;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenWallet;

  const _CustomerHome({required this.debts, required this.isLoading, required this.onRefresh, required this.onOpenWallet});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppDarkColors.card : Colors.white;
    final textColor = isDark ? AppDarkColors.textPrimary : AppColors.textPrimary;
    final subColor = isDark ? AppDarkColors.textSecondary : AppColors.textSecondary;

    final activeDebts = debts.where((d) => d.getStringValue('status') != 'paid' && d.getDoubleValue('remaining') > 0).toList();
    final paidDebts = debts.where((d) => d.getStringValue('status') == 'paid' || d.getDoubleValue('remaining') <= 0).toList();
    final totalDebt = debts.fold<double>(0, (sum, d) => sum + d.getDoubleValue('amount'));
    final totalRemaining = debts.fold<double>(0, (sum, d) => sum + d.getDoubleValue('remaining'));
    final totalPaid = (totalDebt - totalRemaining).clamp(0, double.infinity).toDouble();
    final trustScore = _trustScore(totalDebt, totalRemaining, paidDebts.length, activeDebts.length);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CustomerHero(name: auth.userName.isEmpty ? 'کڕیار' : auth.userName),
          const SizedBox(height: 16),
          if (isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else ...[
            _TrustCard(score: trustScore, remaining: totalRemaining, cardColor: cardColor, textColor: textColor, subColor: subColor),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 1.22,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _MiniStat(title: 'قەرزی ماوە', value: AppHelpers.formatCurrency(totalRemaining), icon: Icons.account_balance_wallet, color: AppColors.danger, cardColor: cardColor, textColor: textColor, subColor: subColor),
                _MiniStat(title: 'پارەی دراو', value: AppHelpers.formatCurrency(totalPaid), icon: Icons.payments, color: AppColors.secondary, cardColor: cardColor, textColor: textColor, subColor: subColor),
                _MiniStat(title: 'قەرزی چالاک', value: activeDebts.length.toString(), icon: Icons.receipt_long, color: AppColors.warning, cardColor: cardColor, textColor: textColor, subColor: subColor),
                _MiniStat(title: 'قەرزی تەواو', value: paidDebts.length.toString(), icon: Icons.verified, color: AppColors.primary, cardColor: cardColor, textColor: textColor, subColor: subColor),
              ],
            ),
            const SizedBox(height: 14),
            _StatementCard(cardColor: cardColor, textColor: textColor, subColor: subColor, totalDebt: totalDebt, totalPaid: totalPaid, totalRemaining: totalRemaining, onOpenWallet: onOpenWallet),
            const SizedBox(height: 16),
            Text('قەرزە چالاکەکان', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (activeDebts.isEmpty)
              _EmptyCustomerCard(cardColor: cardColor, textColor: textColor, subColor: subColor)
            else
              ...activeDebts.map((debt) => _DebtCard(debt: debt, cardColor: cardColor, textColor: textColor, subColor: subColor)),
          ],
        ],
      ),
    );
  }

  int _trustScore(double totalDebt, double totalRemaining, int paidCount, int activeCount) {
    if (totalDebt <= 0) return 100;
    final remainingRatio = (totalRemaining / totalDebt).clamp(0.0, 1.0);
    final paidBoost = (paidCount * 4).clamp(0, 18);
    final activePenalty = (activeCount * 3).clamp(0, 18);
    return (95 - (remainingRatio * 35) + paidBoost - activePenalty).clamp(45, 100).round();
  }
}

class _CustomerHero extends StatelessWidget {
  final String name;

  const _CustomerHero({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.primary, AppColors.primary.withOpacity(0.74)], begin: Alignment.topRight, end: Alignment.bottomLeft),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.22), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('قەرزی من', style: TextStyle(color: Colors.white.withOpacity(0.78), fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Text('کەشف حساب و وەصڵەکانت بە ڕوونی لێرەن', style: TextStyle(color: Colors.white.withOpacity(0.74), fontSize: 12)),
                ],
              ),
            ),
            IconButton(onPressed: () => context.read<ThemeProvider>().toggleTheme(), icon: const Icon(Icons.contrast_rounded, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _TrustCard extends StatelessWidget {
  final int score;
  final double remaining;
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const _TrustCard({required this.score, required this.remaining, required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    final label = score >= 85 ? 'متمانەی تۆ باشە' : score >= 65 ? 'متمانەی تۆ پێویستی بە بەردەوامی هەیە' : 'بە پارەدانەوەی بەشێک، بارەکەت باشتر دەبێت';
    final hint = remaining <= 0 ? 'هیچ قەرزێکی ماوەت نییە ✅' : 'ئەگەر بەشێک لە قەرزەکەت بدەیت، متمانەکەت زیاتر دەبێت.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle),
            child: Center(child: Text('$score', style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 5),
                Text(hint, style: TextStyle(color: subColor, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatementCard extends StatelessWidget {
  final Color cardColor;
  final Color textColor;
  final Color subColor;
  final double totalDebt;
  final double totalPaid;
  final double totalRemaining;
  final VoidCallback onOpenWallet;

  const _StatementCard({required this.cardColor, required this.textColor, required this.subColor, required this.totalDebt, required this.totalPaid, required this.totalRemaining, required this.onOpenWallet});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [const Icon(Icons.summarize_rounded, color: AppColors.primary), const SizedBox(width: 8), Text('کورتەی کەشف حساب', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16))]),
          const SizedBox(height: 10),
          _StatementLine(label: 'کۆی قەرز', value: AppHelpers.formatCurrency(totalDebt), subColor: subColor),
          _StatementLine(label: 'کۆی پارەی دراو', value: AppHelpers.formatCurrency(totalPaid), subColor: subColor),
          _StatementLine(label: 'قەرزی ماوە', value: AppHelpers.formatCurrency(totalRemaining), subColor: subColor),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: onOpenWallet, icon: const Icon(Icons.receipt_long_rounded), label: const Text('بینینی وەصڵەکان')),
        ],
      ),
    );
  }
}

class _StatementLine extends StatelessWidget {
  final String label;
  final String value;
  final Color subColor;

  const _StatementLine({required this.label, required this.value, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: subColor))),
          Text(value, style: TextStyle(color: subColor, fontWeight: FontWeight.bold), textDirection: TextDirection.ltr),
        ],
      ),
    );
  }
}

class _ReceiptWallet extends StatelessWidget {
  final List<RecordModel> debts;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const _ReceiptWallet({required this.debts, required this.isLoading, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppDarkColors.card : Colors.white;
    final textColor = isDark ? AppDarkColors.textPrimary : AppColors.textPrimary;
    final subColor = isDark ? AppDarkColors.textSecondary : AppColors.textSecondary;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SafeArea(
            bottom: false,
            child: Text('جانتای وەصڵەکان', style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          Text('کەشف حساب، قەرزەکان، و پارەدانەوەکانت لێرە بە ڕوونی دەبینیت.', style: TextStyle(color: subColor, height: 1.6)),
          const SizedBox(height: 16),
          if (isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (debts.isEmpty)
            _EmptyCustomerCard(cardColor: cardColor, textColor: textColor, subColor: subColor)
          else
            ...debts.map((debt) => _DebtCard(debt: debt, cardColor: cardColor, textColor: textColor, subColor: subColor)),
        ],
      ),
    );
  }
}

class _DebtCard extends StatelessWidget {
  final RecordModel debt;
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const _DebtCard({required this.debt, required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    final amount = debt.getDoubleValue('amount');
    final remaining = debt.getDoubleValue('remaining');
    final status = debt.getStringValue('status');
    final isPaid = status == 'paid' || remaining <= 0;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => DebtDetailScreen(debtId: debt.id)));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: (isPaid ? AppColors.secondary : AppColors.warning).withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(isPaid ? Icons.verified_rounded : Icons.receipt_long_rounded, color: isPaid ? AppColors.secondary : AppColors.warning),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isPaid ? 'قەرز تەواوە' : 'قەرزی ماوە', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('کۆی قەرز: ${AppHelpers.formatCurrency(amount)}', style: TextStyle(color: subColor, fontSize: 12)),
                ],
              ),
            ),
            Text(AppHelpers.formatCurrency(remaining), style: TextStyle(color: isPaid ? AppColors.secondary : AppColors.danger, fontWeight: FontWeight.bold), textDirection: TextDirection.ltr),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const _MiniStat({required this.title, required this.value, required this.icon, required this.color, required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: color, size: 22),
          ),
          const Spacer(),
          Text(title, style: TextStyle(color: subColor, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 15), textDirection: TextDirection.ltr),
        ],
      ),
    );
  }
}

class _EmptyCustomerCard extends StatelessWidget {
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const _EmptyCustomerCard({required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.secondary, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('هیچ قەرزێکی ماوەت نییە ✅', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('کەشف حسابەکەت پاکە.', style: TextStyle(color: subColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
