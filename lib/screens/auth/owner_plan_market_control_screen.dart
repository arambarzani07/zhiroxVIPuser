import 'package:flutter/material.dart';
import 'package:zhirox/utils/latest_request.dart';
import 'package:zhirox/services/owner_permission_service.dart';
import 'package:zhirox/services/owner_plan_control_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerPlanMarketControlScreen extends StatefulWidget {
  const OwnerPlanMarketControlScreen({super.key});

  @override
  State<OwnerPlanMarketControlScreen> createState() =>
      _OwnerPlanMarketControlScreenState();
}

class _OwnerPlanMarketControlScreenState
    extends State<OwnerPlanMarketControlScreen> {
  OwnerPlanLimits? _planLimits;
  List<OwnerMarketSummary> _markets = const [];
  OwnerTenantPlanControl? _tenant;
  String? _selectedMarketId;
  final LatestRequest _tenantRequest = LatestRequest();
  bool _loading = true;
  bool _tenantLoading = false;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
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

  String _displayValue(OwnerPlanLimitDefinition definition, int value) {
    if (value == 0 && definition.zeroMeansUnlimited) return 'بێ سنوور';
    return '$value';
  }

  String _displayTenantValue(OwnerTenantLimitEntry entry, int value) {
    if (value == 0 && entry.zeroMeansUnlimited) return 'بێ سنوور';
    return '$value';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        OwnerPlanControlService.fetchPlanLimits(),
        OwnerPermissionService.fetchMarkets(),
      ]);
      final planLimits = results[0] as OwnerPlanLimits;
      final markets = results[1] as List<OwnerMarketSummary>;
      if (!mounted) return;
      setState(() {
        _planLimits = planLimits;
        _markets = markets;
        _selectedMarketId = markets.isEmpty ? null : markets.first.id;
        _loading = false;
      });
      if (markets.isNotEmpty) await _loadTenant(markets.first.id);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _loadTenant(String adminId) async {
    if (!mounted) return;
    final request = _tenantRequest.begin();
    setState(() {
      _tenantLoading = true;
      _error = null;
      _selectedMarketId = adminId;
      _tenant = null;
    });
    try {
      final tenant = await OwnerPlanControlService.fetchTenantLimits(adminId);
      if (!mounted || !_tenantRequest.isCurrent(request)) return;
      setState(() {
        _tenant = tenant;
        _tenantLoading = false;
      });
    } catch (error) {
      if (!mounted || !_tenantRequest.isCurrent(request)) return;
      setState(() {
        _tenantLoading = false;
        _error = error;
      });
    }
  }

  Future<void> _editPlan(String planKey) async {
    final data = _planLimits;
    if (data == null || _saving) return;
    final current = data.plans[planKey] ?? const <String, int>{};
    final controllers = <String, TextEditingController>{
      for (final item in data.catalog)
        item.key: TextEditingController(text: '${current[item.key] ?? 0}'),
    };

    final values = await showDialog<Map<String, int>>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text('سنوورەکانی پلانی ${_planLabel(planKey)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '٠ واتە بێ سنوور. ئەم نرخانە بنەمای هەموو مارکێتەکانی ئەم پلانەن، '
              'مەگەر Owner بۆ مارکێتێک override ـی تایبەت دابنێت.',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 14),
            for (final item in data.catalog) ...[
              TextField(
                controller: controllers[item.key],
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: item.label,
                  helperText: '${item.description} • max ${item.maxValue}',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('پاشگەزبوونەوە'),
          ),
          FilledButton(
            onPressed: () {
              final out = <String, int>{};
              for (final item in data.catalog) {
                final value = int.tryParse(controllers[item.key]!.text.trim());
                if (value == null ||
                    value < item.minValue ||
                    value > item.maxValue) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${item.label}: نرخەکە دروست نییە')),
                  );
                  return;
                }
                out[item.key] = value;
              }
              Navigator.pop(context, out);
            },
            child: const Text('پاشەکەوت'),
          ),
        ],
      ),
    );

    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (values == null || !mounted) return;

    setState(() => _saving = true);
    try {
      for (final entry in values.entries) {
        if ((current[entry.key] ?? 0) == entry.value) continue;
        await OwnerPlanControlService.setPlanLimit(
          planKey: planKey,
          limitKey: entry.key,
          value: entry.value,
        );
      }
      final refreshed = await OwnerPlanControlService.fetchPlanLimits();
      final selected = _selectedMarketId;
      OwnerTenantPlanControl? tenant;
      if (selected != null) {
        tenant = await OwnerPlanControlService.fetchTenantLimits(selected);
      }
      if (!mounted) return;
      setState(() {
        _planLimits = refreshed;
        if (tenant != null) _tenant = tenant;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('پلانی ${_planLabel(planKey)} نوێ کرایەوە')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  Future<void> _changeTenantPlan(String planKey) async {
    final adminId = _selectedMarketId;
    final tenant = _tenant;
    if (adminId == null || tenant == null || planKey == tenant.planKey || _saving) {
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('گۆڕینی پلانی مارکێت'),
        content: Text(
          'مارکێتەکە دەگوازرێتە پلانی ${_planLabel(planKey)}. '
          'Feature ـەکان و سنوورە بنەڕەتییەکان لە پلانی نوێ وەردەگیرێن؛ '
          'override ـە تایبەتەکانی Owner هەر دەمێنن.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('نەخێر'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('بەڵێ، بگۆڕە'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await OwnerPlanControlService.setTenantPlan(
        adminId: adminId,
        planKey: planKey,
      );
      final refreshed = await OwnerPlanControlService.fetchTenantLimits(adminId);
      if (!mounted) return;
      setState(() {
        _tenant = refreshed;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('پلانی مارکێت بوو بە ${_planLabel(planKey)}')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  Future<void> _editTenantLimit(OwnerTenantLimitEntry entry) async {
    final adminId = _selectedMarketId;
    if (adminId == null || _saving) return;
    var inherit = entry.overrideValue == null;
    final controller = TextEditingController(
      text: '${entry.overrideValue ?? entry.effectiveValue}',
    );

    final result = await showDialog<int?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(entry.label),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.description),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: inherit,
                onChanged: (value) => setDialogState(() => inherit = value),
                title: const Text('وەرگرتن لە پلان'),
                subtitle: Text('نرخی پلان: ${_displayTenantValue(entry, entry.planValue)}'),
              ),
              if (!inherit)
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'سنووری تایبەت',
                    helperText: '٠ = بێ سنوور • max ${entry.maxValue}',
                    border: const OutlineInputBorder(),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('پاشگەزبوونەوە'),
            ),
            FilledButton(
              onPressed: () {
                if (inherit) {
                  Navigator.pop(context, -1);
                  return;
                }
                final value = int.tryParse(controller.text.trim());
                if (value == null || value < 0 || value > entry.maxValue) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('نرخەکە دروست نییە')),
                  );
                  return;
                }
                Navigator.pop(context, value);
              },
              child: const Text('پاشەکەوت'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await OwnerPlanControlService.setTenantLimitOverride(
        adminId: adminId,
        limitKey: entry.key,
        value: result == -1 ? null : result,
      );
      final refreshed = await OwnerPlanControlService.fetchTenantLimits(adminId);
      if (!mounted) return;
      setState(() {
        _tenant = refreshed;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  Future<void> _resetOverrides() async {
    final adminId = _selectedMarketId;
    final tenant = _tenant;
    if (adminId == null || tenant == null || _saving) return;
    final overrides = tenant.limits.where((item) => item.overrideValue != null).toList();
    if (overrides.isEmpty) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('گەڕاندنەوە بۆ پلان'),
        content: Text('${overrides.length} override لادەبرێت و سنوورەکان لە پلان وەردەگیرێن.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('نەخێر')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('بەڵێ')),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => _saving = true);
    try {
      for (final item in overrides) {
        await OwnerPlanControlService.setTenantLimitOverride(
          adminId: adminId,
          limitKey: item.key,
          value: null,
        );
      }
      final refreshed = await OwnerPlanControlService.fetchTenantLimits(adminId);
      if (!mounted) return;
      setState(() {
        _tenant = refreshed;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final planLimits = _planLimits;
    return Scaffold(
      appBar: AppBar(
        title: const Text('پلان و سنووری مارکێتەکان'),
        actions: [
          IconButton(
            onPressed: _saving ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'نوێکردنەوە',
          ),
        ],
      ),
      body: _loading
          ? const OwnerStatePanel.loading()
          : planLimits == null
              ? OwnerStatePanel.error(
                  message: _error?.toString() ?? 'زانیاری بەردەست نییە',
                  onAction: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    children: [
                      const AppSurface(
                        child: Text(
                          'هەر پلانێک Feature ـەکانی خۆی + سنووری سەرچاوەکانی خۆی هەیە. '
                          'Owner دەتوانێت بۆ هەر مارکێت پلان هەڵبژێرێت و لە دەرەوەی پلان '
                          'سنوور یان Feature ـی تایبەت override بکات.',
                          style: TextStyle(height: 1.6),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const AppSectionHeader(
                        title: 'سنوورە بنەڕەتییەکانی پلانەکان',
                        subtitle: 'کارمەند • کڕیار • ئامێر',
                      ),
                      const SizedBox(height: 10),
                      for (final planKey in const ['standard', 'pro', 'vip']) ...[
                        _planCard(context, planLimits, planKey),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 10),
                      const AppSectionHeader(
                        title: 'کۆنترۆڵی هەر مارکێت',
                        subtitle: 'پلان + override ـی تایبەت',
                      ),
                      const SizedBox(height: 10),
                      if (_markets.isEmpty)
                        const AppSurface(child: Text('هیچ مارکێتێک بەردەست نییە'))
                      else ...[
                        DropdownButtonFormField<String>(
                          initialValue: _selectedMarketId,
                          decoration: const InputDecoration(
                            labelText: 'مارکێت هەڵبژێرە',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.storefront_rounded),
                          ),
                          items: _markets
                              .map((market) => DropdownMenuItem(
                                    value: market.id,
                                    child: Text('${market.displayName} — ${market.adminName}'),
                                  ))
                              .toList(growable: false),
                          onChanged: _saving
                              ? null
                              : (value) {
                                  if (value != null) _loadTenant(value);
                                },
                        ),
                        const SizedBox(height: 12),
                        if (_tenantLoading)
                          const Center(child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ))
                        else if (_tenant != null)
                          _tenantCard(context, _tenant!),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        AppSurface(
                          child: Text(
                            _error.toString(),
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _planCard(BuildContext context, OwnerPlanLimits data, String planKey) {
    final values = data.plans[planKey] ?? const <String, int>{};
    final color = _planColor(planKey);
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(Icons.layers_rounded, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'پلانی ${_planLabel(planKey)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                ),
              ),
              OutlinedButton(
                onPressed: _saving ? null : () => _editPlan(planKey),
                child: const Text('دەستکاری سنوور'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final item in data.catalog)
                _InfoChip(
                  icon: _limitIcon(item.key),
                  label: '${item.label}: ${_displayValue(item, values[item.key] ?? 0)}',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tenantCard(BuildContext context, OwnerTenantPlanControl tenant) {
    final hasOverrides = tenant.limits.any((item) => item.overrideValue != null);
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: tenant.planKey,
            decoration: const InputDecoration(
              labelText: 'پلانی مارکێت',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.layers_rounded),
            ),
            items: const [
              DropdownMenuItem(value: 'standard', child: Text('ئاسایی')),
              DropdownMenuItem(value: 'pro', child: Text('پێشکەوتوو')),
              DropdownMenuItem(value: 'vip', child: Text('تایبەت')),
            ],
            onChanged: _saving
                ? null
                : (value) {
                    if (value != null) _changeTenantPlan(value);
                  },
          ),
          const SizedBox(height: 8),
          Text(
            'Feature ـەکانی مارکێت و سنوورە بنەڕەتییەکان لەم پلانەوە وەردەگیرێن.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          for (final item in tenant.limits) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: AppColors.primarySoft,
                child: Icon(_limitIcon(item.key), color: AppColors.primary),
              ),
              title: Text(item.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                item.source == 'override'
                    ? 'Override ـی Owner • نرخی پلان ${_displayTenantValue(item, item.planValue)}'
                    : 'لە پلانی ${_planLabel(tenant.planKey)}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _displayTenantValue(item, item.effectiveValue),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _saving ? null : () => _editTenantLimit(item),
                    icon: const Icon(Icons.tune_rounded),
                    tooltip: 'دەستکاری تایبەت',
                  ),
                ],
              ),
            ),
            if (item != tenant.limits.last) const Divider(height: 1),
          ],
          if (hasOverrides) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _resetOverrides,
                icon: const Icon(Icons.settings_backup_restore_rounded),
                label: const Text('هەموو سنوورەکان بگەڕێنەوە بۆ پلان'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _limitIcon(String key) => switch (key) {
        'staff_limit' => Icons.groups_rounded,
        'customer_limit' => Icons.people_alt_rounded,
        'device_limit' => Icons.devices_rounded,
        _ => Icons.speed_rounded,
      };
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

