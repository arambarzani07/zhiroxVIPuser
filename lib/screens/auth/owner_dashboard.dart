import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/providers/theme_provider.dart';
import 'package:zhirox/screens/auth/admin_management_screen.dart';
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
              'کۆنترۆڵی مارکێتەکان و وەشانی ئەپ لە یەک شوێن',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),
            AppSurface(
              color: AppColors.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_rounded, color: Colors.white, size: 32),
                  const SizedBox(height: 18),
                  Text(
                    'System Owner',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'دەسەڵاتی سەرەکی بۆ بەشداریکردن، مارکێت و بڵاوکردنەوەی وەشان.',
                    style: TextStyle(color: Colors.white70, height: 1.6),
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
                      child: Icon(Icons.storefront_rounded,
                          color: AppColors.primary),
                    ),
                    title: const Text('بەڕێوەبردنی مارکێتەکان'),
                    subtitle: const Text('زیادکردن و نوێکردنەوەی بەشداریکردن'),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: onOpenMarkets,
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
