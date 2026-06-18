import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/shared/debt_list_screen_clean.dart';
import 'package:zhirox/screens/shared/user_list_screen.dart';
import 'package:zhirox/screens/shared/user_profile_screen.dart';
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
      UserListScreen(
        key: const ValueKey('customers'),
        role: 'customer',
        adminId: auth.adminId,
      ),
      const DebtListScreen(key: ValueKey('debts_clean')),
      UserProfileScreen(key: const ValueKey('profile'), userId: auth.userId),
    ];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        child: screens[_currentIndex],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? AppDarkColors.card : Colors.white,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
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
          gradient: selected
              ? LinearGradient(
                  colors: [AppColors.primary, AppColors.primary.withOpacity(0.72)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
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
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primary.withOpacity(0.75)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.22),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(18)),
                  child: const Icon(Icons.badge_rounded, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('میزکاری کارمەند', style: TextStyle(color: Colors.white.withOpacity(0.78), fontSize: 14)),
                      const SizedBox(height: 4),
                      Text(auth.userName.isEmpty ? 'کارمەند' : auth.userName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('کاری خێرا', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 1.2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: [
              _ActionCard(title: 'کڕیارەکان', subtitle: 'گەڕان و پڕۆفایلی کڕیار', icon: Icons.people_rounded, cardColor: cardColor, textColor: textColor, subColor: subColor, onTap: () => onOpenTab(1)),
              _ActionCard(title: 'قەرزەکان', subtitle: 'قەرز پێدان و پارە وەرگرتنەوە', icon: Icons.receipt_long_rounded, cardColor: cardColor, textColor: textColor, subColor: subColor, onTap: () => onOpenTab(2)),
              _ActionCard(title: 'وەعدی پارەدانەوە', subtitle: 'ڕێککەوتنی کڕیار تۆمار بکە', icon: Icons.event_available_rounded, cardColor: cardColor, textColor: textColor, subColor: subColor, onTap: () => onOpenTab(1)),
              _ActionCard(title: 'هەژماری من', subtitle: 'زانیاری و دەسەڵاتەکانم', icon: Icons.person_rounded, cardColor: cardColor, textColor: textColor, subColor: subColor, onTap: () => onOpenTab(3)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
            child: Row(
              children: [
                const Icon(Icons.shield_rounded, color: AppColors.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('کارە گرنگەکان بە شێوەی پارێزراو دەچنە پێش و ئەگەر پێویست بوو ڕێگەپێدانی بەڕێوەبەر دەوێت.', style: TextStyle(color: subColor, height: 1.6)),
                ),
              ],
            ),
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
            Text(subtitle, style: TextStyle(color: subColor, fontSize: 11), maxLines: 2),
          ],
        ),
      ),
    );
  }
}
