import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerPlatformCenterScreen extends StatefulWidget {
  const OwnerPlatformCenterScreen({super.key});

  @override
  State<OwnerPlatformCenterScreen> createState() =>
      _OwnerPlatformCenterScreenState();
}

class _OwnerPlatformCenterScreenState
    extends State<OwnerPlatformCenterScreen> {
  Map<String, dynamic> _overview = const {};
  List<Map<String, dynamic>> _tenants = const [];
  bool _loading = true;
  String? _error;

  int _asInt(dynamic value) =>
      value is int ? value : int.tryParse('${value ?? 0}') ?? 0;

  String _planLabel(String value) => switch (value) {
        'monthly' => 'مانگانە',
        'quarterly' => '٣ مانگ',
        'semiannual' => '٦ مانگ',
        'annual' => 'ساڵانە',
        _ => 'تایبەت',
      };

  String _supportLabel(String value) => switch (value) {
        'priority' => 'پێشەنگ',
        'vip' => 'تایبەت',
        _ => 'ئاسایی',
      };

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
        PBService.getOwnerPlatformOverview(),
        PBService.getOwnerTenantsPage(page: 1, perPage: 100),
      ]);
      final page = results[1];
      final rawTenants = page['tenants'];
      final tenants = <Map<String, dynamic>>[];
      if (rawTenants is List) {
        for (final item in rawTenants) {
          if (item is Map) tenants.add(Map<String, dynamic>.from(item));
        }
      }
      if (!mounted) return;
      setState(() {
        _overview = results[0];
        _tenants = tenants;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا زانیاری پلاتفۆرم بهێنرێت.',
        );
      });
    }
  }

  Future<void> _changeLifecycle(Map<String, dynamic> tenant) async {
    String status = (tenant['lifecycle_status'] ?? 'active').toString();
    final reason = TextEditingController();
    try {
      final selected = await showDialog<String>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text((tenant['market_name'] ?? 'مارکێت').toString()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(
                    labelText: 'دۆخی هەژمار',
                    prefixIcon: Icon(Icons.account_tree_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'trial', child: Text('تاقیکردنەوە')),
                    DropdownMenuItem(value: 'active', child: Text('چالاک')),
                    DropdownMenuItem(value: 'grace', child: Text('ماوەی ڕێگەپێدراو')),
                    DropdownMenuItem(
                      value: 'suspended',
                      child: Text('ڕاگیراو'),
                    ),
                    DropdownMenuItem(value: 'archived', child: Text('ئەرشیڤکراو')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => status = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'هۆکار / تێبینی پلاتفۆرم',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('پاشگەزبوونەوە'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, status),
                child: const Text('پاشەکەوت'),
              ),
            ],
          ),
        ),
      );
      if (selected == null) return;

      await PBService.setOwnerTenantLifecycle(
        adminId: tenant['id'].toString(),
        status: selected,
        reason: reason.text.trim(),
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'دۆخی هەژمار نوێ کرایەوە.');
      await _load();
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'گۆڕینی دۆخ سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    } finally {
      reason.dispose();
    }
  }

  Future<void> _editLimits(Map<String, dynamic> tenant) async {
    final deviceCtrl = TextEditingController(
      text: _asInt(tenant['device_limit']).toString(),
    );
    final staffCtrl = TextEditingController(
      text: _asInt(tenant['staff_limit']).toString(),
    );
    String tier = (tenant['support_tier'] ?? 'standard').toString();

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('سنوور و ئاستی خزمەتگوزاری'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: deviceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'سنووری ئامێر',
                    prefixIcon: Icon(Icons.devices_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: staffCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'سنووری کارمەند',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: tier,
                  decoration: const InputDecoration(
                    labelText: 'ئاستی پشتیوانی',
                    prefixIcon: Icon(Icons.support_agent_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'standard',
                      child: Text('ئاسایی'),
                    ),
                    DropdownMenuItem(
                      value: 'priority',
                      child: Text('پێشەنگ'),
                    ),
                    DropdownMenuItem(value: 'vip', child: Text('تایبەت')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => tier = value);
                  },
                ),
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
      if (ok != true) return;

      final deviceLimit = int.tryParse(deviceCtrl.text.trim()) ?? 0;
      final staffLimit = int.tryParse(staffCtrl.text.trim()) ?? -1;
      if (deviceLimit < 1 ||
          deviceLimit > 100 ||
          staffLimit < 0 ||
          staffLimit > 1000) {
        throw Exception('invalid_input');
      }

      await PBService.setOwnerTenantLimits(
        adminId: tenant['id'].toString(),
        deviceLimit: deviceLimit,
        staffLimit: staffLimit,
        supportTier: tier,
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'سنوورەکان نوێ کرانەوە.');
      await _load();
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'نوێکردنەوەی سنوورەکان سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    } finally {
      deviceCtrl.dispose();
      staffCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        title: const Text('کۆنترۆڵی پلاتفۆرم'),
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
                      AppSurface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.privacy_tip_outlined,
                                  color: AppColors.primary,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'سنووری پاراستن',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'خاوەنی سیستەم تەنها زانیاریی سیستەمی هەژمار، بەشداری، دۆخ و تەکنیکی پلاتفۆرم بەڕێوەدەبات. '
                              'کڕیار، قەرز، پارەدانەوە، پسوولە و ناوەڕۆکی مارکێت لێرە پیشان نادرێن.',
                              style: TextStyle(color: secondary, height: 1.55),
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
                            'هەموو مارکێتەکان',
                            _asInt(_overview['total_tenants']),
                            Icons.storefront_outlined,
                          ),
                          _metric(
                            context,
                            'چالاک',
                            _asInt(_overview['active_tenants']),
                            Icons.check_circle_outline_rounded,
                          ),
                          _metric(
                            context,
                            'ڕاگیراو',
                            _asInt(_overview['suspended_tenants']),
                            Icons.pause_circle_outline_rounded,
                          ),
                          _metric(
                            context,
                            '≤ ٧ ڕۆژ',
                            _asInt(_overview['expiring_7_days']),
                            Icons.event_busy_outlined,
                          ),
                          _metric(
                            context,
                            'بەسەرچوو',
                            _asInt(_overview['expired_tenants']),
                            Icons.timer_off_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const AppSectionHeader(
                        title: 'هەژمارەکانی مارکێت',
                        subtitle:
                            'تەنها زانیاری پلاتفۆرم؛ ناوەڕۆکی کاروبار دەستپێنەکراوە',
                      ),
                      const SizedBox(height: 10),
                      ..._tenants.map(
                        (tenant) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _tenantCard(
                            context,
                            tenant,
                            isDark: isDark,
                            onLifecycle: () => _changeLifecycle(tenant),
                            onLimits: () => _editLimits(tenant),
                          ),
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
    int value,
    IconData icon,
  ) {
    return SizedBox(
      width: 155,
      child: AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(height: 12),
            Text(
              value.toString(),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _tenantCard(
    BuildContext context,
    Map<String, dynamic> tenant, {
    required bool isDark,
    required VoidCallback onLifecycle,
    required VoidCallback onLimits,
  }) {
    final end = DateTime.tryParse((tenant['subscription_end'] ?? '').toString());
    final lifecycle = (tenant['lifecycle_status'] ?? 'active').toString();
    final plan = (tenant['subscription_plan'] ?? 'custom').toString();
    final market = (tenant['market_name'] ?? 'مارکێت').toString();
    final adminName = (tenant['admin_name'] ?? '').toString();
    final phone = (tenant['phone'] ?? '').toString();
    final tier = (tenant['support_tier'] ?? 'standard').toString();

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: AppColors.primarySoft,
                child: Icon(Icons.storefront_rounded, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      market,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      adminName.isEmpty ? phone : '$adminName • $phone',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _statusChip(lifecycle),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _mini(Icons.workspace_premium_outlined, _planLabel(plan)),
              _mini(Icons.support_agent_rounded, _supportLabel(tier)),
              _mini(
                Icons.devices_outlined,
                '${_asInt(tenant['device_limit'])} ئامێر',
              ),
              _mini(
                Icons.badge_outlined,
                '${_asInt(tenant['staff_limit'])} کارمەند',
              ),
              _mini(
                Icons.event_outlined,
                end == null
                    ? 'بێ بەروار'
                    : DateFormat('yyyy/MM/dd').format(end.toLocal()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onLifecycle,
                  icon: const Icon(Icons.account_tree_outlined, size: 18),
                  label: const Text('دۆخی هەژمار'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onLimits,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('سنوورەکان'),
                ),
              ),
            ],
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

  Widget _statusChip(String status) {
    final (label, color) = switch (status) {
      'trial' => ('تاقیکردنەوە', Colors.blue),
      'grace' => ('ماوەی ڕێگەپێدراو', Colors.orange),
      'suspended' => ('ڕاگیراو', Colors.red),
      'archived' => ('ئەرشیڤکراو', Colors.grey),
      _ => ('چالاک', Colors.green),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
