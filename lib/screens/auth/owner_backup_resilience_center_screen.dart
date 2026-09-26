import 'package:flutter/material.dart';
import 'package:zhirox/utils/owner_date_time.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerBackupResilienceCenterScreen extends StatefulWidget {
  const OwnerBackupResilienceCenterScreen({super.key});

  @override
  State<OwnerBackupResilienceCenterScreen> createState() =>
      _OwnerBackupResilienceCenterScreenState();
}

class _OwnerBackupResilienceCenterScreenState
    extends State<OwnerBackupResilienceCenterScreen> {
  Map<String, dynamic> _overview = const {};
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
        PBService.getOwnerBackupResilienceOverview(),
        PBService.getOwnerBackupResiliencePage(page: 1, perPage: 100),
      ]);
      final items = <Map<String, dynamic>>[];
      final raw = results[1]['items'];
      if (raw is List) {
        for (final row in raw) {
          if (row is Map) items.add(Map<String, dynamic>.from(row));
        }
      }
      if (!mounted) return;
      setState(() {
        _overview = results[0];
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppHelpers.backendErrorMessage(
          error,
          fallback: 'نەتوانرا دۆخی پاشەکەوت بهێنرێت.',
        );
      });
    }
  }

  Future<void> _editPolicy(Map<String, dynamic> item) async {
    var expectedHours = _asInt(item['expected_interval_hours']);
    if (expectedHours <= 0) expectedHours = 48;
    var verificationDays = _asInt(item['verification_interval_days']);
    if (verificationDays <= 0) verificationDays = 30;
    var alertEnabled = item['alert_enabled'] != false;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          scrollable: true,
          title: Text('${item['market_name'] ?? 'مارکێت'}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: expectedHours,
                decoration: const InputDecoration(
                  labelText: 'چاوەڕوانکراوی پاشەکەوت',
                  prefixIcon: Icon(Icons.schedule_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 12, child: Text('هەر ١٢ کاتژمێر')),
                  DropdownMenuItem(value: 24, child: Text('هەر ٢٤ کاتژمێر')),
                  DropdownMenuItem(value: 48, child: Text('هەر ٤٨ کاتژمێر')),
                  DropdownMenuItem(value: 72, child: Text('هەر ٧٢ کاتژمێر')),
                  DropdownMenuItem(value: 168, child: Text('هەفتانە')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => expectedHours = value);
                  }
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: verificationDays,
                decoration: const InputDecoration(
                  labelText: 'ماوەی نوێبوونی پشتڕاستکردنەوە',
                  prefixIcon: Icon(Icons.verified_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 7, child: Text('٧ ڕۆژ')),
                  DropdownMenuItem(value: 14, child: Text('١٤ ڕۆژ')),
                  DropdownMenuItem(value: 30, child: Text('٣٠ ڕۆژ')),
                  DropdownMenuItem(value: 60, child: Text('٦٠ ڕۆژ')),
                  DropdownMenuItem(value: 90, child: Text('٩٠ ڕۆژ')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => verificationDays = value);
                  }
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: alertEnabled,
                onChanged: (value) =>
                    setDialogState(() => alertEnabled = value),
                title: const Text('ئاگادارکردنەوەی پاشەکەوت'),
                subtitle: const Text(
                  'ئاگادارکردنەوە کاتێک پاشەکەوت کۆن یان پشتڕاستکردنەوە دواخراوە',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'خاوەنی سیستەم تەنها دۆخی پاشەکەوت و سیاسەتی چاودێری دەبینێت؛ '
                'هیچ ناوەڕۆکی پاشەکەوت یان زانیاری کاروباری پیشان نادرێت.',
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
                'expected_interval_hours': expectedHours,
                'verification_interval_days': verificationDays,
                'alert_enabled': alertEnabled,
              }),
              child: const Text('پاشەکەوت'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    try {
      await PBService.setOwnerBackupMonitoringPolicy(
        adminId: item['id'].toString(),
        expectedIntervalHours:
            _asInt(result['expected_interval_hours']),
        verificationIntervalDays:
            _asInt(result['verification_interval_days']),
        alertEnabled: result['alert_enabled'] == true,
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'سیاسەتی پاشەکەوت نوێ کرایەوە.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          error,
          fallback: 'نوێکردنەوەی سیاسەتی پاشەکەوت سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('پاشەکەوت و بەردەوامی'),
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
                              Icons.cloud_done_outlined,
                              color: AppColors.primary,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'ئەم ناوەندە تەنها نوێبوونەوە و پشتڕاستکردنەوە، '
                                'ماوەی هەڵگرتنی زانیاریی سیستەمی و سیاسەتی پاشەکەوت چاودێری دەکات. '
                                'خاوەنی سیستەم ناتوانێت ناوەڕۆکی پاشەکەوت بکاتەوە.',
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
                            'چاودێریکراو',
                            _asInt(_overview['monitored_tenants']).toString(),
                            Icons.storefront_outlined,
                          ),
                          _metric(
                            context,
                            'ساغ',
                            _asInt(_overview['healthy_tenants']).toString(),
                            Icons.health_and_safety_outlined,
                          ),
                          _metric(
                            context,
                            'کۆن',
                            _asInt(_overview['stale_tenants']).toString(),
                            Icons.schedule_outlined,
                          ),
                          _metric(
                            context,
                            'پاشەکەوت نییە',
                            _asInt(_overview['missing_backup_tenants']).toString(),
                            Icons.cloud_off_outlined,
                          ),
                          _metric(
                            context,
                            'پشتڕاستکردنەوە دواخراوە',
                            _asInt(_overview['verification_due_tenants'])
                                .toString(),
                            Icons.fact_check_outlined,
                          ),
                          _metric(
                            context,
                            'پشتڕاستکردنەوە شکستی هێنا',
                            _asInt(_overview['verification_failed_tenants'])
                                .toString(),
                            Icons.gpp_bad_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const AppSectionHeader(
                        title: 'دۆخی پاشەکەوتی مارکێتەکان',
                        subtitle:
                            'تەنها زانیاریی سیستەمی — هیچ ناوەڕۆکی کاروباری نییە',
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
                            child: _backupCard(context, item),
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

  Widget _backupCard(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    final state = (item['health_state'] ?? 'missing').toString();
    final market = (item['market_name'] ?? 'مارکێت').toString();
    final admin = (item['admin_name'] ?? '').toString();
    final backupType = (item['latest_backup_type'] ?? '').toString();
    final restorable = item['restorable'];

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: AppColors.primarySoft,
                child: Icon(
                  Icons.backup_outlined,
                  color: AppColors.primary,
                ),
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
                    if (admin.isNotEmpty)
                      Text(
                        admin,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              _statusChip(state),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _mini(
                Icons.event_available_outlined,
                'پاشەکەوت: ${ownerDateTime(item['latest_backup_at'])}',
              ),
              _mini(
                Icons.verified_outlined,
                'پشتڕاستکراوە: ${ownerDateTime(item['last_verified_at'])}',
              ),
              if (backupType.isNotEmpty)
                _mini(Icons.category_outlined, backupType),
              _mini(
                Icons.inventory_2_outlined,
                '${_asInt(item['backup_count'])} پاشەکەوت',
              ),
              _mini(
                Icons.autorenew_rounded,
                '${_asInt(item['automatic_backup_count'])} خۆکار',
              ),
              _mini(
                Icons.schedule_rounded,
                'Expected: ${_asInt(item['expected_interval_hours'])}h',
              ),
              _mini(
                Icons.fact_check_outlined,
                'پشتڕاستکردنەوە: ${_asInt(item['verification_interval_days'])} ڕۆژ',
              ),
              if (restorable is bool)
                _mini(
                  restorable
                      ? Icons.check_circle_outline_rounded
                      : Icons.error_outline_rounded,
                  restorable ? 'ساغی داتا باشە' : 'کێشەی ساغی داتا',
                ),
              _mini(
                item['alert_enabled'] == true
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                item['alert_enabled'] == true ? 'ئاگاداری چالاک' : 'ئاگاداری ناچالاک',
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _editPolicy(item),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('ڕێکخستنی چاودێری پاشەکەوت'),
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

  Widget _statusChip(String state) {
    final (label, color) = switch (state) {
      'healthy' => ('ساغ', Colors.green),
      'stale' => ('کۆن', Colors.orange),
      'verification_due' => ('پشتڕاستکردنەوە', Colors.amber),
      'verification_failed' => ('شکست', Colors.red),
      _ => ('نییە', Colors.red),
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
