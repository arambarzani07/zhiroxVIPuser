import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/providers/theme_provider.dart';
import 'package:zhirox/screens/shared/user_profile_screen.dart';
import 'package:zhirox/screens/admin/pending_requests_screen.dart';
import 'package:zhirox/screens/admin/admin_notifications_screen.dart';
import 'package:zhirox/screens/admin/debt_restore_screen.dart';
import 'package:zhirox/screens/admin/receipt_settings_screen.dart';
import 'package:zhirox/screens/admin/daftar_sync_dashboard_screen.dart';
import 'package:zhirox/screens/admin/governance_center_screen.dart';
import 'package:zhirox/screens/admin/subscription_payment_screen.dart';
import 'package:zhirox/screens/shared/user_list_screen.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class EmployeeSettingsScreen extends StatelessWidget {
  const EmployeeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('ڕێکخستنەکان', style: Theme.of(context)
                .textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(auth.marketName, style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            if (auth.canManageEmployees ||
                auth.canApproveCustomers ||
                auth.canManageNotifications ||
                auth.canRestoreDebts ||
                auth.canManageReceipts ||
                auth.canManageDaftarSync ||
                auth.canViewAuditLog ||
                auth.canManageBackup ||
                auth.canManageSubscription) ...[
              Text(
                'دەسەڵاتە ڕێگەپێدراوەکان',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              AppSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    if (auth.canManageEmployees)
                      _PermissionLink(
                        icon: Icons.badge_outlined,
                        title: 'بەڕێوەبردنی کارمەندان',
                        subtitle: 'بینین و بەڕێوەبردنی هەژماری کارمەندان',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UserListScreen(
                              role: 'employee',
                              adminId: auth.adminId,
                            ),
                          ),
                        ),
                      ),
                    if (auth.canApproveCustomers)
                      _PermissionLink(
                        icon: Icons.how_to_reg_outlined,
                        title: 'پەسەندکردنی کڕیار',
                        subtitle: 'داواکارییە نوێیەکان پشکنین بکە',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PendingRequestsScreen(adminId: auth.adminId),
                          ),
                        ),
                      ),
                    if (auth.canManageNotifications)
                      _PermissionLink(
                        icon: Icons.notifications_active_outlined,
                        title: 'بەڕێوەبردنی ئاگادارکردنەوە',
                        subtitle: 'مێژوو و ناردنی ئاگادارکردنەوە',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminNotificationsScreen(),
                          ),
                        ),
                      ),
                    if (auth.canRestoreDebts)
                      _PermissionLink(
                        icon: Icons.restore_from_trash_outlined,
                        title: 'گەڕاندنەوەی قەرزی سڕاوە',
                        subtitle: 'قەرزە سڕاوەکان ببینە و بگەڕێنەوە',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DebtRestoreScreen(),
                          ),
                        ),
                      ),
                    if (auth.canManageReceipts)
                      _PermissionLink(
                        icon: Icons.receipt_long_outlined,
                        title: 'بەڕێوەبردنی پسووڵە',
                        subtitle: 'ڕێکخستن و شێوازی پسووڵە',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ReceiptSettingsScreen(),
                          ),
                        ),
                      ),
                    if (auth.canManageDaftarSync)
                      _PermissionLink(
                        icon: Icons.sync_rounded,
                        title: 'Daftar Sync',
                        subtitle: 'دۆخی پەیوەندی و sync بپشکنە',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DaftarSyncDashboardScreen(),
                          ),
                        ),
                      ),
                    if (auth.canViewAuditLog || auth.canManageBackup)
                      _PermissionLink(
                        icon: Icons.admin_panel_settings_outlined,
                        title: 'Audit و Backup',
                        subtitle: 'چاودێری و پاراستنی داتا',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const GovernanceCenterScreen(),
                          ),
                        ),
                      ),
                    if (auth.canManageSubscription)
                      _PermissionLink(
                        icon: Icons.workspace_premium_outlined,
                        title: 'بەشداری',
                        subtitle: 'پلان و پارەدانی بەشداری',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SubscriptionPaymentScreen(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            AppSurface(
              padding: EdgeInsets.zero,
              child: Column(children: [
                ListTile(
                  minTileHeight: 68,
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.primarySoft,
                    child: Icon(Icons.person_outline, color: AppColors.primary),
                  ),
                  title: const Text('پرۆفایل'),
                  subtitle: const Text('زانیاری هەژمار و وشەی نهێنی'),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => UserProfileScreen(userId: auth.userId),
                  )),
                ),
                const Divider(height: 1),
                ListTile(
                  minTileHeight: 68,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primarySoft,
                    child: Icon(isDark ? Icons.light_mode : Icons.dark_mode,
                      color: AppColors.primary),
                  ),
                  title: Text(isDark ? 'دۆخی ڕووناک' : 'دۆخی تاریک'),
                  subtitle: const Text('گۆڕینی ڕەنگی ڕووکار'),
                  trailing: Switch(
                    value: isDark,
                    onChanged: (_) => context.read<ThemeProvider>().toggleTheme(),
                  ),
                  onTap: () => context.read<ThemeProvider>().toggleTheme(),
                ),
                const Divider(height: 1),
                ListTile(
                  minTileHeight: 68,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.danger.withValues(alpha: 0.10),
                    child: const Icon(Icons.logout, color: AppColors.danger),
                  ),
                  title: const Text('چوونەدەرەوە',
                    style: TextStyle(color: AppColors.danger)),
                  subtitle: const Text('دەرچوون لە هەژمار'),
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
          ],
        ),
      ),
    );
  }
}


class _PermissionLink extends StatelessWidget {
  const _PermissionLink({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: 64,
      leading: CircleAvatar(
        backgroundColor: AppColors.primarySoft,
        child: Icon(icon, color: AppColors.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_left_rounded),
      onTap: onTap,
    );
  }
}
