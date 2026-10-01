import 'package:flutter/material.dart';
import 'package:zhirox/services/autopilot_dashboard_service.dart';

class AutoPilotDashboardScreen extends StatefulWidget {
  const AutoPilotDashboardScreen({super.key});

  @override
  State<AutoPilotDashboardScreen> createState() => _AutoPilotDashboardScreenState();
}

class _AutoPilotDashboardScreenState extends State<AutoPilotDashboardScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = AutoPilotDashboardService.load();
  }

  Future<void> _refresh() async {
    final next = AutoPilotDashboardService.load();
    setState(() => _future = next);
    await next;
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  int _int(Map<String, dynamic> map, String key) {
    final value = map[key];
    return value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  }

  String _healthLabel(String value) {
    switch (value) {
      case 'healthy':
        return 'سالم';
      case 'degraded':
        return 'پێویستی بە سەرنج هەیە';
      case 'attention':
        return 'ئاگاداری گرنگ';
      default:
        return 'نادیار';
    }
  }

  Color _healthColor(BuildContext context, String value) {
    switch (value) {
      case 'healthy':
        return Colors.green;
      case 'degraded':
        return Colors.orange;
      case 'attention':
        return Colors.red;
      default:
        return Theme.of(context).colorScheme.outline;
    }
  }

  String _modeLabel(String value) {
    switch (value) {
      case 'full_auto_safe':
        return 'خۆکاری تەواوی پارێزراو';
      case 'assisted':
        return 'یارمەتیدەر';
      case 'manual':
        return 'دەستی';
      default:
        return value.isEmpty ? 'نادیار' : value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ZHIROX AutoPilot'),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 120),
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 56,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'نەتوانرا دۆخی AutoPilot بخوێندرێتەوە.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('دووبارە هەوڵ بدە'),
                    ),
                  ),
                ],
              ),
            );
          }

          final data = snapshot.data!;
          final autopilot = _map(data['autopilot']);
          final health = _map(data['health']);
          final telegram = _map(data['telegram']);
          final receipts = _map(data['receipts']);
          final statements = _map(data['statements']);
          final notifications = _map(data['notifications']);
          final risk = _map(data['risk']);
          final issues = data['recent_issues'] is List
              ? List<dynamic>.from(data['recent_issues'] as List)
              : <dynamic>[];
          final healthStatus = '${health['status'] ?? ''}';
          final healthColor = _healthColor(context, healthStatus);
          final enabled = autopilot['enabled'] == true;

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: healthColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: healthColor.withValues(alpha: 0.22)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: healthColor.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              healthStatus == 'healthy'
                                  ? Icons.check_circle_rounded
                                  : Icons.warning_amber_rounded,
                              color: healthColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _healthLabel(healthStatus),
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  enabled
                                      ? _modeLabel('${autopilot['mode'] ?? ''}')
                                      : 'AutoPilot ناچالاکە',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: enabled
                                  ? Colors.green.withValues(alpha: 0.12)
                                  : Colors.grey.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              enabled ? 'ON' : 'OFF',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: enabled ? Colors.green.shade700 : Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _MiniMetric(label: 'Queue', value: _int(health, 'active_queue'))),
                          const SizedBox(width: 8),
                          Expanded(child: _MiniMetric(label: 'Retry', value: _int(health, 'retrying'))),
                          const SizedBox(width: 8),
                          Expanded(child: _MiniMetric(label: 'Failed', value: _int(health, 'failed'))),
                          const SizedBox(width: 8),
                          Expanded(child: _MiniMetric(label: 'Dead', value: _int(health, 'dead_letter'))),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _SectionCard(
                  icon: Icons.telegram_rounded,
                  title: 'Telegram',
                  metrics: [
                    _MetricData('پەیوەستکراو', _int(telegram, 'linked_customers')),
                    _MetricData('نێردراو / 24 کاتژمێر', _int(telegram, 'sent_24h')),
                    _MetricData('لە Queue', _int(telegram, 'queued')),
                    _MetricData('Retry', _int(telegram, 'retrying')),
                    _MetricData('Failed', _int(telegram, 'failed')),
                    _MetricData('Dead-letter', _int(telegram, 'dead_letter')),
                  ],
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  icon: Icons.receipt_long_rounded,
                  title: 'پسووڵەی PDF',
                  metrics: [
                    _MetricData('نێردراو / 24 کاتژمێر', _int(receipts, 'sent_24h')),
                    _MetricData('لە Queue', _int(receipts, 'queued')),
                    _MetricData('Processing', _int(receipts, 'processing')),
                    _MetricData('Retry', _int(receipts, 'retrying')),
                    _MetricData('Failed', _int(receipts, 'failed')),
                    _MetricData('Dead-letter', _int(receipts, 'dead_letter')),
                  ],
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  icon: Icons.picture_as_pdf_rounded,
                  title: 'Full Statement',
                  metrics: [
                    _MetricData('تەواوبوو / 30 ڕۆژ', _int(statements, 'completed_30d')),
                    _MetricData('لە Queue', _int(statements, 'queued')),
                    _MetricData('Processing', _int(statements, 'processing')),
                    _MetricData('Retry', _int(statements, 'retrying')),
                    _MetricData('Failed', _int(statements, 'failed')),
                    _MetricData('Dead-letter', _int(statements, 'dead_letter')),
                  ],
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  icon: Icons.notifications_active_rounded,
                  title: 'ئاگادارکردنەوەکان',
                  metrics: [
                    _MetricData('تەواوبوو / 24 کاتژمێر', _int(notifications, 'completed_24h')),
                    _MetricData('Pending', _int(notifications, 'pending')),
                    _MetricData('Processing', _int(notifications, 'processing')),
                    _MetricData('Failed', _int(notifications, 'failed')),
                  ],
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  icon: Icons.health_and_safety_rounded,
                  title: 'Risk Engine',
                  metrics: [
                    _MetricData('کۆی هەڵسەنگێنراو', _int(risk, 'total')),
                    _MetricData('Low', _int(risk, 'low')),
                    _MetricData('Medium', _int(risk, 'medium')),
                    _MetricData('High', _int(risk, 'high')),
                    _MetricData('Critical', _int(risk, 'critical')),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'کێشە نوێکان',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
                if (issues.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.18)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_outline_rounded, color: Colors.green),
                        SizedBox(width: 10),
                        Expanded(child: Text('هیچ کێشەی retry / failed / dead-letter نییە.')),
                      ],
                    ),
                  )
                else
                  ...issues.map((raw) {
                    final issue = _map(raw);
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.error_outline_rounded, color: Colors.orange),
                        title: Text('${issue['source'] ?? 'AutoPilot'} • ${issue['status'] ?? ''}'),
                        subtitle: Text(
                          '${issue['error'] ?? 'هەڵەی نادیار'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value.toString(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _MetricData {
  const _MetricData(this.label, this.value);

  final String label;
  final int value;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.icon, required this.title, required this.metrics});

  final IconData icon;
  final String title;
  final List<_MetricData> metrics;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: metrics.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.75,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              final item = metrics[index];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.value.toString(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
