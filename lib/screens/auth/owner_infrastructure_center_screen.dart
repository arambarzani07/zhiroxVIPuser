import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerInfrastructureCenterScreen extends StatefulWidget {
  const OwnerInfrastructureCenterScreen({super.key});

  @override
  State<OwnerInfrastructureCenterScreen> createState() =>
      _OwnerInfrastructureCenterScreenState();
}

class _OwnerInfrastructureCenterScreenState
    extends State<OwnerInfrastructureCenterScreen> {
  Map<String, dynamic> _overview = const {};
  List<Map<String, dynamic>> _jobs = const [];
  bool _loading = true;
  String? _error;

  int _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? 0}') ?? 0;

  String _date(dynamic value) {
    final parsed = DateTime.tryParse('${value ?? ''}');
    if (parsed == null) return '—';
    return DateFormat('yyyy/MM/dd HH:mm:ss').format(parsed.toLocal());
  }

  String _duration(dynamic value) {
    final ms = _asInt(value);
    if (ms <= 0) return '—';
    if (ms < 1000) return '$ms ms';
    final seconds = ms / 1000;
    if (seconds < 60) return '${seconds.toStringAsFixed(1)} s';
    final minutes = seconds / 60;
    return '${minutes.toStringAsFixed(1)} min';
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
        PBService.getOwnerInfrastructureOverview(),
        PBService.getOwnerInfrastructureJobsPage(page: 1, perPage: 100),
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
        _jobs = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppHelpers.backendErrorMessage(
          error,
          fallback: 'نەتوانرا دۆخی infrastructure بهێنرێت.',
        );
      });
    }
  }

  bool get _healthy =>
      _asInt(_overview['failed_jobs_24h']) == 0 &&
      _asInt(_overview['failed_deliveries_24h']) == 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Infrastructure Health'),
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
                            Icon(
                              _healthy
                                  ? Icons.check_circle_rounded
                                  : Icons.warning_amber_rounded,
                              color: _healthy
                                  ? AppColors.success
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _healthy
                                    ? 'Infrastructure ـی پلاتفۆرم ئاساییە.'
                                    : 'هەندێک job یان delivery پێویستی بە پشکنین هەیە.',
                                style: const TextStyle(height: 1.55),
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
                            'Scheduled Job',
                            _asInt(_overview['active_jobs']).toString(),
                            Icons.schedule_rounded,
                            AppColors.primary,
                          ),
                          _metric(
                            context,
                            'Job Failure / 24h',
                            _asInt(_overview['failed_jobs_24h']).toString(),
                            Icons.error_outline_rounded,
                            Colors.red,
                          ),
                          _metric(
                            context,
                            'Push Queue',
                            _asInt(_overview['pending_push_queue']).toString(),
                            Icons.queue_rounded,
                            Colors.orange,
                          ),
                          _metric(
                            context,
                            'Delivery Failure / 24h',
                            _asInt(_overview['failed_deliveries_24h'])
                                .toString(),
                            Icons.notifications_off_outlined,
                            Colors.red,
                          ),
                          _metric(
                            context,
                            'Active Push Device',
                            _asInt(_overview['active_push_devices']).toString(),
                            Icons.phone_iphone_rounded,
                            Colors.teal,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      AppSurface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'کۆتا دۆخی Push و Job',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 12),
                            _row(
                              Icons.check_circle_outline_rounded,
                              'کۆتا Push سەرکەوتوو',
                              _date(_overview['latest_push_success_at']),
                            ),
                            const SizedBox(height: 8),
                            _row(
                              Icons.error_outline_rounded,
                              'کۆتا Push شکست',
                              _date(_overview['latest_push_failure_at']),
                            ),
                            const SizedBox(height: 8),
                            _row(
                              Icons.history_rounded,
                              'کۆتا Job Run',
                              _date(_overview['latest_job_run_at']),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const AppSectionHeader(
                        title: 'Scheduled Jobs',
                        subtitle:
                            'Schedule، دۆخی کۆتا run و شکستەکانی ٢٤ کاتژمێر',
                      ),
                      const SizedBox(height: 10),
                      if (_jobs.isEmpty)
                        const AppSurface(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(18),
                              child: Text('هیچ scheduled job ـێک نییە.'),
                            ),
                          ),
                        )
                      else
                        ..._jobs.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _jobCard(context, item),
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

  Widget _jobCard(BuildContext context, Map<String, dynamic> item) {
    final status = (item['latest_status'] ?? 'never').toString();
    final failed = _asInt(item['failed_count_24h']);
    final active = item['active'] == true;
    final color = !active
        ? Colors.grey
        : failed > 0 || (status != 'succeeded' && status != 'running')
            ? Colors.red
            : Colors.green;

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.10),
                child: Icon(Icons.schedule_send_rounded, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (item['job_name'] ?? 'Scheduled Job').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      (item['schedule'] ?? '').toString(),
                      style: Theme.of(context).textTheme.bodySmall,
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                ),
              ),
              Chip(
                label: Text(active ? status : 'inactive'),
                side: BorderSide.none,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _mini(
                Icons.play_circle_outline_rounded,
                '${_asInt(item['run_count_24h'])} run / 24h',
              ),
              _mini(
                Icons.error_outline_rounded,
                '$failed failure / 24h',
              ),
              _mini(
                Icons.timer_outlined,
                _duration(item['latest_duration_ms']),
              ),
              _mini(
                Icons.history_rounded,
                _date(item['latest_started_at']),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) => Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
            textDirection: TextDirection.ltr,
          ),
        ],
      );

  Widget _mini(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );
}
