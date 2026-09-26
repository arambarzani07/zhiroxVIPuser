import 'package:flutter/material.dart';
import 'package:zhirox/utils/owner_date_time.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerIncidentCenterScreen extends StatefulWidget {
  const OwnerIncidentCenterScreen({super.key});

  @override
  State<OwnerIncidentCenterScreen> createState() =>
      _OwnerIncidentCenterScreenState();
}

class _OwnerIncidentCenterScreenState extends State<OwnerIncidentCenterScreen> {
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
        PBService.getOwnerIncidentOverview(),
        PBService.getOwnerIncidentsPage(page: 1, perPage: 100),
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
          fallback: 'نەتوانرا زانیاری ڕووداوەکانی پلاتفۆرم بهێنرێت.',
        );
      });
    }
  }

  Future<void> _editIncident([Map<String, dynamic>? item]) async {
    final title = TextEditingController(text: '${item?['title'] ?? ''}');
    final summary = TextEditingController(text: '${item?['summary'] ?? ''}');
    final component = TextEditingController(
      text: '${item?['affected_component'] ?? 'platform'}',
    );
    var severity = '${item?['severity'] ?? 'minor'}';
    var status = '${item?['status'] ?? 'investigating'}';
    var publicVisible = item?['public_visible'] != false;
    DateTime? startsAt =
        DateTime.tryParse('${item?['starts_at'] ?? ''}')?.toLocal();

    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            scrollable: true,
            title: Text(item == null ? 'دروستکردنی ڕووداو' : 'نوێکردنەوەی ڕووداو'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  maxLength: 180,
                  decoration: const InputDecoration(
                    labelText: 'ناونیشان',
                    prefixIcon: Icon(Icons.title_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: summary,
                  maxLength: 4000,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'پوختە',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: component,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'بەشی کاریگەر',
                    prefixIcon: Icon(Icons.extension_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: severity,
                  decoration: const InputDecoration(
                    labelText: 'ئاستی گرنگی',
                    prefixIcon: Icon(Icons.warning_amber_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'info', child: Text('زانیاری')),
                    DropdownMenuItem(value: 'minor', child: Text('کەم')),
                    DropdownMenuItem(value: 'major', child: Text('گرنگ')),
                    DropdownMenuItem(value: 'critical', child: Text('زۆر گرنگ')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => severity = value);
                    }
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(
                    labelText: 'دۆخ',
                    prefixIcon: Icon(Icons.track_changes_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'scheduled', child: Text('پلاندانراو')),
                    DropdownMenuItem(value: 'investigating', child: Text('لێکۆڵینەوە')),
                    DropdownMenuItem(value: 'identified', child: Text('هۆکار ناسراوە')),
                    DropdownMenuItem(value: 'monitoring', child: Text('چاودێری')),
                    DropdownMenuItem(value: 'resolved', child: Text('چارەسەرکراو')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => status = value);
                    }
                  },
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: publicVisible,
                  onChanged: (value) =>
                      setDialogState(() => publicVisible = value),
                  title: const Text('پیشاندانی گشتی'),
                  subtitle: const Text(
                    'Admin/کارمەند تەنها ڕووداوە گشتییە چالاکەکان دەبینن.',
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_rounded),
                  title: const Text('کاتی دەستپێک'),
                  subtitle: Text(
                    startsAt == null
                        ? 'ئێستا'
                        : DateFormat('yyyy/MM/dd HH:mm').format(startsAt!),
                    textDirection: TextDirection.ltr,
                  ),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () async {
                    final now = DateTime.now();
                    final date = await showDatePicker(
                      context: ctx,
                      initialDate: startsAt ?? now,
                      firstDate: now.subtract(const Duration(days: 365)),
                      lastDate: now.add(const Duration(days: 730)),
                    );
                    if (date == null || !ctx.mounted) return;
                    final time = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.fromDateTime(startsAt ?? now),
                    );
                    if (time == null) return;
                    setDialogState(() {
                      startsAt = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
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

      if (accepted != true) return;
      if (title.text.trim().isEmpty) {
        if (!mounted) return;
        AppHelpers.showSnackBar(
          context,
          'ناونیشانی ڕووداو پێویستە.',
          isError: true,
        );
        return;
      }

      if (item == null) {
        await PBService.createOwnerIncident(
          title: title.text.trim(),
          summary: summary.text.trim(),
          severity: severity,
          status: status,
          affectedComponent: component.text.trim().isEmpty
              ? 'platform'
              : component.text.trim(),
          publicVisible: publicVisible,
          startsAt: startsAt,
        );
      } else {
        await PBService.updateOwnerIncident(
          incidentId: item['id'].toString(),
          title: title.text.trim(),
          summary: summary.text.trim(),
          severity: severity,
          status: status,
          affectedComponent: component.text.trim().isEmpty
              ? 'platform'
              : component.text.trim(),
          publicVisible: publicVisible,
          startsAt: startsAt,
        );
      }

      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        item == null ? 'ڕووداو دروست کرا.' : 'ڕووداو نوێ کرایەوە.',
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          error,
          fallback: 'پاشەکەوتکردنی ڕووداو سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    } finally {
      title.dispose();
      summary.dispose();
      component.dispose();
    }
  }

  String _statusLabel(String value) => switch (value) {
        'scheduled' => 'پلاندانراو',
        'investigating' => 'لێکۆڵینەوە',
        'identified' => 'هۆکار ناسراوە',
        'monitoring' => 'چاودێری',
        'resolved' => 'چارەسەرکراو',
        _ => value,
      };

  Color _severityColor(String value) => switch (value) {
        'critical' => Colors.red,
        'major' => Colors.orange,
        'minor' => Colors.amber,
        _ => Colors.blue,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ناوەندی ڕووداو و دۆخی خزمەتگوزاری'),
        actions: [
          IconButton(
            tooltip: 'نوێکردنەوە',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editIncident(),
        icon: const Icon(Icons.add_alert_rounded),
        label: const Text('ڕووداوی نوێ'),
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
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      const AppSurface(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.crisis_alert_rounded,
                              color: AppColors.primary,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'ئەم ناوەندە تەنها ڕووداو و دۆخی خزمەتگوزاریی '
                                'پلاتفۆرم بەڕێوەدەبات؛ هیچ ناوەڕۆکی کاروباری '
                                'مارکێت ناخوێنێتەوە.',
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
                            'چالاک',
                            _asInt(_overview['active_incidents']).toString(),
                            Icons.warning_amber_rounded,
                          ),
                          _metric(
                            context,
                            'زۆر گرنگ',
                            _asInt(_overview['critical_incidents']).toString(),
                            Icons.error_outline_rounded,
                          ),
                          _metric(
                            context,
                            'پلاندانراو',
                            _asInt(_overview['scheduled_incidents']).toString(),
                            Icons.event_outlined,
                          ),
                          _metric(
                            context,
                            'چارەسەرکراو / ٣٠ ڕۆژ',
                            _asInt(_overview['resolved_30d']).toString(),
                            Icons.verified_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const AppSectionHeader(
                        title: 'ڕووداوەکان',
                        subtitle:
                            'دۆخ، گرنگی، بەشی کاریگەر و کاتی نوێکردنەوە',
                      ),
                      const SizedBox(height: 10),
                      if (_items.isEmpty)
                        const AppSurface(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(
                              child: Text('هیچ ڕووداوێک تۆمار نەکراوە.'),
                            ),
                          ),
                        )
                      else
                        ..._items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _incidentCard(context, item),
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
  ) =>
      SizedBox(
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

  Widget _incidentCard(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    final severity = '${item['severity'] ?? 'minor'}';
    final status = '${item['status'] ?? 'investigating'}';
    final color = _severityColor(severity);

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.10),
                child: Icon(Icons.crisis_alert_rounded, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${item['title'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Chip(
                label: Text(_statusLabel(status)),
                backgroundColor: color.withValues(alpha: 0.08),
                labelStyle: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if ('${item['summary'] ?? ''}'.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '${item['summary']}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _mini(
                Icons.extension_outlined,
                '${item['affected_component'] ?? 'platform'}',
              ),
              _mini(
                Icons.visibility_outlined,
                item['public_visible'] == true ? 'گشتی' : 'ناوخۆیی',
              ),
              _mini(
                Icons.schedule_rounded,
                ownerDateTime(item['updated_at']),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _editIncident(item),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('نوێکردنەوە'),
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
