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
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            _OwnerHero(onOpenMarkets: onOpenMarkets),
            const SizedBox(height: 22),
            const AppSectionHeader(
              title: 'کۆنترۆڵی مارکێت و پلان',
              subtitle: 'بەشداری، دەسەڵات، سنوور و تایبەتمەندیی هەر مارکێت',
            ),
            const SizedBox(height: 12),
            _OwnerModuleGrid(
              children: [
                _OwnerModuleCard(
                  title: 'مارکێتەکان',
                  subtitle: 'دروستکردن، نوێکردنەوە و بەڕێوەبردنی هەژمار',
                  icon: Icons.storefront_rounded,
                  tint: scheme.primary,
                  onTap: onOpenMarkets,
                ),
                _OwnerModuleCard(
                  title: 'کۆنترۆڵی پلاتفۆرم',
                  subtitle: 'دۆخ، سنوور، lifecycle و پشتیوانی',
                  icon: Icons.admin_panel_settings_rounded,
                  tint: scheme.primary,
                  onTap: () => _open(context, const OwnerPlatformCenterScreen()),
                ),
                _OwnerModuleCard(
                  title: 'پلان و تایبەتمەندی',
                  subtitle: 'Standard / Pro / VIP و override ـی مارکێت',
                  icon: Icons.workspace_premium_rounded,
                  tint: scheme.tertiary,
                  onTap: () =>
                      _open(context, const OwnerEntitlementsCenterScreen()),
                ),
                _OwnerModuleCard(
                  title: '٢٠٠ دەسەڵاتی Owner',
                  subtitle: 'Scope، Risk و دەسەڵات بەپێی مارکێت',
                  icon: Icons.rule_folder_rounded,
                  tint: scheme.tertiary,
                  onTap: () =>
                      _open(context, const OwnerPermissionCenterScreen()),
                ),
                _OwnerModuleCard(
                  title: 'بەشداری و پارەدان',
                  subtitle: 'پلان، بەرواری کۆتایی و مێژووی بەشداری',
                  icon: Icons.credit_card_rounded,
                  tint: const Color(0xFFD28A00),
                  onTap: () =>
                      _open(context, const OwnerSubscriptionCenterScreen()),
                ),
                _OwnerModuleCard(
                  title: 'پشتیوانی',
                  subtitle: 'SLA، داواکاری و وەڵامی تەکنیکی',
                  icon: Icons.support_agent_rounded,
                  tint: scheme.secondary,
                  onTap: () => _open(context, const OwnerSupportCenterScreen()),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const AppSectionHeader(
              title: 'پاراستن و بەردەوامی',
              subtitle: 'دەستگەیشتن، ئامێر، backup و ئامادەیی خزمەتگوزاری',
            ),
            const SizedBox(height: 12),
            _OwnerModuleGrid(
              children: [
                _OwnerModuleCard(
                  title: 'پاراستن',
                  subtitle: 'دانیشتن، قوفڵ و چوونەژوورەوەی گوماناوی',
                  icon: Icons.security_rounded,
                  tint: scheme.error,
                  onTap: () => _open(context, const OwnerSecurityCenterScreen()),
                ),
                _OwnerModuleCard(
                  title: 'هەژمار و ئامێر',
                  subtitle: 'Recovery، device policy و پەسەندکردن',
                  icon: Icons.phonelink_lock_rounded,
                  tint: const Color(0xFF52677E),
                  onTap: () =>
                      _open(context, const OwnerRecoveryDeviceCenterScreen()),
                ),
                _OwnerModuleCard(
                  title: 'پاشەکەوت و Recovery',
                  subtitle: 'Backup health، restore و resilience',
                  icon: Icons.cloud_done_rounded,
                  tint: scheme.secondary,
                  onTap: () =>
                      _open(context, const OwnerBackupResilienceCenterScreen()),
                ),
                _OwnerModuleCard(
                  title: 'تەندروستی سیستەم',
                  subtitle: 'پلاتفۆرم، audit و دۆخی خزمەتگوزاری',
                  icon: Icons.monitor_heart_rounded,
                  tint: const Color(0xFF0B9D72),
                  onTap: () => _open(context, const OwnerHealthCenterScreen()),
                ),
                _OwnerModuleCard(
                  title: 'ئامادەیی مارکێت',
                  subtitle: 'بەشداری، ئامێر، backup و app readiness',
                  icon: Icons.fact_check_rounded,
                  tint: const Color(0xFF3375D6),
                  onTap: () =>
                      _open(context, const OwnerReadinessCenterScreen()),
                ),
                _OwnerModuleCard(
                  title: 'ڕووداوەکان',
                  subtitle: 'Incident، کاریگەری و چارەسەرکردن',
                  icon: Icons.crisis_alert_rounded,
                  tint: scheme.error,
                  onTap: () => _open(context, const OwnerIncidentCenterScreen()),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const AppSectionHeader(
              title: 'ژێرخان و ئۆپەراسیۆن',
              subtitle: 'دۆمەین، automation، queue و کۆنترۆڵی خزمەتگوزاری',
            ),
            const SizedBox(height: 12),
            _OwnerModuleGrid(
              children: [
                _OwnerModuleCard(
                  title: 'ژێرخان',
                  subtitle: 'Queue، worker، ناردن و دۆخی خزمەتگوزاری',
                  icon: Icons.dns_rounded,
                  tint: const Color(0xFF1597A5),
                  onTap: () =>
                      _open(context, const OwnerInfrastructureCenterScreen()),
                ),
                _OwnerModuleCard(
                  title: 'ئۆپەراسیۆن',
                  subtitle: 'Maintenance، status و ئاگادارکردنەوەی گشتی',
                  icon: Icons.settings_input_antenna_rounded,
                  tint: scheme.secondary,
                  onTap: () =>
                      _open(context, const OwnerOperationsCenterScreen()),
                ),
                _OwnerModuleCard(
                  title: 'دۆمەین و HTTPS',
                  subtitle: 'DNS، CNAME و پشکنینی certificate',
                  icon: Icons.language_rounded,
                  tint: const Color(0xFF3B78D8),
                  onTap: () => _open(context, const OwnerDomainCenterScreen()),
                ),
                _OwnerModuleCard(
                  title: 'کۆنترۆڵی وەشان',
                  subtitle: 'Update، minimum version و فایلەکانی دامەزراندن',
                  icon: Icons.system_update_rounded,
                  tint: const Color(0xFF0D9B70),
                  onTap: () => _open(context, const UpdateControlScreen()),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const AppSectionHeader(
              title: 'پالیسی، ڕووکار و دەستگەیشتن',
              subtitle: 'ناسنامەی مارکێت و کۆنترۆڵە تەکنیکییە تایبەتەکان',
            ),
            const SizedBox(height: 12),
            _OwnerModuleGrid(
              children: [
                _OwnerModuleCard(
                  title: 'سیاسەت و پابەندبوون',
                  subtitle: 'Policy، consent و retention ـی داتای تەکنیکی',
                  icon: Icons.policy_rounded,
                  tint: const Color(0xFFD38218),
                  onTap: () =>
                      _open(context, const OwnerPolicyComplianceCenterScreen()),
                ),
                _OwnerModuleCard(
                  title: 'ناسنامە و ڕووکار',
                  subtitle: 'ناو، لۆگۆ و ڕەنگی تایبەتی مارکێت',
                  icon: Icons.palette_rounded,
                  tint: scheme.tertiary,
                  onTap: () => _open(context, const OwnerBrandingCenterScreen()),
                ),
                _OwnerModuleCard(
                  title: 'مۆڵەتی Import',
                  subtitle: 'چالاک/ناچالاککردنی هێنانەژوورەوە بەپێی مارکێت',
                  icon: Icons.move_to_inbox_rounded,
                  tint: scheme.primary,
                  onTap: () => _open(context, const ImportPermissionScreen()),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _PrivacyBoundaryCard(),
          ],
        ),
      ),
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
    final ownerVisual = theme.extension<OwnerVisualExtension>();
    final start = ownerVisual?.heroStart ?? scheme.primary;
    final end = ownerVisual?.heroEnd ?? scheme.primaryContainer;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [start, end],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: theme.brightness == Brightness.light
            ? [
                BoxShadow(
                  color: start.withValues(alpha: 0.22),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: Colors.white,
                  size: 29,
                ),
              ),
              const SizedBox(width: 13),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'کۆنترۆڵی Owner',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'بەڕێوەبردنی پلاتفۆرم، پلان، دەسەڵات و مارکێتەکان لە یەک ناوەند',
                      style: TextStyle(
                        color: Color(0xFFE7ECFF),
                        fontSize: 12.5,
                        height: 1.6,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroPill(icon: Icons.rule_rounded, label: '٢٠٠ دەسەڵات'),
              _HeroPill(icon: Icons.layers_rounded, label: 'پلان + Override'),
              _HeroPill(icon: Icons.lock_outline_rounded, label: 'Privacy Boundary'),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: start,
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: onOpenMarkets,
                  icon: const Icon(Icons.storefront_rounded),
                  label: const Text('مارکێتەکان'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.38),
                    ),
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const OwnerPermissionCenterScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.admin_panel_settings_rounded),
                  label: const Text('دەسەڵاتەکان'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _OwnerModuleGrid extends StatelessWidget {
  const _OwnerModuleGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 10.0;
        final columns = constraints.maxWidth >= 700 ? 3 : 2;
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _OwnerModuleCard extends StatelessWidget {
  const _OwnerModuleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tint,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          height: 150,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, color: tint, size: 22),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                    size: 15,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                      fontSize: 10.5,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyBoundaryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: scheme.primary),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'سنووری تایبەتمەندی',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Owner پلاتفۆرم و هەژمار بەڕێوەدەبات؛ ناوەڕۆکی قەرز، پارەدانەوە، پسوولە و تێبینی تایبەتی مارکێت لەم ناوەندەدا پیشان نادرێت.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.6,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Text(
              'ڕێکخستنەکانی Owner',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 5),
            Text(
              'ڕووکار، وەشان و هەژماری خاوەنی سیستەم',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 22),
            const AppSectionHeader(
              title: 'ڕووکار',
              subtitle: 'دۆخی ڕووناک و تاریک بۆ هەموو ناوەندی Owner',
            ),
            const SizedBox(height: 10),
            AppSurface(
              padding: EdgeInsets.zero,
              child: SwitchListTile.adaptive(
                secondary: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                    color: scheme.primary,
                  ),
                ),
                title: Text(isDark ? 'دۆخی تاریک' : 'دۆخی ڕووناک'),
                subtitle: const Text('ڕەنگی هەموو پەڕەکانی Owner یەکجار بگۆڕە'),
                value: isDark,
                onChanged: (_) => context.read<ThemeProvider>().toggleTheme(),
              ),
            ),
            const SizedBox(height: 20),
            const AppSectionHeader(
              title: 'سیستەم',
              subtitle: 'وەشان و دۆخی بڵاوکردنەوەی ئەپ',
            ),
            const SizedBox(height: 10),
            AppSurface(
              padding: EdgeInsets.zero,
              child: ListTile(
                minTileHeight: 72,
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: scheme.secondary.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.system_update_alt_rounded,
                    color: scheme.secondary,
                  ),
                ),
                title: const Text('ڕێکخستنی نوێکردنەوە'),
                subtitle: const Text('Minimum version، forced update و فایل'),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const UpdateControlScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const AppSectionHeader(
              title: 'هەژمار',
              subtitle: 'دانیشتنی ئێستا و چوونەدەرەوە',
            ),
            const SizedBox(height: 10),
            AppSurface(
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(Icons.shield_rounded, color: scheme.primary),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'System Owner',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'دەسەڵاتی پلاتفۆرم بە privacy boundary',
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.error,
                side: BorderSide(color: scheme.error.withValues(alpha: 0.35)),
                minimumSize: const Size(double.infinity, 52),
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
