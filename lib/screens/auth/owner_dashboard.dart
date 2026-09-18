import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/providers/theme_provider.dart';
import 'package:zhirox/screens/auth/admin_management_screen.dart';
import 'package:zhirox/screens/auth/import_permission_screen.dart';
import 'package:zhirox/screens/auth/owner_platform_center_screen.dart';
import 'package:zhirox/screens/auth/owner_health_center_screen.dart';
import 'package:zhirox/screens/auth/owner_subscription_center_screen.dart';
import 'package:zhirox/screens/auth/owner_security_center_screen.dart';
import 'package:zhirox/screens/auth/owner_support_center_screen.dart';
import 'package:zhirox/screens/auth/owner_operations_center_screen.dart';
import 'package:zhirox/screens/auth/owner_entitlements_center_screen.dart';
import 'package:zhirox/screens/auth/owner_recovery_device_center_screen.dart';
import 'package:zhirox/screens/auth/owner_backup_resilience_center_screen.dart';
import 'package:zhirox/screens/auth/update_control_screen.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  int _currentIndex = 0;
  final Set<int> _visited = <int>{0};

  void _select(int index) {
    if (_currentIndex == index) return;
    setState(() {
      _currentIndex = index;
      _visited.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _OwnerHome(onOpenMarkets: () => _select(1)),
          _visited.contains(1)
              ? const AdminManagementScreen()
              : const SizedBox.shrink(),
          _visited.contains(2)
              ? const _OwnerSettings()
              : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'داشبۆرد',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront_rounded),
            label: 'مارکێتەکان',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'ڕێکخستن',
          ),
        ],
      ),
    );
  }
}

class _OwnerHome extends StatelessWidget {
  const _OwnerHome({required this.onOpenMarkets});
  final VoidCallback onOpenMarkets;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'بەڕێوەبردنی ژیرۆکس',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'کۆنترۆڵی پلاتفۆرم، بەشداری و وەشان — بەبێ دەستگەیشتن بە ناوەڕۆکی مارکێت',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),
            AppSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_rounded, color: AppColors.primary, size: 32),
                  const SizedBox(height: 18),
                  Text(
                    'System Owner',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'دەسەڵاتی سەرەکی بۆ بەشداریکردن، مارکێت، مۆڵەت و بڵاوکردنەوەی وەشان.',
                    style: TextStyle(color: AppColors.textSecondary, height: 1.6),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const AppSectionHeader(
              title: 'کردارە خێراکان',
              subtitle: 'ئەو کارانەی زۆرتر بەکاردێن',
            ),
            const SizedBox(height: 10),
            AppSurface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    minTileHeight: 72,
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.primarySoft,
                      child: Icon(Icons.admin_panel_settings_outlined,
                          color: AppColors.primary),
                    ),
                    title: const Text('کۆنترۆڵی پلاتفۆرم'),
                    subtitle: const Text('Lifecycle، سنوور، Support و دۆخی هەژمار'),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OwnerPlatformCenterScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    minTileHeight: 72,
                    leading: CircleAvatar(
                      backgroundColor: AppColors.success.withValues(alpha: 0.12),
                      child: const Icon(
                        Icons.monitor_heart_outlined,
                        color: AppColors.success,
                      ),
                    ),
                    title: const Text('تەندروستی و پاراستنی سیستەم'),
                    subtitle: const Text(
                      'Backup، بەشداری، دۆخی پلاتفۆرم و Audit ـی Owner',
                    ),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OwnerHealthCenterScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    minTileHeight: 72,
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.primarySoft,
                      child: Icon(Icons.storefront_rounded,
                          color: AppColors.primary),
                    ),
                    title: const Text('هەژمارەکانی مارکێت'),
                    subtitle: const Text('دروستکردن و نوێکردنەوەی بەشداری؛ بێ business data'),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: onOpenMarkets,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    minTileHeight: 72,
                    leading: CircleAvatar(
                      backgroundColor: Colors.teal.withValues(alpha: 0.10),
                      child: const Icon(
                        Icons.settings_input_antenna_rounded,
                        color: Colors.teal,
                      ),
                    ),
                    title: const Text('Platform Operations'),
                    subtitle: const Text(
                      'Maintenance، system status و announcement',
                    ),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OwnerOperationsCenterScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    minTileHeight: 72,
                    leading: CircleAvatar(
                      backgroundColor: Colors.deepPurple.withValues(alpha: 0.10),
                      child: const Icon(
                        Icons.tune_rounded,
                        color: Colors.deepPurple,
                      ),
                    ),
                    title: const Text('Feature Entitlements'),
                    subtitle: const Text(
                      'Standard / Pro / VIP و override ـی هەر مارکێت',
                    ),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OwnerEntitlementsCenterScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    minTileHeight: 72,
                    leading: CircleAvatar(
                      backgroundColor: Colors.indigo.withValues(alpha: 0.10),
                      child: const Icon(
                        Icons.support_agent_rounded,
                        color: Colors.indigo,
                      ),
                    ),
                    title: const Text('Support Center'),
                    subtitle: const Text(
                      'Ticket، SLA و وەڵامدانەوەی تەکنیکی',
                    ),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OwnerSupportCenterScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    minTileHeight: 72,
                    leading: CircleAvatar(
                      backgroundColor: Colors.blueGrey.withValues(alpha: 0.10),
                      child: const Icon(
                        Icons.phonelink_lock_rounded,
                        color: Colors.blueGrey,
                      ),
                    ),
                    title: const Text('Recovery & Device Authorization'),
                    subtitle: const Text(
                      'Account Recovery، Device Policy و Approve/Revoke',
                    ),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const OwnerRecoveryDeviceCenterScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    minTileHeight: 72,
                    leading: CircleAvatar(
                      backgroundColor: Colors.teal.withValues(alpha: 0.10),
                      child: const Icon(
                        Icons.cloud_done_outlined,
                        color: Colors.teal,
                      ),
                    ),
                    title: const Text('Backup & Resilience'),
                    subtitle: const Text(
                      'Freshness، verification و Backup monitoring policy',
                    ),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const OwnerBackupResilienceCenterScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    minTileHeight: 72,
                    leading: CircleAvatar(
                      backgroundColor: Colors.red.withValues(alpha: 0.10),
                      child: const Icon(
                        Icons.security_rounded,
                        color: Colors.red,
                      ),
                    ),
                    title: const Text('ناوەندی پاراستن'),
                    subtitle: const Text(
                      'Session، access، lock و suspicious-login metadata',
                    ),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OwnerSecurityCenterScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    minTileHeight: 72,
                    leading: CircleAvatar(
                      backgroundColor: Colors.amber.withValues(alpha: 0.14),
                      child: const Icon(
                        Icons.workspace_premium_outlined,
                        color: Colors.amber,
                      ),
                    ),
                    title: const Text('ناوەندی بەشداری'),
                    subtitle: const Text(
                      'Plan، expiry و billing metadata ـی مارکێتەکان',
                    ),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OwnerSubscriptionCenterScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    minTileHeight: 72,
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.10),
                      child: const Icon(Icons.move_to_inbox_rounded,
                          color: AppColors.primary),
                    ),
                    title: const Text('مۆڵەتی Import'),
                    subtitle: const Text('کردنەوە یان داخستنی Import بۆ هەر مارکێت'),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ImportPermissionScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    minTileHeight: 72,
                    leading: CircleAvatar(
                      backgroundColor:
                          AppColors.success.withValues(alpha: 0.12),
                      child: const Icon(Icons.system_update_rounded,
                          color: AppColors.success),
                    ),
                    title: const Text('کۆنترۆڵی وەشان'),
                    subtitle: const Text('IPA و زانیاری نوێکردنەوە'),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const UpdateControlScreen(),
                      ),
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

class _OwnerSettings extends StatelessWidget {
  const _OwnerSettings();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'ڕێکخستنەکان',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 20),
            AppSurface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.dark_mode_outlined),
                    title: const Text('دۆخی تاریک'),
                    subtitle: const Text('ڕەنگی ئەپ بەپێی پێویست بگۆڕە'),
                    value: isDark,
                    onChanged: (_) =>
                        context.read<ThemeProvider>().toggleTheme(),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    minTileHeight: 68,
                    leading: const Icon(Icons.system_update_alt_rounded),
                    title: const Text('ڕێکخستنی نوێکردنەوە'),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const UpdateControlScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () async {
                final confirmed = await AppHelpers.showConfirmDialog(
                  context,
                  title: 'چوونەدەرەوە',
                  message: 'دڵنیایت دەتەوێت لە هەژمارەکەت بچیتە دەرەوە؟',
                );
                if (confirmed && context.mounted) {
                  await context.read<AuthProvider>().logout();
                }
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('چوونەدەرەوە'),
            ),
          ],
        ),
      ),
    );
  }
}
