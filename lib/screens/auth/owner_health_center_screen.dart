import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerHealthCenterScreen extends StatefulWidget {
  const OwnerHealthCenterScreen({super.key});

  @override
  State<OwnerHealthCenterScreen> createState() =>
      _OwnerHealthCenterScreenState();
}

class _OwnerHealthCenterScreenState extends State<OwnerHealthCenterScreen> {
  Map<String, dynamic> _health = const {};
  List<Map<String, dynamic>> _audit = const [];
  bool _loading = true;
  String? _error;

  int _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? 0}') ?? 0;

  double _asDouble(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('${value ?? 0}') ?? 0;

  String _date(dynamic value) {
    final parsed = DateTime.tryParse('${value ?? ''}');
    if (parsed == null) return '—';
    return DateFormat('yyyy/MM/dd HH:mm').format(parsed.toLocal());
  }

  String _money(dynamic value) {
    final n = _asDouble(value);
    return "${NumberFormat('#,##0', 'en').format(n)} د.ع";
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
        PBService.getOwnerHealthOverview(),
        PBService.getOwnerPlatformAuditPage(page: 1, perPage: 100),
      ]);
      final auditPage = results[1];
      final rows = <Map<String, dynamic>>[];
      final raw = auditPage['items'];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map) rows.add(Map<String, dynamic>.from(item));
        }
      }
      if (!mounted) return;
      setState(() {
        _health = results[0];
        _audit = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppHelpers.backendErrorMessage(
          error,
          fallback: 'نەتوانرا دۆخی پلاتفۆرم بهێنرێت.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        title: const Text('تەندروستی و پاراستنی سیستەم'),
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
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.verified_user_outlined,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Privacy-safe Platform Health',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'ئەم بەشە تەنها metadata ـی پلاتفۆرم، Backup، '
                                    'بەشداری و کردارەکانی Owner نیشان دەدات. '
                                    'هیچ کڕیار، قەرز، پارەدانەوە، پسوولە یان ناوەڕۆکی مارکێت نادات.',
                                    style: TextStyle(
                                      color: secondary,
                                      height: 1.55,
                                    ),
                                  ),
                                ],
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
                            'Backup تازە',
                            _asInt(_health['backup_fresh_tenants']).toString(),
                            Icons.cloud_done_outlined,
                            good: _asInt(_health['backup_stale_tenants']) == 0,
                          ),
                          _metric(
                            context,
                            'Backup کۆن/نییە',
                            _asInt(_health['backup_stale_tenants']).toString(),
                            Icons.cloud_off_outlined,
                            good: _asInt(_health['backup_stale_tenants']) == 0,
                          ),
                          _metric(
                            context,
                            'پارەدانی Pending',
                            _asInt(_health['billing_pending_30d']).toString(),
                            Icons.hourglass_bottom_rounded,
                            good: _asInt(_health['billing_pending_30d']) == 0,
                          ),
                          _metric(
                            context,
                            'پارەدانی Failed',
                            _asInt(_health['billing_failed_30d']).toString(),
                            Icons.error_outline_rounded,
                            good: _asInt(_health['billing_failed_30d']) == 0,
                          ),
                          _metric(
                            context,
                            'داهاتی ٣٠ ڕۆژ',
                            _money(_health['platform_revenue_30d_iqd']),
                            Icons.payments_outlined,
                            good: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      AppSurface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'دۆخی پلاتفۆرم',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _row(
                              Icons.storage_rounded,
                              'Database',
                              'Online',
                              Colors.green,
                            ),
                            _row(
                              Icons.backup_outlined,
                              'کۆتا Backup',
                              _date(_health['latest_backup_at']),
                              null,
                            ),
                            _row(
                              Icons.system_update_alt_rounded,
                              'کۆتا ڕێکخستنی Update',
                              _date(_health['latest_update_config_at']),
                              null,
                            ),
                            _row(
                              Icons.history_rounded,
                              'کۆتا کرداری Owner',
                              _date(_health['latest_owner_action_at']),
                              null,
                            ),
                            _row(
                              Icons.storefront_outlined,
                              'مارکێتی چالاک',
                              _asInt(_health['active_tenants']).toString(),
                              null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const AppSectionHeader(
                        title: 'Owner Audit',
                        subtitle:
                            'تەنها کردارەکانی پلاتفۆرم؛ business data تۆمار ناکرێت',
                      ),
                      const SizedBox(height: 8),
                      if (_audit.isEmpty)
                        const AppSurface(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('هێشتا کرداری Owner تۆمار نەکراوە.'),
                            ),
                          ),
                        )
                      else
                        ..._audit.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AppSurface(
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const CircleAvatar(
                                  backgroundColor: AppColors.primarySoft,
                                  child: Icon(
                                    Icons.history_rounded,
                                    color: AppColors.primary,
                                    size: 19,
                                  ),
                                ),
                                title: Text(
                                  _actionLabel(
                                    (item['action'] ?? '').toString(),
                                  ),
                                ),
                                subtitle: Text(
                                  _auditSubtitle(item),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Text(
                                  _date(item['created_at']),
                                  style: Theme.of(context).textTheme.bodySmall,
                                  textDirection: TextDirection.ltr,
                                ),
                              ),
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
    String value,
    IconData icon, {
    required bool good,
  }) {
    final color = good ? Colors.green : Colors.orange;
    return SizedBox(
      width: 160,
      child: AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 23),
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

  Widget _row(
    IconData icon,
    String label,
    String value,
    Color? valueColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppColors.primary),
          const SizedBox(width: 9),
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }

  String _actionLabel(String action) => const {
        'tenant_lifecycle_changed': 'گۆڕینی دۆخی هەژمار',
        'tenant_limits_changed': 'گۆڕینی سنوورەکان',
        'subscription_changed': 'گۆڕینی بەشداری',
        'admin_sessions_revoked': 'ڕاگرتنی Session ـەکان',
        'admin_account_locked': 'قوفڵکردنی هەژماری Admin',
        'admin_account_unlocked': 'کردنەوەی هەژماری Admin',
        'support_ticket_updated': 'نوێکردنەوەی Support Ticket',
      }[action] ??
      action;

  String _auditSubtitle(Map<String, dynamic> item) {
    final market = (item['market_name'] ?? '').toString();
    final metadata = item['metadata'];
    final parts = <String>[
      if (market.isNotEmpty) market,
    ];
    if (metadata is Map) {
      final status = metadata['status']?.toString() ?? '';
      final tier = metadata['support_tier']?.toString() ?? '';
      final reason = metadata['reason']?.toString() ?? '';
      if (status.isNotEmpty) parts.add('Status: $status');
      if (tier.isNotEmpty) parts.add('Support: $tier');
      if (reason.isNotEmpty) parts.add(reason);
    }
    return parts.isEmpty ? 'کرداری پلاتفۆرم' : parts.join(' • ');
  }
}
