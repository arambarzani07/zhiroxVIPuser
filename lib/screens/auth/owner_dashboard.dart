import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/providers/theme_provider.dart';
import 'package:zhirox/screens/auth/admin_management_screen.dart';
import 'package:zhirox/screens/auth/import_permission_screen.dart';
import 'package:zhirox/screens/auth/owner_backup_resilience_center_screen.dart';
import 'package:zhirox/screens/auth/owner_branding_center_screen.dart';
import 'package:zhirox/screens/auth/owner_domain_center_screen.dart';
import 'package:zhirox/screens/auth/owner_entitlements_center_screen.dart';
import 'package:zhirox/screens/auth/owner_health_center_screen.dart';
import 'package:zhirox/screens/auth/owner_incident_center_screen.dart';
import 'package:zhirox/screens/auth/owner_infrastructure_center_screen.dart';
import 'package:zhirox/screens/auth/owner_operations_center_screen.dart';
import 'package:zhirox/screens/auth/owner_telegram_bot_settings_screen.dart';
import 'package:zhirox/screens/auth/owner_permission_center_screen.dart';
import 'package:zhirox/screens/auth/owner_platform_center_screen.dart';
import 'package:zhirox/screens/auth/owner_policy_compliance_center_screen.dart';
import 'package:zhirox/screens/auth/owner_readiness_center_screen.dart';
import 'package:zhirox/screens/auth/owner_recovery_device_center_screen.dart';
import 'package:zhirox/screens/auth/owner_security_center_screen.dart';
import 'package:zhirox/screens/auth/owner_subscription_center_screen.dart';
import 'package:zhirox/screens/auth/owner_support_center_screen.dart';
import 'package:zhirox/screens/auth/update_control_screen.dart';
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
    final scheme = Theme.of(context).colorScheme;
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
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _select,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard_rounded),
              label: 'سەرەکی',
            ),
            NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront_rounded),
              label: 'مارکێتەکان',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune_rounded),
              label: 'ڕێکخستن',
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnerHome extends StatelessWidget {
  const _OwnerHome({required this.onOpenMarkets});

  final VoidCallback onOpenMarkets;

  void _open(BuildContext context, Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
          children: [
            const _OwnerTopHeader(),
            const SizedBox(height: 16),
            _OwnerHero(onOpenMarkets: onOpenMarkets),
            const SizedBox(height: 16),
            _QuickActions(
              onMarkets: onOpenMarkets,
              onPlatform: () =>
                  _open(context, const OwnerPlatformCenterScreen()),
              onPermissions: () =>
                  _open(context, const OwnerPermissionCenterScreen()),
              onSecurity: () =>
                  _open(context, const OwnerSecurityCenterScreen()),
            ),
            const SizedBox(height: 24),
            _OwnerGroup(
              title: 'مارکێت و پلان',
              subtitle: 'بەڕێوەبردنی هەژمار، پلان و دەسەڵات',
              accent: scheme.primary,
              children: [
                _OwnerRow(
                  title: 'کۆنترۆڵی پلاتفۆرم',
                  subtitle: 'Lifecycle، سنوور، پشتیوانی و دۆخی هەژمار',
                  icon: Icons.admin_panel_settings_rounded,
                  tint: scheme.primary,
                  onTap: () =>
                      _open(context, const OwnerPlatformCenterScreen()),
                ),
                _OwnerRow(
                  title: 'پلان و تایبەتمەندی',
                  subtitle: 'Standard / Pro / VIP و override ـی هەر مارکێت',
                  icon: Icons.workspace_premium_rounded,
                  tint: scheme.tertiary,
                  onTap: () =>
                      _open(context, const OwnerEntitlementsCenterScreen()),
                ),
                _OwnerRow(
                  title: 'دەسەڵاتەکانی Owner',
                  subtitle: 'Scope، Risk و پالیسی دەستگەیشتن',
                  icon: Icons.rule_folder_rounded,
                  tint: scheme.tertiary,
                  badge: '٢٠٠',
                  onTap: () =>
                      _open(context, const OwnerPermissionCenterScreen()),
                ),
                _OwnerRow(
                  title: 'بەشداری و پارەدان',
                  subtitle: 'پلان، بەرواری کۆتایی و مێژووی بەشداری',
                  icon: Icons.credit_card_rounded,
                  tint: const Color(0xFFC47C00),
                  onTap: () =>
                      _open(context, const OwnerSubscriptionCenterScreen()),
                ),
                _OwnerRow(
                  title: 'پشتیوانی',
                  subtitle: 'داواکاری، SLA و وەڵامی تەکنیکی',
                  icon: Icons.support_agent_rounded,
                  tint: scheme.secondary,
                  onTap: () => _open(context, const OwnerSupportCenterScreen()),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _OwnerGroup(
              title: 'پاراستن و بەردەوامی',
              subtitle: 'پاراستنی هەژمار، ئامێر و دۆخی خزمەتگوزاری',
              accent: scheme.error,
              children: [
                _OwnerRow(
                  title: 'ناوەندی پاراستن',
                  subtitle: 'دانیشتن، قوفڵ و چوونەژوورەوەی گوماناوی',
                  icon: Icons.shield_rounded,
                  tint: scheme.error,
                  onTap: () =>
                      _open(context, const OwnerSecurityCenterScreen()),
                ),
                _OwnerRow(
                  title: 'هەژمار و ئامێر',
                  subtitle: 'Recovery، device policy و پەسەندکردنی ئامێر',
                  icon: Icons.phonelink_lock_rounded,
                  tint: const Color(0xFF52677E),
                  onTap: () =>
                      _open(context, const OwnerRecoveryDeviceCenterScreen()),
                ),
                _OwnerRow(
                  title: 'پاشەکەوت و Recovery',
                  subtitle: 'Backup health، restore و resilience',
                  icon: Icons.cloud_done_rounded,
                  tint: scheme.secondary,
                  onTap: () =>
                      _open(context, const OwnerBackupResilienceCenterScreen()),
                ),
                _OwnerRow(
                  title: 'تەندروستی سیستەم',
                  subtitle: 'Platform health، audit و دۆخی خزمەتگوزاری',
                  icon: Icons.monitor_heart_rounded,
                  tint: const Color(0xFF0B9270),
                  onTap: () =>
                      _open(context, const OwnerHealthCenterScreen()),
                ),
                _OwnerRow(
                  title: 'ئامادەیی مارکێتەکان',
                  subtitle: 'بەشداری، ئامێر، backup و app readiness',
                  icon: Icons.fact_check_rounded,
                  tint: const Color(0xFF3573C8),
                  onTap: () =>
                      _open(context, const OwnerReadinessCenterScreen()),
                ),
                _OwnerRow(
                  title: 'ڕووداوەکان',
                  subtitle: 'Incident، کاریگەری و چارەسەرکردن',
                  icon: Icons.crisis_alert_rounded,
                  tint: scheme.error,
                  onTap: () =>
                      _open(context, const OwnerIncidentCenterScreen()),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _OwnerGroup(
              title: 'ژێرخان و ئۆپەراسیۆن',
              subtitle: 'دۆمەین، automation و کۆنترۆڵی خزمەتگوزاری',
              accent: scheme.secondary,
              children: [
                _OwnerRow(
                  title: 'ژێرخان',
                  subtitle: 'Queue، worker، ناردن و تەندروستی خزمەتگوزاری',
                  icon: Icons.dns_rounded,
                  tint: const Color(0xFF168B9A),
                  onTap: () =>
                      _open(context, const OwnerInfrastructureCenterScreen()),
                ),
                _OwnerRow(
                  title: 'ئۆپەراسیۆن',
                  subtitle: 'Maintenance، status و ئاگادارکردنەوەی گشتی',
                  icon: Icons.settings_input_antenna_rounded,
                  tint: scheme.secondary,
                  onTap: () =>
                      _open(context, const OwnerOperationsCenterScreen()),
                ),
                _OwnerRow(
                  title: 'Telegram Bot',
                  subtitle: 'Bot Token، Webhook و دۆخی پەیوەندی',
                  icon: Icons.telegram_rounded,
                  tint: const Color(0xFF2AABEE),
                  onTap: () => _open(
                    context,
                    const OwnerTelegramBotSettingsScreen(),
                  ),
                ),
                _OwnerRow(
                  title: 'دۆمەین و HTTPS',
                  subtitle: 'DNS، CNAME و certificate',
                  icon: Icons.language_rounded,
                  tint: const Color(0xFF3B73C5),
                  onTap: () =>
                      _open(context, const OwnerDomainCenterScreen()),
                ),
                _OwnerRow(
                  title: 'کۆنترۆڵی وەشان',
                  subtitle: 'Minimum version، forced update و فایلەکان',
                  icon: Icons.system_update_rounded,
                  tint: const Color(0xFF0C8F69),
                  onTap: () => _open(context, const UpdateControlScreen()),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _OwnerGroup(
              title: 'پالیسی و ڕووکار',
              subtitle: 'ناسنامە، پابەندبوون و دەستگەیشتنە تایبەتەکان',
              accent: scheme.tertiary,
              children: [
                _OwnerRow(
                  title: 'سیاسەت و پابەندبوون',
                  subtitle: 'Policy، consent و retention ـی داتای تەکنیکی',
                  icon: Icons.policy_rounded,
                  tint: const Color(0xFFC47B17),
                  onTap: () => _open(
                    context,
                    const OwnerPolicyComplianceCenterScreen(),
                  ),
                ),
                _OwnerRow(
                  title: 'ناسنامە و ڕووکار',
                  subtitle: 'ناو، لۆگۆ و ڕەنگی تایبەتی مارکێت',
                  icon: Icons.palette_rounded,
                  tint: scheme.tertiary,
                  onTap: () =>
                      _open(context, const OwnerBrandingCenterScreen()),
                ),
                _OwnerRow(
                  title: 'مۆڵەتی Import',
                  subtitle: 'چالاک/ناچالاککردنی هێنانەژوورەوە بەپێی مارکێت',
                  icon: Icons.move_to_inbox_rounded,
                  tint: scheme.primary,
                  onTap: () =>
                      _open(context, const ImportPermissionScreen()),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const _PrivacyBoundaryCard(),
          ],
        ),
      ),
    );
  }
}

class _OwnerTopHeader extends StatelessWidget {
  const _OwnerTopHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ناوەندی Owner',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'کۆنترۆڵی پلاتفۆرم لە یەک شوێنی ڕێکخراو',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_rounded, size: 15, color: scheme.primary),
              const SizedBox(width: 5),
              Text(
                'System Owner',
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OwnerHero extends StatelessWidget {
  const _OwnerHero({required this.onOpenMarkets});

  final VoidCallback onOpenMarkets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visual = theme.extension<OwnerVisualExtension>();
    final start = visual?.heroStart ?? scheme.primary;
    final end = visual?.heroEnd ?? scheme.primary;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [start, end],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: theme.brightness == Brightness.light
            ? [
                BoxShadow(
                  color: start.withValues(alpha: 0.16),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          Positioned(
            left: -30,
            top: -42,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(19),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                      ),
                      child: const Icon(
                        Icons.shield_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'کۆنترۆڵی سەرەکی',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'مارکێت، پلان، دەسەڵات، پاراستن و ئۆپەراسیۆن لە یەک ناوەند.',
                            style: TextStyle(
                              color: Color(0xFFE8ECFF),
                              fontSize: 11.5,
                              height: 1.55,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: start,
                          minimumSize: const Size(0, 46),
                        ),
                        onPressed: onOpenMarkets,
                        icon: const Icon(Icons.storefront_rounded, size: 19),
                        label: const Text('مارکێتەکان'),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.30),
                          ),
                          minimumSize: const Size(0, 46),
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const OwnerPermissionCenterScreen(),
                          ),
                        ),
                        icon: const Icon(
                          Icons.admin_panel_settings_rounded,
                          size: 19,
                        ),
                        label: const Text('دەسەڵات'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onMarkets,
    required this.onPlatform,
    required this.onPermissions,
    required this.onSecurity,
  });

  final VoidCallback onMarkets;
  final VoidCallback onPlatform;
  final VoidCallback onPermissions;
  final VoidCallback onSecurity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _QuickAction(
            icon: Icons.storefront_rounded,
            label: 'مارکێت',
            tint: scheme.primary,
            onTap: onMarkets,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickAction(
            icon: Icons.dashboard_customize_rounded,
            label: 'پلاتفۆرم',
            tint: scheme.secondary,
            onTap: onPlatform,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickAction(
            icon: Icons.rule_rounded,
            label: 'دەسەڵات',
            tint: scheme.tertiary,
            onTap: onPermissions,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickAction(
            icon: Icons.shield_rounded,
            label: 'پاراستن',
            tint: scheme.error,
            onTap: onSecurity,
          ),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: tint, size: 20),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnerGroup extends StatelessWidget {
  const _OwnerGroup({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.children,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppSurface(
      padding: const EdgeInsets.fromLTRB(14, 15, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 38,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.45,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(
                height: 1,
                indent: 54,
                color: scheme.outlineVariant.withValues(alpha: 0.8),
              ),
          ],
        ],
      ),
    );
  }
}

class _OwnerRow extends StatelessWidget {
  const _OwnerRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tint,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      minTileHeight: 66,
      onTap: onTap,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: tint, size: 21),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                badge!,
                style: TextStyle(
                  color: tint,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontSize: 10.3,
          ),
        ),
      ),
      trailing: Icon(
        Icons.chevron_left_rounded,
        size: 20,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
      ),
    );
  }
}

class _PrivacyBoundaryCard extends StatelessWidget {
  const _PrivacyBoundaryCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.verified_user_outlined,
              color: scheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Privacy Boundary',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Owner پلاتفۆرم و هەژمار بەڕێوەدەبات؛ ناوەڕۆکی قەرز، پارەدانەوە، پسوولە و تێبینی تایبەتی مارکێت لێرە پیشان نادرێت.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.55,
                    fontSize: 10.5,
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

class _OwnerSettings extends StatelessWidget {
  const _OwnerSettings();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
          children: [
            Text(
              'ڕێکخستن',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'ڕووکار، وەشان و هەژماری Owner',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            AppSurface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    secondary: _SettingsIcon(
                      icon: isDark
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      tint: scheme.primary,
                    ),
                    title: Text(isDark ? 'دۆخی تاریک' : 'دۆخی ڕووناک'),
                    subtitle: const Text('ڕووکار بۆ هەموو پەڕەکانی Owner'),
                    value: isDark,
                    onChanged: (_) =>
                        context.read<ThemeProvider>().toggleTheme(),
                  ),
                  Divider(height: 1, color: scheme.outlineVariant),
                  ListTile(
                    minTileHeight: 72,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    leading: _SettingsIcon(
                      icon: Icons.system_update_alt_rounded,
                      tint: scheme.secondary,
                    ),
                    title: const Text('کۆنترۆڵی نوێکردنەوە'),
                    subtitle: const Text('Minimum version، forced update و فایل'),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const UpdateControlScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            AppSurface(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  _SettingsIcon(
                    icon: Icons.shield_rounded,
                    tint: scheme.primary,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'System Owner',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'دەسەڵاتی پلاتفۆرم بە Privacy Boundary',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.verified_rounded,
                    color: scheme.primary,
                    size: 20,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.error,
                side: BorderSide(color: scheme.error.withValues(alpha: 0.28)),
                minimumSize: const Size(double.infinity, 50),
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

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon({required this.icon, required this.tint});

  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: tint, size: 21),
    );
  }
}
