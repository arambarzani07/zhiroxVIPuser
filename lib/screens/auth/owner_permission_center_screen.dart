import 'package:flutter/material.dart';
import 'package:zhirox/services/owner_permission_service.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerPermissionCenterScreen extends StatefulWidget {
  const OwnerPermissionCenterScreen({super.key});

  @override
  State<OwnerPermissionCenterScreen> createState() =>
      _OwnerPermissionCenterScreenState();
}

class _OwnerPermissionCenterScreenState
    extends State<OwnerPermissionCenterScreen> {
  Future<OwnerPermissionCatalog>? _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = OwnerPermissionService.fetchCatalog();
    });
  }

  Future<void> _refresh() async {
    final future = OwnerPermissionService.fetchCatalog();
    setState(() {
      _future = future;
    });
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ناوەندی دەسەڵاتەکانی Owner'),
      ),
      body: FutureBuilder<OwnerPermissionCatalog>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorState(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final catalog = snapshot.data;
          if (catalog == null) {
            return _ErrorState(
              message: 'زانیاری دەسەڵاتەکان بەردەست نییە',
              onRetry: _reload,
            );
          }

          final filtered = catalog.permissions.where((permission) {
            final query = _query.trim().toLowerCase();
            if (query.isEmpty) return true;
            return permission.label.toLowerCase().contains(query) ||
                permission.key.toLowerCase().contains(query) ||
                permission.groupLabel.toLowerCase().contains(query);
          }).toList(growable: false);

          final groups = <String, List<OwnerPermissionCatalogEntry>>{};
          for (final permission in filtered) {
            groups
                .putIfAbsent(permission.groupLabel, () => [])
                .add(permission);
          }

          final riskCounts = <int, int>{1: 0, 2: 0, 3: 0, 4: 0};
          for (final permission in catalog.permissions) {
            riskCounts[permission.riskLevel] =
                (riskCounts[permission.riskLevel] ?? 0) + 1;
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                AppSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: AppColors.primarySoft,
                            child: Icon(
                              Icons.admin_panel_settings_rounded,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${catalog.count} دەسەڵاتی Owner',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${groups.length} گرووپ • catalog ـی live لە backend',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'ئەم دەسەڵاتانە تایبەتن بە کۆنترۆڵی پلاتفۆرم، مارکێت و هەژماری بەڕێوەبەر؛ '
                        'دەستگەیشتنی ڕاستەوخۆ بە قەرز، پارەدانەوە، پسوولە و تێبینی تایبەتی کڕیار لێرە نییە.',
                        style: TextStyle(height: 1.55),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _RiskSummary(level: 1, count: riskCounts[1] ?? 0),
                    _RiskSummary(level: 2, count: riskCounts[2] ?? 0),
                    _RiskSummary(level: 3, count: riskCounts[3] ?? 0),
                    _RiskSummary(level: 4, count: riskCounts[4] ?? 0),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'گەڕان بە ناو، گرووپ یان permission key',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 16),
                if (filtered.isEmpty)
                  const AppSurface(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('هیچ دەسەڵاتێک نەدۆزرایەوە'),
                      ),
                    ),
                  )
                else
                  ...groups.entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PermissionGroup(
                        title: entry.key,
                        permissions: entry.value,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PermissionGroup extends StatelessWidget {
  const _PermissionGroup({
    required this.title,
    required this.permissions,
  });

  final String title;
  final List<OwnerPermissionCatalogEntry> permissions;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text('${permissions.length} دەسەڵات'),
        children: [
          for (var index = 0; index < permissions.length; index++) ...[
            _PermissionTile(permission: permissions[index]),
            if (index != permissions.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({required this.permission});

  final OwnerPermissionCatalogEntry permission;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: _RiskBadge(level: permission.riskLevel),
      title: Text(
        permission.label,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              permission.key,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final scope in permission.scopes)
                  _TinyChip(label: _scopeLabel(scope)),
                if (permission.requiresReason)
                  const _TinyChip(label: 'هۆکار پێویستە'),
                if (permission.requiresReauth)
                  const _TinyChip(label: 'Re-auth'),
                if (permission.requiresTypedConfirmation)
                  const _TinyChip(label: 'پشتڕاستکردنەوەی نووسراو'),
                if (permission.requiresTwoPersonApproval)
                  const _TinyChip(label: 'دوو-کەس پەسەند'),
              ],
            ),
          ],
        ),
      ),
      trailing: permission.scopes.contains('platform')
          ? Icon(
              permission.allowedPlatform
                  ? Icons.verified_user_rounded
                  : Icons.lock_outline_rounded,
              color: permission.allowedPlatform
                  ? Colors.green
                  : Theme.of(context).colorScheme.error,
            )
          : null,
    );
  }

  static String _scopeLabel(String scope) {
    switch (scope) {
      case 'platform':
        return 'پلاتفۆرم';
      case 'market':
        return 'مارکێت';
      case 'admin':
        return 'بەڕێوەبەر';
      default:
        return scope;
    }
  }
}

class _TinyChip extends StatelessWidget {
  const _TinyChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _RiskBadge extends StatelessWidget {
  const _RiskBadge({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final color = _riskColor(level, context);
    return CircleAvatar(
      radius: 18,
      backgroundColor: color.withValues(alpha: 0.12),
      child: Text(
        '$level',
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _RiskSummary extends StatelessWidget {
  const _RiskSummary({required this.level, required this.count});

  final int level;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = _riskColor(level, context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: 0.10),
      ),
      child: Text(
        'Risk $level • $count',
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

Color _riskColor(int level, BuildContext context) {
  switch (level) {
    case 1:
      return Colors.green;
    case 2:
      return Colors.blue;
    case 3:
      return Colors.orange;
    case 4:
      return Theme.of(context).colorScheme.error;
    default:
      return Theme.of(context).colorScheme.onSurfaceVariant;
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: Theme.of(context).colorScheme.error,
              size: 42,
            ),
            const SizedBox(height: 12),
            const Text(
              'بارکردنی دەسەڵاتەکان سەرکەوتوو نەبوو',
              style: TextStyle(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('دووبارە هەوڵدان'),
            ),
          ],
        ),
      ),
    );
  }
}
