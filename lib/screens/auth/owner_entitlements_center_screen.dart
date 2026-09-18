import 'package:flutter/material.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerEntitlementsCenterScreen extends StatefulWidget {
  const OwnerEntitlementsCenterScreen({super.key});

  @override
  State<OwnerEntitlementsCenterScreen> createState() =>
      _OwnerEntitlementsCenterScreenState();
}

class _OwnerEntitlementsCenterScreenState
    extends State<OwnerEntitlementsCenterScreen> {
  Map<String, dynamic> _overview = const {};
  List<Map<String, dynamic>> _features = const [];
  Map<String, dynamic> _plans = const {};
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  int _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? 0}') ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        PBService.getOwnerEntitlementsOverview(),
        PBService.getOwnerEntitlementsPage(page: 1, perPage: 100),
      ]);
      final page = results[1];

      final features = <Map<String, dynamic>>[];
      final rawFeatures = page['features'];
      if (rawFeatures is List) {
        for (final item in rawFeatures) {
          if (item is Map) features.add(Map<String, dynamic>.from(item));
        }
      }

      final items = <Map<String, dynamic>>[];
      final rawItems = page['items'];
      if (rawItems is List) {
        for (final item in rawItems) {
          if (item is Map) items.add(Map<String, dynamic>.from(item));
        }
      }

      if (!mounted) return;
      setState(() {
        _overview = results[0];
        _features = features;
        _plans = page['plans'] is Map
            ? Map<String, dynamic>.from(page['plans'] as Map)
            : const {};
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppHelpers.backendErrorMessage(
          error,
          fallback: 'نەتوانرا دەسەڵاتی تایبەتمەندییەکان بهێنرێن.',
        );
      });
    }
  }

  String _planLabel(String key) => switch (key) {
        'vip' => 'تایبەت',
        'pro' => 'پێشکەوتوو',
        _ => 'ئاسایی',
      };

  Color _planColor(String key) => switch (key) {
        'vip' => Colors.deepPurple,
        'pro' => Colors.indigo,
        _ => AppColors.primary,
      };

  Future<void> _editPlan(String planKey) async {
    final raw = _plans[planKey];
    final current = <String, bool>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        current['${entry.key}'] = entry.value == true;
      }
    }
    for (final feature in _features) {
      final key = '${feature['feature_key'] ?? ''}';
      current.putIfAbsent(key, () => false);
    }

    final draft = Map<String, bool>.from(current);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          scrollable: true,
          title: Text('پلانی تایبەتمەندی — ${_planLabel(planKey)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ئەم گۆڕانکارییە بۆ هەموو مارکێتەکانی ئەم پلانی تایبەتمەندی ـە '
                'کاریگەری هەیە، مەگەر دەستکاری تایبەت ـی تایبەتیان هەبێت.',
              ),
              const SizedBox(height: 12),
              ..._features.map((feature) {
                final key = '${feature['feature_key'] ?? ''}';
                return SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: draft[key] == true,
                  onChanged: (value) =>
                      setDialogState(() => draft[key] = value),
                  title: Text('${feature['display_name'] ?? key}'),
                  subtitle: Text('${feature['description'] ?? ''}'),
                );
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('پاشگەزبوونەوە'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('پاشەکەوت'),
            ),
          ],
        ),
      ),
    );

    if (accepted != true) return;

    try {
      for (final entry in draft.entries) {
        if (current[entry.key] == entry.value) continue;
        await PBService.setOwnerPlanEntitlement(
          planKey: planKey,
          featureKey: entry.key,
          enabled: entry.value,
        );
      }
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        'پلانی تایبەتمەندی ـی ${_planLabel(planKey)} نوێ کرایەوە.',
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          error,
          fallback: 'نوێکردنەوەی پلانی تایبەتمەندی سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _editTenant(Map<String, dynamic> item) async {
    var featurePlan = (item['feature_plan'] ?? 'standard').toString();
    final entitlements = <String, Map<String, dynamic>>{};
    final rawEntitlements = item['entitlements'];
    if (rawEntitlements is List) {
      for (final row in rawEntitlements) {
        if (row is Map) {
          final mapped = Map<String, dynamic>.from(row);
          final key = '${mapped['feature_key'] ?? ''}';
          if (key.isNotEmpty) entitlements[key] = mapped;
        }
      }
    }

    final draft = <String, String>{};
    for (final feature in _features) {
      final key = '${feature['feature_key'] ?? ''}';
      final row = entitlements[key];
      final source = '${row?['source'] ?? 'plan'}';
      if (source == 'دەستکاری تایبەت') {
        draft[key] = row?['enabled'] == true ? 'enabled' : 'disabled';
      } else {
        draft[key] = 'inherit';
      }
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          scrollable: true,
          title: Text('${item['market_name'] ?? 'مارکێت'}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: featurePlan,
                decoration: const InputDecoration(
                  labelText: 'پلانی تایبەتمەندی',
                  prefixIcon: Icon(Icons.layers_outlined),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'standard',
                    child: Text('ئاسایی'),
                  ),
                  DropdownMenuItem(value: 'pro', child: Text('پێشکەوتوو')),
                  DropdownMenuItem(value: 'vip', child: Text('تایبەت')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => featurePlan = value);
                  }
                },
              ),
              const SizedBox(height: 14),
              ..._features.map((feature) {
                final key = '${feature['feature_key'] ?? ''}';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: DropdownButtonFormField<String>(
                    initialValue: draft[key] ?? 'inherit',
                    decoration: InputDecoration(
                      labelText: '${feature['display_name'] ?? key}',
                      helperText: '${feature['description'] ?? ''}',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'inherit',
                        child: Text('شوێنکەوتنی پلانی تایبەتمەندی'),
                      ),
                      DropdownMenuItem(
                        value: 'enabled',
                        child: Text('دەستکاری تایبەت: چالاک'),
                      ),
                      DropdownMenuItem(
                        value: 'disabled',
                        child: Text('دەستکاری تایبەت: ناچالاک'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => draft[key] = value);
                      }
                    },
                  ),
                );
              }),
              const SizedBox(height: 6),
              const Text(
                'خاوەنی سیستەم تەنها دەسەڵاتی تایبەتمەندی زانیاریی سیستەمی دەگۆڕێت؛ '
                'هیچ ناوەڕۆکی مارکێت لەم بەشەدا نییە.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('پاشگەزبوونەوە'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, {
                'feature_plan': featurePlan,
                'دەستکاری تایبەتs': Map<String, String>.from(draft),
              }),
              child: const Text('پاشەکەوت'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    try {
      final adminId = '${item['id'] ?? ''}';
      final newPlan = '${result['feature_plan'] ?? featurePlan}';
      if (newPlan != (item['feature_plan'] ?? 'standard').toString()) {
        await PBService.setOwnerTenantFeaturePlan(
          adminId: adminId,
          planKey: newPlan,
        );
      }

      final rawOverrides = result['دەستکاری تایبەتs'];
      if (rawOverrides is Map) {
        for (final entry in rawOverrides.entries) {
          final value = '${entry.value}';
          await PBService.setOwnerTenantEntitlement(
            adminId: adminId,
            featureKey: '${entry.key}',
            enabled: switch (value) {
              'enabled' => true,
              'disabled' => false,
              _ => null,
            },
          );
        }
      }

      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'دەسەڵاتی تایبەتمەندی نوێ کرایەوە.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          error,
          fallback: 'نوێکردنەوەی دەسەڵاتی تایبەتمەندی سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('دەسەڵاتی تایبەتمەندییەکان'),
        actions: [
          IconButton(
            tooltip: 'نوێکردنەوە',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_rounded, size: 44),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('دووبارە هەوڵ بدە'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const AppSurface(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              color: AppColors.primary,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'دەسەڵاتی تایبەتمەندی و دەستکاری تایبەت ـەکان تەنها '
                                'زانیاریی پلاتفۆرم ـن. خاوەنی سیستەم ناوەڕۆکی '
                                'مارکێت نابینێت.',
                                style: TextStyle(height: 1.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _metric(
                            context,
                            'تایبەتمەندی',
                            _asInt(_overview['feature_count']).toString(),
                            Icons.widgets_outlined,
                          ),
                          _metric(
                            context,
                            'یاسای پلان',
                            _asInt(_overview['plan_rule_count']).toString(),
                            Icons.rule_folder_outlined,
                          ),
                          _metric(
                            context,
                            'دەستکاری تایبەت',
                            _asInt(_overview['دەستکاری تایبەت_count']).toString(),
                            Icons.tune_outlined,
                          ),
                          _metric(
                            context,
                            'مارکێتی دەستکاری تایبەت',
                            _asInt(_overview['tenants_with_دەستکاری تایبەتs'])
                                .toString(),
                            Icons.storefront_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const AppSectionHeader(
                        title: 'پلانی تایبەتمەندی ـەکان',
                        subtitle: 'ئاسایی / پێشکەوتوو / تایبەت',
                      ),
                      const SizedBox(height: 10),
                      ...['standard', 'pro', 'vip'].map(
                        (planKey) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _planCard(context, planKey),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const AppSectionHeader(
                        title: 'دەسەڵاتی تایبەتمەندی ـی مارکێتەکان',
                        subtitle:
                            'Plan + دەستکاری تایبەت ـی تایبەت بۆ هەر هەژمارێک',
                      ),
                      const SizedBox(height: 10),
                      if (_items.isEmpty)
                        const AppSurface(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(18),
                              child: Text('هیچ هەژماری مارکێت نییە.'),
                            ),
                          ),
                        )
                      else
                        ..._items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _tenantCard(context, item),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _metric(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return SizedBox(
      width: 160,
      child: AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(height: 10),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
              textDirection: TextDirection.ltr,
            ),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _planCard(BuildContext context, String planKey) {
    final raw = _plans[planKey];
    final map = raw is Map ? Map<String, dynamic>.from(raw) : const {};
    final enabled = map.values.where((value) => value == true).length;
    final color = _planColor(planKey);

    return AppSurface(
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.10),
            child: Icon(Icons.layers_rounded, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _planLabel(planKey),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '$enabled / ${_features.length} تایبەتمەندی چالاکە',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => _editPlan(planKey),
            child: const Text('دەستکاری'),
          ),
        ],
      ),
    );
  }

  Widget _tenantCard(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    final plan = (item['feature_plan'] ?? 'standard').toString();
    final rawEntitlements = item['entitlements'];
    var enabledCount = 0;
    if (rawEntitlements is List) {
      enabledCount = rawEntitlements
          .whereType<Map>()
          .where((row) => row['enabled'] == true)
          .length;
    }

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: _planColor(plan).withValues(alpha: 0.10),
                child: Icon(
                  Icons.extension_rounded,
                  color: _planColor(plan),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item['market_name'] ?? 'مارکێت'}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${item['admin_name'] ?? ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Chip(label: Text(_planLabel(plan))),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _mini(
                Icons.check_circle_outline_rounded,
                '$enabledCount/${_features.length} چالاک',
              ),
              _mini(
                Icons.tune_rounded,
                '${_asInt(item['override_count'])} دەستکاری تایبەت',
              ),
              _mini(
                Icons.devices_outlined,
                'ئامێر: ${_asInt(item['device_limit'])}',
              ),
              _mini(
                Icons.groups_outlined,
                'کارمەند: ${_asInt(item['staff_limit'])}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _editTenant(item),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('ڕێکخستنی دەسەڵاتی تایبەتمەندی'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mini(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );
}
