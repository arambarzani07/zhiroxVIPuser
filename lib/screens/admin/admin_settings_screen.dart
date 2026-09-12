import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/providers/theme_provider.dart';
import 'package:zhirox/screens/admin/debt_restore_screen.dart';
import 'package:zhirox/screens/admin/governance_center_screen.dart';
import 'package:zhirox/screens/admin/intelligence_center_screen.dart';
import 'package:zhirox/screens/admin/pending_requests_screen.dart';
import 'package:zhirox/screens/admin/receipt_settings_screen.dart';
import 'package:zhirox/screens/admin/subscription_payment_screen.dart';
import 'package:zhirox/screens/shared/user_list_screen.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class AdminSettingsScreen extends StatelessWidget {
  const AdminSettingsScreen({super.key, required this.pendingCount});
  final int pendingCount;

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              sliver: SliverToBoxAdapter(
                child: Row(children: [
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ڕێکخستنەکان', style: Theme.of(context)
                          .textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          )),
                      const SizedBox(height: 4),
                      Text(
                        auth.marketName.isEmpty ? 'بەڕێوەبردنی سیستەم' : auth.marketName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.primarySoft,
                    child: const Icon(Icons.storefront_rounded, color: AppColors.primary),
                  ),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList.list(children: [
                const AppSectionHeader(
                  title: 'بەڕێوەبردنی ڕۆژانە',
                  subtitle: 'کارمەند، داواکاری و ڕاپۆرت',
                ),
                const SizedBox(height: 10),
                AppSurface(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    _SettingsRow(
                      icon: Icons.badge_outlined,
                      title: 'کارمەندان',
                      subtitle: 'هەژمار و دەسەڵاتی کارمەندان',
                      onTap: () => _open(context, UserListScreen(
                        role: 'employee',
                        adminId: auth.userId,
                      )),
                    ),
                    const Divider(height: 1),
                    _SettingsRow(
                      icon: Icons.pending_actions_outlined,
                      title: 'داواکارییەکان',
                      subtitle: 'پەسەندکردن یان ڕەتکردنەوەی کڕیار',
                      badge: pendingCount,
                      onTap: () => _open(context, PendingRequestsScreen(
                        adminId: auth.userId,
                      )),
                    ),
                    const Divider(height: 1),
                    _SettingsRow(
                      icon: Icons.auto_graph_rounded,
                      title: 'ناوەندی زیرەکی',
                      subtitle: 'هەڵسەنگاندن و ئاگاداریی دارایی',
                      onTap: () => _open(
                        context,
                        const Scaffold(body: SafeArea(child: IntelligenceCenterScreen())),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 22),
                const AppSectionHeader(
                  title: 'دارایی و بەڵگەنامە',
                  subtitle: 'بەشداری، پسووڵە و داتای سڕاوە',
                ),
                const SizedBox(height: 10),
                AppSurface(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    _SettingsRow(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'بەشداری و FIB',
                      subtitle: 'پلان و پارەدانی بەشداری',
                      onTap: () => _open(
                        context,
                        const SubscriptionPaymentScreen(),
                      ),
                    ),
                    const Divider(height: 1),
                    _SettingsRow(
                      icon: Icons.receipt_long_outlined,
                      title: 'ڕێکخستنی پسووڵە',
                      subtitle: 'ناونیشان، ژمارە و شێوازی پسووڵە',
                      onTap: () => _open(
                        context,
                        const ReceiptSettingsScreen(),
                      ),
                    ),
                    const Divider(height: 1),
                    _SettingsRow(
                      icon: Icons.restore_from_trash_outlined,
                      title: 'قەرزە سڕاوەکان',
                      subtitle: 'بینین و گەڕاندنەوەی قەرز',
                      onTap: () => _open(
                        context,
                        const DebtRestoreScreen(),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 22),
                const AppSectionHeader(
                  title: 'پاراستن و کۆنترۆڵ',
                  subtitle: 'Audit، Backup و دەسەڵات',
                ),
                const SizedBox(height: 10),
                AppSurface(
                  padding: EdgeInsets.zero,
                  child: _SettingsRow(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'دەسەڵات، Audit و Backup',
                    subtitle: 'کۆنترۆڵی ورد و گەڕاندنەوەی داتا',
                    onTap: () => _open(
                      context,
                      const GovernanceCenterScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const AppSectionHeader(title: 'ئەپ و هەژمار'),
                const SizedBox(height: 10),
                AppSurface(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    _SettingsRow(
                      icon: isDark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      title: isDark ? 'دۆخی ڕووناک' : 'دۆخی تاریک',
                      subtitle: 'گۆڕینی ڕەنگی ڕووکار',
                      onTap: () => context.read<ThemeProvider>().toggleTheme(),
                    ),
                    const Divider(height: 1),
                    _SettingsRow(
                      icon: Icons.logout_rounded,
                      title: 'چوونەدەرەوە',
                      subtitle: 'دەرچوون لە هەژمار',
                      destructive: true,
                      onTap: () async {
                        final ok = await AppHelpers.showConfirmDialog(
                          context,
                          title: 'چوونەدەرەوە',
                          message: 'دڵنیایت لە چوونەدەرەوە؟',
                        );
                        if (ok && context.mounted) auth.logout();
                      },
                    ),
                  ]),
                ),
                const SizedBox(height: 28),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge = 0,
    this.destructive = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int badge;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.danger : AppColors.primary;
    return ListTile(
      minTileHeight: 68,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.10),
        foregroundColor: color,
        child: Icon(icon, size: 20),
      ),
      title: Text(title, style: TextStyle(
        fontWeight: FontWeight.w700,
        color: destructive ? AppColors.danger : null,
      )),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: badge > 0
          ? Badge(label: Text(badge > 99 ? '99+' : badge.toString()))
          : const Icon(Icons.chevron_left_rounded),
      onTap: onTap,
    );
  }
}
