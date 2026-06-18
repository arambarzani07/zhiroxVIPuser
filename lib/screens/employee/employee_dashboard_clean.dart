import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/shared/debt_list_screen_clean.dart';
import 'package:zhirox/screens/shared/user_list_screen_clean.dart';
import 'package:zhirox/screens/shared/user_profile_screen_clean.dart';
import 'package:zhirox/utils/constants.dart';

class EmployeeDashboardClean extends StatefulWidget {
  const EmployeeDashboardClean({super.key});

  @override
  State<EmployeeDashboardClean> createState() => _EmployeeDashboardCleanState();
}

class _EmployeeDashboardCleanState extends State<EmployeeDashboardClean> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().refreshUser();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final screens = [
      _EmployeeHome(onOpenTab: (index) => setState(() => _currentIndex = index)),
      UserListScreenClean(
        key: const ValueKey('customers_clean'),
        role: 'customer',
        adminId: auth.adminId,
      ),
      const DebtListScreen(key: ValueKey('debts_clean')),
      UserProfileScreenClean(key: const ValueKey('profile_clean'), userId: auth.userId),
    ];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
      body: AnimatedSwitcher(duration: const Duration(milliseconds: 280), child: screens[_currentIndex]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? AppDarkColors.card : Colors.white,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
          boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 24, offset: const Offset(0, -6))],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _nav(0, Icons.work_outline_rounded, Icons.work_rounded, 'سەرەکی'),
                _nav(1, Icons.people_outline, Icons.people_rounded, 'کڕیار'),
                _nav(2, Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'قەرز'),
                _nav(3, Icons.person_outline, Icons.person_rounded, 'هەژمار'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _nav(int index, IconData icon, IconData activeIcon, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: EdgeInsets.symmetric(horizontal: selected ? 14 : 10, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected ? LinearGradient(colors: [AppColors.primary, AppColors.primary.withOpacity(0.72)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? activeIcon : icon, color: selected ? Colors.white : (isDark ? AppDarkColors.textSecondary : Colors.grey[400])),
            if (selected) ...[
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmployeeHome extends StatelessWidget {
  final ValueChanged<int> onOpenTab;

  const _EmployeeHome({required this.onOpenTab});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppDarkColors.card : Colors.white;
    final textColor = isDark ? AppDarkColors.textPrimary : AppColors.textPrimary;
    final subColor = isDark ? AppDarkColors.textSecondary : AppColors.textSecondary;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _EmployeeHero(auth: auth),
          const SizedBox(height: 16),
          _TodayWorkCard(cardColor: cardColor, textColor: textColor, subColor: subColor, onOpenCustomers: () => onOpenTab(1), onOpenDebts: () => onOpenTab(2)),
          const SizedBox(height: 16),
          Text('کاری خێرا', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 1.16,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: [
              _ActionCard(title: 'گەڕانی کڕیار', subtitle: 'قەرز، پارە، کەشف حساب', icon: Icons.search_rounded, cardColor: cardColor, textColor: textColor, subColor: subColor, onTap: () => onOpenTab(1)),
              _ActionCard(title: 'قەرز پێدان', subtitle: 'پێش قەرز پێدان، قەرزی ماوە ببینە', icon: Icons.add_card_rounded, cardColor: cardColor, textColor: textColor, subColor: subColor, onTap: () => onOpenTab(2)),
              _ActionCard(title: 'پارە وەرگرتنەوە', subtitle: 'بڕ بنووسە و قەرزی ماوە نوێ بکە', icon: Icons.payments_rounded, cardColor: cardColor, textColor: textColor, subColor: subColor, onTap: () => onOpenTab(2)),
              _ActionCard(title: 'وەعد و کەشف حساب', subtitle: 'ڕێککەوتن و کەشف حسابی کڕیار', icon: Icons.event_available_rounded, cardColor: cardColor, textColor: textColor, subColor: subColor, onTap: () => onOpenTab(1)),
            ],
          ),
          const SizedBox(height: 16),
          _PermissionSummaryCard(auth: auth, cardColor: cardColor, textColor: textColor, subColor: subColor, onOpenProfile: () => onOpenTab(3)),
          const SizedBox(height: 16),
          _SafeWorkCard(cardColor: cardColor, subColor: subColor),
        ],
      ),
    );
  }
}

class _EmployeeHero extends StatelessWidget {
  final AuthProvider auth;

  const _EmployeeHero({required this.auth});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.primary, AppColors.primary.withOpacity(0.75)], begin: Alignment.topRight, end: Alignment.bottomLeft),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.22), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.badge_rounded, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('میزکاری کارمەند', style: TextStyle(color: Colors.white.withOpacity(0.80), fontSize: 14)),
                const SizedBox(height: 4),
                Text(auth.userName.isEmpty ? 'کارمەند' : auth.userName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('کاری قەرز و پارە بە شێوەی پارێزراو', style: TextStyle(color: Colors.white.withOpacity(0.74), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayWorkCard extends StatelessWidget {
  final Color cardColor;
  final Color textColor;
  final Color subColor;
  final VoidCallback onOpenCustomers;
  final VoidCallback onOpenDebts;

  const _TodayWorkCard({required this.cardColor, required this.textColor, required this.subColor, required this.onOpenCustomers, required this.onOpenDebts});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [const Icon(Icons.task_alt_rounded, color: AppColors.secondary), const SizedBox(width: 8), Text('کاری ئەمڕۆت', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16))]),
          const SizedBox(height: 10),
          Text('سەرەتا کڕیار بدۆزەوە، قەرزی ماوە ببینە، پاشان قەرز پێدان یان پارە وەرگرتنەوە ئەنجام بدە.', style: TextStyle(color: subColor, height: 1.6)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: FilledButton.icon(onPressed: onOpenCustomers, icon: const Icon(Icons.people_rounded), label: const Text('کڕیار'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: onOpenDebts, icon: const Icon(Icons.receipt_long_rounded), label: const Text('قەرز'))),
            ],
          ),
        ],
      ),
    );
  }
}

class _PermissionSummaryCard extends StatelessWidget {
  final AuthProvider auth;
  final Color cardColor;
  final Color textColor;
  final Color subColor;
  final VoidCallback onOpenProfile;

  const _PermissionSummaryCard({required this.auth, required this.cardColor, required this.textColor, required this.subColor, required this.onOpenProfile});

  @override
  Widget build(BuildContext context) {
    final allowedItems = [
      _PermissionItem('قەرز پێدان', auth.canGiveDebt),
      _PermissionItem('پارە وەرگرتنەوە', auth.canReceivePayment),
      _PermissionItem('کڕیار زیادکردن', auth.canAddCustomers),
      _PermissionItem('کەشف حساب', auth.canCreateStatement),
      _PermissionItem('ناردنی ئاگاداری', auth.canSendNotifications),
    ];
    final protectedItems = [
      _PermissionItem('بینینی ڕاپۆرت', auth.canViewReports),
      _PermissionItem('دەستکاری قەرز', auth.canEditDebts),
      _PermissionItem('سنووری قەرز', auth.canSetDebtLimit),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [const Icon(Icons.verified_user_rounded, color: AppColors.primary), const SizedBox(width: 8), Text('دەسەڵاتەکانی کارمەند', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16))]),
          const SizedBox(height: 8),
          Text('ئەمە ئەو کارانەیە کە دەتوانیت بکەیت، یان پێویستیان بە ڕێگەپێدانی بەڕێوەبەر هەیە.', style: TextStyle(color: subColor, height: 1.55, fontSize: 12)),
          const SizedBox(height: 12),
          Text('کاری ڕۆژانە', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: allowedItems.map((item) => _PermissionChip(item: item)).toList()),
          const SizedBox(height: 12),
          Text('کرداری گرنگ', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: protectedItems.map((item) => _PermissionChip(item: item)).toList()),
          const SizedBox(height: 12),
          TextButton.icon(onPressed: onOpenProfile, icon: const Icon(Icons.person_rounded), label: const Text('بینینی هەژماری من')),
        ],
      ),
    );
  }
}

class _PermissionItem {
  final String label;
  final bool allowed;

  const _PermissionItem(this.label, this.allowed);
}

class _PermissionChip extends StatelessWidget {
  final _PermissionItem item;

  const _PermissionChip({required this.item});

  @override
  Widget build(BuildContext context) {
    final color = item.allowed ? AppColors.secondary : AppColors.warning;
    final text = item.allowed ? item.label : '${item.label} — بە ڕێگەپێدان';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withOpacity(0.22))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.allowed ? Icons.check_circle_rounded : Icons.lock_clock_rounded, color: color, size: 16),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }
}

class _SafeWorkCard extends StatelessWidget {
  final Color cardColor;
  final Color subColor;

  const _SafeWorkCard({required this.cardColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          const Icon(Icons.shield_rounded, color: AppColors.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text('ئەگەر کردارێک پێویستی بە ڕێگەپێدانی بەڕێوەبەر هەبوو، بە شێوەی پارێزراو دەچێتە پێش و بەڕێوەبەر بڕیار دەدات.', style: TextStyle(color: subColor, height: 1.6)),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color cardColor;
  final Color textColor;
  final Color subColor;
  final VoidCallback onTap;

  const _ActionCard({required this.title, required this.subtitle, required this.icon, required this.cardColor, required this.textColor, required this.subColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: AppColors.primary),
            ),
            const Spacer(),
            Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: subColor, fontSize: 11, height: 1.35), maxLines: 2),
          ],
        ),
      ),
    );
  }
}
