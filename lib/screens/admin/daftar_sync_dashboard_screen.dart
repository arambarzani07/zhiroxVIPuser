import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class DaftarSyncDashboardScreen extends StatefulWidget {
  const DaftarSyncDashboardScreen({super.key});

  @override
  State<DaftarSyncDashboardScreen> createState() =>
      _DaftarSyncDashboardScreenState();
}

class _DaftarSyncDashboardScreenState extends State<DaftarSyncDashboardScreen> {
  Map<String, dynamic> _data = const {};
  bool _loading = true;
  bool _syncing = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_loading && !_syncing) unawaited(_load(silent: true));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : const [];

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      await PBService.ensureInitialized();
      final raw = await PBService.client.rpc('get_my_daftar_sync_dashboard');
      if (!mounted) return;
      setState(() {
        _data = _map(raw);
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = AppHelpers.backendErrorMessage(
          error,
          fallback: 'نەتوانرا دۆخی Sync بهێنرێت. دووبارە هەوڵ بدە.',
        ),
      );
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await PBService.client.rpc('request_my_daftar_sync');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'هاوتاکردنی هەردوو ئاراستە دەستی پێکرد؛ دۆخەکە خۆکارانە نوێ دەبێتەوە.',
          ),
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 3));
      await _load(silent: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            AppHelpers.backendErrorMessage(
              error,
              fallback: 'دەستپێکردنی Sync سەرکەوتوو نەبوو.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String _date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return '—';
    final local = parsed.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}/${two(local.month)}/${two(local.day)}  '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Color _statusColor(String status) => switch (status) {
    'healthy' || 'success' => Colors.green,
    'running' => Colors.blue,
    'degraded' || 'skipped' => Colors.orange,
    _ => Colors.red,
  };

  String _statusLabel(String status) => switch (status) {
    'healthy' => 'تەندروست',
    'success' => 'سەرکەوتوو',
    'running' => 'لە کاردایە',
    'skipped' => 'پێویست نەبوو',
    'degraded' => 'لاواز',
    'circuit_open' => 'وەستێنراو',
    'failed' => 'شکستخواردوو',
    _ => status.isEmpty ? 'نادیار' : status,
  };

  @override
  Widget build(BuildContext context) {
    final source = _map(_data['source']);
    final runs = _rows(_data['recent_runs']);
    final errors = _rows(_data['recent_errors']);
    final health = source['health_status']?.toString() ?? '';
    final status = source['last_status']?.toString() ?? '';
    final result = _map(source['last_result']);
    final outboundQueue = _map(_data['outbound_queue']);
    final bidirectionalReady = _data['bidirectional_ready'] == true;
    final openErrors = (_data['open_dead_letters'] as num?)?.toInt() ?? 0;
    final outboundWaiting =
        ((outboundQueue['pending'] as num?)?.toInt() ?? 0) +
        ((outboundQueue['processing'] as num?)?.toInt() ?? 0);
    final outboundErrors =
        ((outboundQueue['failed'] as num?)?.toInt() ?? 0) +
        ((outboundQueue['blocked'] as num?)?.toInt() ?? 0);
    final reconciliationGaps =
        ((source['reconciliation_missing_contacts'] as num?)?.toInt() ?? 0) +
        ((source['reconciliation_missing_transactions'] as num?)?.toInt() ??
            0) +
        ((_data['inbound_missing_candidates'] as num?)?.toInt() ?? 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('داشبۆردی پەیوەندی Daftar'),
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
          ? _ErrorState(message: _error!, retry: _load)
          : source.isEmpty
          ? const Center(
              child: Text('هیچ پەیوەندییەکی Daftar بۆ ئەم مارکێتە چالاک نییە.'),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AppSurface(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                color: _statusColor(health)
                                    .withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Icon(
                                Icons.sync_rounded,
                                color: _statusColor(health),
                                size: 30,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    source['source_name']?.toString() ??
                                        'Daftar Qarz',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    bidirectionalReady
                                        ? 'پەیوەندی دوولایەنە: چالاک'
                                        : 'پەیوەندی دوولایەنە: پێویستی بە پشکنینە',
                                    style: TextStyle(
                                      color: bidirectionalReady
                                          ? Colors.green
                                          : Colors.orange,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: _syncing ? null : _syncNow,
                              icon: _syncing
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.sync),
                              label: const Text('هاوتاکردن'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: (bidirectionalReady
                                    ? Colors.green
                                    : Colors.orange)
                                .withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                bidirectionalReady
                                    ? Icons.compare_arrows_rounded
                                    : Icons.sync_problem_rounded,
                                size: 20,
                                color: bidirectionalReady
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  bidirectionalReady
                                      ? 'دروستکردن، دەستکاری و سڕینەوە لە هەردوو ئەپەکە هاوتا دەکرێت.'
                                      : 'پەیوەندی هەیە، بەڵام یەکێک لە queue، هاوتایی داتا یان Sync پێویستی بە پشکنین هەیە.',
                                  style: TextStyle(
                                    color: bidirectionalReady
                                        ? Colors.green.shade800
                                        : Colors.orange.shade900,
                                    fontWeight: FontWeight.w600,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (source['last_error'] != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              source['last_error'].toString(),
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.55,
                    children: [
                      _MetricCard(
                        label: 'دوا Sync',
                        value: _date(source['last_success_at']),
                        icon: Icons.schedule_rounded,
                        color: _statusColor(status),
                      ),
                      _MetricCard(
                        label: 'دۆخی دوا کار',
                        value: _statusLabel(status),
                        icon: Icons.task_alt_rounded,
                        color: _statusColor(status),
                      ),
                      _MetricCard(
                        label: 'کڕیارە وەرگیراوەکان',
                        value: '${result['fetched_contacts'] ?? 0}',
                        icon: Icons.people_alt_outlined,
                        color: Colors.indigo,
                      ),
                      _MetricCard(
                        label: 'مامەڵە وەرگیراوەکان',
                        value: '${result['fetched_transactions'] ?? 0}',
                        icon: Icons.receipt_long_outlined,
                        color: Colors.teal,
                      ),
                      _MetricCard(
                        label: 'شکستی بەردەوام',
                        value: '${source['consecutive_failures'] ?? 0}',
                        icon: Icons.warning_amber_rounded,
                        color:
                            ((source['consecutive_failures'] as num?)
                                        ?.toInt() ??
                                    0) ==
                                0
                            ? Colors.green
                            : Colors.orange,
                      ),
                      _MetricCard(
                        label: 'هەڵەی چاوەڕوان',
                        value: '$openErrors',
                        icon: Icons.report_gmailerrorred_rounded,
                        color: openErrors == 0 ? Colors.green : Colors.red,
                      ),
                      _MetricCard(
                        label: 'گۆڕانکاریی چاوەڕوان',
                        value: '$outboundWaiting',
                        icon: Icons.outbox_rounded,
                        color: outboundWaiting == 0
                            ? Colors.green
                            : Colors.blue,
                      ),
                      _MetricCard(
                        label: 'هەڵەی ناردن',
                        value: '$outboundErrors',
                        icon: Icons.sync_problem_rounded,
                        color: outboundErrors == 0 ? Colors.green : Colors.red,
                      ),
                      _MetricCard(
                        label: 'جیاوازیی داتا',
                        value: '$reconciliationGaps',
                        icon: Icons.difference_rounded,
                        color: reconciliationGaps == 0
                            ? Colors.green
                            : Colors.orange,
                      ),
                      _MetricCard(
                        label: 'دوا ناردن بۆ Daftar',
                        value: _date(outboundQueue['last_sent_at']),
                        icon: Icons.send_rounded,
                        color: Colors.teal,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const AppSectionHeader(
                    title: 'مێژووی Sync',
                    subtitle: '٢٠ هەوڵی دواوە',
                  ),
                  const SizedBox(height: 10),
                  if (runs.isEmpty)
                    const AppSurface(child: Text('هێشتا مێژووی Sync نییە.'))
                  else
                    AppSurface(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var index = 0; index < runs.length; index++) ...[
                            _RunTile(
                              run: runs[index],
                              date: _date,
                              label: _statusLabel,
                              color: _statusColor,
                            ),
                            if (index != runs.length - 1)
                              const Divider(height: 1),
                          ],
                        ],
                      ),
                    ),
                  if (errors.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    const AppSectionHeader(
                      title: 'هەڵە چاوەڕوانەکان',
                      subtitle: 'داتا ون نابێت و بۆ چارەسەرکردن دەپارێزرێت',
                    ),
                    const SizedBox(height: 10),
                    AppSurface(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < errors.length;
                            index++
                          ) ...[
                            ListTile(
                              leading: const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                              ),
                              title: Text(
                                errors[index]['error_code']?.toString() ??
                                    'هەڵە',
                              ),
                              subtitle: Text(
                                '${_date(errors[index]['last_seen_at'])} • '
                                '${errors[index]['attempts'] ?? 1} هەوڵ',
                              ),
                            ),
                            if (index != errors.length - 1)
                              const Divider(height: 1),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                ],
              ),
            ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => AppSurface(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const Spacer(),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _RunTile extends StatelessWidget {
  const _RunTile({
    required this.run,
    required this.date,
    required this.label,
    required this.color,
  });
  final Map<String, dynamic> run;
  final String Function(dynamic) date;
  final String Function(String) label;
  final Color Function(String) color;

  @override
  Widget build(BuildContext context) {
    final status = run['status']?.toString() ?? '';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color(status).withValues(alpha: .1),
        child: Icon(
          status == 'failed' ? Icons.close : Icons.check,
          color: color(status),
          size: 20,
        ),
      ),
      title: Text(
        label(status),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${date(run['started_at'])} • '
        '${run['fetched_contacts'] ?? 0} کڕیار • '
        '${run['fetched_transactions'] ?? 0} مامەڵە',
      ),
      trailing: run['error_message'] == null
          ? null
          : const Icon(Icons.info_outline, color: Colors.red),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.retry});
  final String message;
  final Future<void> Function({bool silent}) retry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => retry(),
            child: const Text('دووبارە هەوڵ بدە'),
          ),
        ],
      ),
    ),
  );
}
