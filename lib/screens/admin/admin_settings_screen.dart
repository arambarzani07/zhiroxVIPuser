import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/providers/theme_provider.dart';
import 'package:zhirox/screens/admin/admin_notifications_screen.dart';
import 'package:zhirox/screens/admin/collection_center_screen.dart';
import 'package:zhirox/screens/admin/debt_restore_screen.dart';
import 'package:zhirox/screens/admin/daftar_sync_dashboard_screen.dart';
import 'package:zhirox/screens/admin/governance_center_screen.dart';
import 'package:zhirox/screens/admin/intelligence_center_screen.dart';
import 'package:zhirox/screens/admin/legacy_import_screen.dart';
import 'package:zhirox/screens/admin/pending_requests_screen.dart';
import 'package:zhirox/screens/admin/receipt_settings_screen.dart';
import 'package:zhirox/screens/admin/subscription_payment_screen.dart';
import 'package:zhirox/screens/shared/user_list_screen.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class AdminSettingsScreen extends StatelessWidget {
  const AdminSettingsScreen({
    super.key,
    required this.pendingCount,
    required this.onOpenReports,
    required this.onChangePhone,
    required this.onChangePassword,
  });

  final int pendingCount;
  final VoidCallback onOpenReports;
  final VoidCallback onChangePhone;
  final VoidCallback onChangePassword;

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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              sliver: SliverToBoxAdapter(
                child: _SettingsHeaderCard(
                  marketName: auth.marketName,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              sliver: SliverList.list(
                children: [
                  _SettingsGroup(
                    icon: Icons.space_dashboard_outlined,
                    title: 'بەڕێوەبردنی کاروبار',
                    subtitle: 'کارمەند، داواکاری، ڕاپۆرت و بەدواداچوون',
                    children: [
                      _SettingsRow(
                        icon: Icons.badge_outlined,
                        title: 'کارمەندان',
                        subtitle: 'هەژمار و دەسەڵاتی کارمەندان',
                        onTap: () => _open(
                          context,
                          UserListScreen(
                            role: 'employee',
                            adminId: auth.userId,
                          ),
                        ),
                      ),
                      _SettingsRow(
                        icon: Icons.pending_actions_outlined,
                        title: 'داواکارییەکان',
                        subtitle: 'پەسەندکردن یان ڕەتکردنەوەی کڕیار',
                        badge: pendingCount,
                        onTap: () => _open(
                          context,
                          PendingRequestsScreen(adminId: auth.userId),
                        ),
                      ),
                      _SettingsRow(
                        icon: Icons.summarize_outlined,
                        title: 'کەشفی حیساب و ڕاپۆرت',
                        subtitle: 'ڕاپۆرتی قەرز و پارەدانەوە',
                        onTap: onOpenReports,
                      ),
                      _SettingsRow(
                        icon: Icons.auto_graph_rounded,
                        title: 'ناوەندی زیرەکی',
                        subtitle: 'هەڵسەنگاندن و ئاگاداریی دارایی',
                        onTap: () => _open(
                          context,
                          const Scaffold(
                            body: SafeArea(child: IntelligenceCenterScreen()),
                          ),
                        ),
                      ),
                      _SettingsRow(
                        icon: Icons.event_repeat_rounded,
                        title: 'بەدواداچوونی قەرز',
                        subtitle: 'Aging، پێشەنگی کڕیار و پلانی بەدواداچوون',
                        onTap: () =>
                            _open(context, const CollectionCenterScreen()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SettingsGroup(
                    icon: Icons.hub_outlined,
                    title: 'پەیوەندی و داتا',
                    subtitle: 'ئاگادارکردنەوە، Sync و گواستنەوەی داتا',
                    children: [
                      _SettingsRow(
                        icon: Icons.notifications_active_outlined,
                        title: 'ناوەندی ئاگادارکردنەوەکان',
                        subtitle: 'Push، مێژوو و ناردنی گشتی',
                        onTap: () =>
                            _open(context, const AdminNotificationsScreen()),
                      ),
                      _SettingsRow(
                        icon: Icons.sync_rounded,
                        title: 'پەیوەندی Daftar',
                        subtitle: 'دۆخی Sync، مێژوو و هەڵەکان',
                        onTap: () =>
                            _open(context, const DaftarSyncDashboardScreen()),
                      ),
                      _SettingsRow(
                        icon: Icons.move_to_inbox_rounded,
                        title: 'گواستنەوەی داتای کۆن',
                        subtitle: 'Import ـی کڕیار، قەرز و پارەدانەوە',
                        onTap: () =>
                            _open(context, const LegacyImportScreen()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SettingsGroup(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'دارایی و بەڵگەنامە',
                    subtitle: 'بەشداری، پسووڵە و داتای سڕاوە',
                    children: [
                      _SettingsRow(
                        icon: Icons.credit_card_rounded,
                        title: 'بەشداری و FIB',
                        subtitle: 'پلان و پارەدانی بەشداری',
                        onTap: () =>
                            _open(context, const SubscriptionPaymentScreen()),
                      ),
                      _SettingsRow(
                        icon: Icons.receipt_long_outlined,
                        title: 'ڕێکخستنی پسووڵە',
                        subtitle: 'ناونیشان، ژمارە و شێوازی پسووڵە',
                        onTap: () =>
                            _open(context, const ReceiptSettingsScreen()),
                      ),
                      _SettingsRow(
                        icon: Icons.restore_from_trash_outlined,
                        title: 'قەرزە سڕاوەکان',
                        subtitle: 'بینین و گەڕاندنەوەی قەرز',
                        onTap: () =>
                            _open(context, const DebtRestoreScreen()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SettingsGroup(
                    icon: Icons.verified_user_outlined,
                    title: 'پاراستن و کۆنترۆڵ',
                    subtitle: 'دەسەڵات، Audit و Backup',
                    children: [
                      _SettingsRow(
                        icon: Icons.admin_panel_settings_outlined,
                        title: 'دەسەڵات، Audit و Backup',
                        subtitle: 'کۆنترۆڵی ورد و گەڕاندنەوەی داتا',
                        onTap: () =>
                            _open(context, const GovernanceCenterScreen()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SettingsGroup(
                    icon: Icons.tune_rounded,
                    title: 'هەژمار و ڕووکار',
                    subtitle: 'ڕووکار و زانیارییەکانی هەژمار',
                    children: [
                      _SettingsRow(
                        icon: isDark
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                        title: isDark ? 'دۆخی ڕووناک' : 'دۆخی تاریک',
                        subtitle: 'گۆڕینی ڕەنگی ڕووکار',
                        onTap: () =>
                            context.read<ThemeProvider>().toggleTheme(),
                      ),
                      _SettingsRow(
                        icon: Icons.phone_android_rounded,
                        title: 'ژمارەی مۆبایل',
                        subtitle:
                            (auth.user?.getStringValue('phone') ?? '').isEmpty
                            ? 'ژمارە مۆبایلێکی نوێ دابنێ'
                            : auth.user!.getStringValue('phone'),
                        onTap: onChangePhone,
                      ),
                      _SettingsRow(
                        icon: Icons.lock_outline_rounded,
                        title: 'وشەی نهێنی',
                        subtitle: 'گۆڕینی وشەی نهێنیی هەژمار',
                        onTap: onChangePassword,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  AppSurface(
                    padding: EdgeInsets.zero,
                    child: _SettingsRow(
                      icon: Icons.logout_rounded,
                      title: 'چوونەدەرەوە',
                      subtitle: 'بە سەلامەتی لە هەژمارەکەت دەرچۆ',
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

class _SettingsHeaderCard extends StatelessWidget {
  const _SettingsHeaderCard({required this.marketName});

  final String marketName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayName =
        marketName.trim().isEmpty ? 'بەڕێوەبردنی سیستەم' : marketName.trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.storefront_rounded,
              color: scheme.primary,
              size: 25,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ڕێکخستنەکان',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              'بەڕێوەبەر',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 2, bottom: 9),
          child: Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        AppSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1)
                  Divider(
                    height: 1,
                    indent: 68,
                    endIndent: 14,
                    color: scheme.outlineVariant.withValues(alpha: 0.55),
                  ),
              ],
            ],
          ),
        ),
      ],
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
    final scheme = Theme.of(context).colorScheme;
    final color = destructive ? AppColors.danger : scheme.primary;

    return ListTile(
      minTileHeight: 66,
      contentPadding: const EdgeInsetsDirectional.fromSTEB(12, 2, 10, 2),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(13),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 21, color: color),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w750,
              color: destructive ? AppColors.danger : null,
            ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ),
      trailing: badge > 0
          ? Container(
              constraints: const BoxConstraints(minWidth: 30),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                badge > 99 ? '99+' : badge.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          : Icon(
              Icons.chevron_left_rounded,
              color: destructive
                  ? AppColors.danger.withValues(alpha: 0.75)
                  : scheme.onSurfaceVariant.withValues(alpha: 0.65),
            ),
      onTap: onTap,
    );
  }
}
