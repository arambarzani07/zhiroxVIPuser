import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerReadinessCenterScreen extends StatefulWidget {
  const OwnerReadinessCenterScreen({super.key});

  @override
  State<OwnerReadinessCenterScreen> createState() =>
      _OwnerReadinessCenterScreenState();
}

class _OwnerReadinessCenterScreenState
    extends State<OwnerReadinessCenterScreen> {
  Map<String, dynamic> _overview = const {};
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  int _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? 0}') ?? 0;

  String _date(dynamic value) {
    final parsed = DateTime.tryParse('${value ?? ''}');
    if (parsed == null) return '—';
    return DateFormat('yyyy/MM/dd HH:mm').format(parsed.toLocal());
  }

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
        PBService.getOwnerReadinessOverview(),
        PBService.getOwnerReadinessPage(page: 1, perPage: 100),
      ]);

      final rows = <Map<String, dynamic>>[];
      final raw = results[1]['items'];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map) rows.add(Map<String, dynamic>.from(item));
        }
      }

      if (!mounted) return;
      setState(() {
        _overview = results[0];
        _items = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppHelpers.backendErrorMessage(
          error,
          fallback: 'نەتوانرا دۆخی ئامادەبوونی هەژمارەکان بهێنرێت.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tenant Readiness Center'),
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
                              Icons.fact_check_outlined,
                              color: AppColors.primary,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'ئەم ناوەندە تەنها metadata ـی پلاتفۆرم '
                                'هەڵدەسەنگێنێت: access، subscription، device، '
                                'backup، support SLA و app telemetry. '
                                'هیچ ناوەڕۆکی کاروباری مارکێت ناخوێنێتەوە.',
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
                            'هەموو هەژمارەکان',
                            _asInt(_overview['total_tenants']).toString(),
                            Icons.storefront_outlined,
                            AppColors.primary,
                          ),
                          _metric(
                            context,
                            'Ready',
                            _asInt(_overview['ready_tenants']).toString(),
                            Icons.verified_outlined,
                            Colors.green,
                          ),
                          _metric(
                            context,
                            'Attention',
                            _asInt(_overview['attention_tenants']).toString(),
                            Icons.warning_amber_rounded,
                            Colors.orange,
                          ),
                          _metric(
                            context,
                            'Blocked',
                            _asInt(_overview['blocked_tenants']).toString(),
                            Icons.block_outlined,
                            Colors.red,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const AppSectionHeader(
                        title: 'دۆخی ئامادەبوون',
                        subtitle:
                            'Blocked لە پێشەوە، پاشان Attention و Ready',
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
    Color color,
  ) {
    return SizedBox(
      width: 160,
      child: AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
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

  Widget _tenantCard(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    final market = (item['market_name'] ?? 'مارکێت').toString();
    final admin = (item['admin_name'] ?? '').toString();
    final status = (item['readiness_status'] ?? 'attention').toString();
    final score = _asInt(item['readiness_score']);
    final total = _asInt(item['readiness_total']);
    final color = switch (status) {
      'ready' => Colors.green,
      'blocked' => Colors.red,
      _ => Colors.orange,
    };

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.10),
                child: Icon(
                  status == 'ready'
                      ? Icons.verified_rounded
                      : status == 'blocked'
                          ? Icons.block_rounded
                          : Icons.warning_amber_rounded,
                  color: color,
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
              _statusChip(status, color),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: total <= 0 ? 0 : score / total,
                    backgroundColor: color.withValues(alpha: 0.10),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$score/$total',
                style: const TextStyle(fontWeight: FontWeight.w900),
                textDirection: TextDirection.ltr,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _checkChip(
                'Account',
                item['account_ready'] == true,
                Icons.admin_panel_settings_outlined,
              ),
              _checkChip(
                'Subscription',
                item['subscription_ready'] == true,
                Icons.workspace_premium_outlined,
              ),
              _checkChip(
                'Device',
                item['device_ready'] == true,
                Icons.devices_outlined,
              ),
              _checkChip(
                'Backup Fresh',
                item['backup_fresh'] == true,
                Icons.backup_outlined,
              ),
              _checkChip(
                'Backup Verified',
                item['backup_verified'] == true,
                Icons.verified_user_outlined,
              ),
              _checkChip(
                'Support SLA',
                item['support_sla_ready'] == true,
                Icons.support_agent_outlined,
              ),
              _checkChip(
                'App Telemetry',
                item['app_telemetry_ready'] == true,
                Icons.phone_iphone_outlined,
              ),
            ],
          ),
          const SizedBox(height: 14),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text(
              'وردەکاری metadata',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            children: [
              _detailRow(
                context,
                Icons.account_tree_outlined,
                'Lifecycle',
                '${item['lifecycle_status'] ?? 'active'}',
              ),
              _detailRow(
                context,
                Icons.layers_outlined,
                'Feature Plan',
                '${item['feature_plan'] ?? 'standard'}',
              ),
              _detailRow(
                context,
                Icons.security_outlined,
                'Device Policy',
                '${item['device_policy_mode'] ?? 'observe'}',
              ),
              _detailRow(
                context,
                Icons.devices_other_outlined,
                'Device',
                '${_asInt(item['approved_device_count'])} approved • '
                    '${_asInt(item['pending_device_count'])} pending',
              ),
              _detailRow(
                context,
                Icons.system_update_outlined,
                'App',
                '${item['latest_app_version'] ?? 'unknown'} • '
                    '${_date(item['latest_device_seen_at'])}',
              ),
              _detailRow(
                context,
                Icons.backup_outlined,
                'Last Backup',
                _date(item['latest_backup_at']),
              ),
              _detailRow(
                context,
                Icons.verified_outlined,
                'Last Verification',
                _date(item['last_verified_at']),
              ),
              _detailRow(
                context,
                Icons.schedule_outlined,
                'Backup Policy',
                '${_asInt(item['expected_backup_hours'])}h / '
                    '${_asInt(item['verification_interval_days'])}d',
              ),
              _detailRow(
                context,
                Icons.support_agent_rounded,
                'Overdue SLA',
                _asInt(item['overdue_support_count']).toString(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _checkChip(String label, bool ok, IconData icon) {
    final color = ok ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check_circle_rounded : icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status, Color color) {
    final label = switch (status) {
      'ready' => 'Ready',
      'blocked' => 'Blocked',
      _ => 'Attention',
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
