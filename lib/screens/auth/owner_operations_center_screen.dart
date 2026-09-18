import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerOperationsCenterScreen extends StatefulWidget {
  const OwnerOperationsCenterScreen({super.key});

  @override
  State<OwnerOperationsCenterScreen> createState() =>
      _OwnerOperationsCenterScreenState();
}

class _OwnerOperationsCenterScreenState
    extends State<OwnerOperationsCenterScreen> {
  final _maintenanceController = TextEditingController();
  final _announcementTitleController = TextEditingController();
  final _announcementMessageController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  String _platformStatus = 'operational';
  bool _maintenanceEnabled = false;
  DateTime? _maintenanceStartsAt;
  DateTime? _maintenanceEndsAt;

  bool _announcementEnabled = false;
  String _announcementSeverity = 'info';
  DateTime? _announcementStartsAt;
  DateTime? _announcementEndsAt;

  DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  String _dateLabel(DateTime? value) {
    if (value == null) return 'دیاری نەکراوە';
    return DateFormat('yyyy/MM/dd HH:mm').format(value);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _maintenanceController.dispose();
    _announcementTitleController.dispose();
    _announcementMessageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await PBService.getPlatformOperationsState();
      if (!mounted) return;
      setState(() {
        _platformStatus =
            (state['platform_status'] ?? 'operational').toString();
        _maintenanceEnabled = state['maintenance_enabled'] == true;
        _maintenanceController.text =
            (state['maintenance_message'] ?? '').toString();
        _maintenanceStartsAt = _date(state['maintenance_starts_at']);
        _maintenanceEndsAt = _date(state['maintenance_ends_at']);

        _announcementEnabled = state['announcement_enabled'] == true;
        _announcementTitleController.text =
            (state['announcement_title'] ?? '').toString();
        _announcementMessageController.text =
            (state['announcement_message'] ?? '').toString();
        _announcementSeverity =
            (state['announcement_severity'] ?? 'info').toString();
        _announcementStartsAt = _date(state['announcement_starts_at']);
        _announcementEndsAt = _date(state['announcement_ends_at']);
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

  Future<DateTime?> _pickDateTime(DateTime? current) async {
    final now = DateTime.now();
    final base = current ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return current;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null) return current;

    return DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
  }

  bool _validRange(DateTime? start, DateTime? end) {
    if (start == null || end == null) return true;
    return end.isAfter(start);
  }

  Future<void> _save() async {
    if (_saving) return;

    if (_maintenanceEnabled &&
        _maintenanceController.text.trim().isEmpty) {
      AppHelpers.showSnackBar(
        context,
        'بۆ دۆخی چاکسازی پەیامێک بنووسە.',
        isError: true,
      );
      return;
    }
    if (_announcementEnabled &&
        (_announcementTitleController.text.trim().isEmpty ||
            _announcementMessageController.text.trim().isEmpty)) {
      AppHelpers.showSnackBar(
        context,
        'ناونیشان و دەقی ئاگادارکردنەوە پڕ بکەرەوە.',
        isError: true,
      );
      return;
    }
    if (!_validRange(_maintenanceStartsAt, _maintenanceEndsAt) ||
        !_validRange(_announcementStartsAt, _announcementEndsAt)) {
      AppHelpers.showSnackBar(
        context,
        'کاتی کۆتایی دەبێت دوای کاتی دەستپێک بێت.',
        isError: true,
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await PBService.setOwnerOperationsState(
        platformStatus: _platformStatus,
        maintenanceEnabled: _maintenanceEnabled,
        maintenanceMessage: _maintenanceController.text.trim(),
        maintenanceStartsAt: _maintenanceStartsAt,
        maintenanceEndsAt: _maintenanceEndsAt,
        announcementEnabled: _announcementEnabled,
        announcementTitle: _announcementTitleController.text.trim(),
        announcementMessage: _announcementMessageController.text.trim(),
        announcementSeverity: _announcementSeverity,
        announcementStartsAt: _announcementStartsAt,
        announcementEndsAt: _announcementEndsAt,
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        'دۆخی پلاتفۆرم پاشەکەوت کرا.',
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          error,
          fallback: 'پاشەکەوتکردنی ڕێکخستنەکانی پلاتفۆرم سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        title: const Text('بەڕێوەبردنی پلاتفۆرم'),
        actions: [
          IconButton(
            tooltip: 'نوێکردنەوە',
            onPressed: _loading || _saving ? null : _load,
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
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    AppSurface(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.settings_input_antenna_rounded,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'خاوەنی سیستەم تەنها دۆخی پلاتفۆرم، چاکسازی و '
                              'ئاگادارکردنەوەی سیستەمی کۆنترۆڵ دەکات. '
                              'ئەم بەشە هیچ ناوەڕۆکی کاروباری مارکێت ناخوێنێتەوە.',
                              style: TextStyle(
                                color: secondary,
                                height: 1.55,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppSurface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'دۆخی پلاتفۆرم',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _platformStatus,
                            decoration: const InputDecoration(
                              labelText: 'دۆخی پلاتفۆرم',
                              prefixIcon: Icon(Icons.monitor_heart_outlined),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'operational',
                                child: Text('ئاسایی'),
                              ),
                              DropdownMenuItem(
                                value: 'degraded',
                                child: Text('لاوازبوو'),
                              ),
                              DropdownMenuItem(
                                value: 'partial_outage',
                                child: Text('بەشێک وەستاوە'),
                              ),
                              DropdownMenuItem(
                                value: 'maintenance',
                                child: Text('چاکسازی'),
                              ),
                            ],
                            onChanged: _saving
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() => _platformStatus = value);
                                    }
                                  },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppSurface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            secondary:
                                const Icon(Icons.build_circle_outlined),
                            title: const Text(
                              'دۆخی چاکسازی',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: const Text(
                              'وەستاندن یان دیاریکردنی کاتی خزمەتگوزاری',
                            ),
                            value: _maintenanceEnabled,
                            onChanged: _saving
                                ? null
                                : (value) => setState(
                                      () => _maintenanceEnabled = value,
                                    ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _maintenanceController,
                            enabled: !_saving,
                            minLines: 3,
                            maxLines: 5,
                            maxLength: 1000,
                            decoration: const InputDecoration(
                              labelText: 'پەیامی چاکسازی',
                              hintText:
                                  'نموونە: سیستەم بۆ ماوەیەکی کورت نوێ دەکرێتەوە...',
                              alignLabelWithHint: true,
                              prefixIcon: Icon(Icons.info_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _scheduleRow(
                            title: 'دەستپێک',
                            value: _maintenanceStartsAt,
                            onPick: _saving
                                ? null
                                : () async {
                                    final value = await _pickDateTime(
                                      _maintenanceStartsAt,
                                    );
                                    if (mounted) {
                                      setState(
                                        () => _maintenanceStartsAt = value,
                                      );
                                    }
                                  },
                            onClear: _saving || _maintenanceStartsAt == null
                                ? null
                                : () => setState(
                                      () => _maintenanceStartsAt = null,
                                    ),
                          ),
                          const SizedBox(height: 8),
                          _scheduleRow(
                            title: 'کۆتایی',
                            value: _maintenanceEndsAt,
                            onPick: _saving
                                ? null
                                : () async {
                                    final value = await _pickDateTime(
                                      _maintenanceEndsAt,
                                    );
                                    if (mounted) {
                                      setState(
                                        () => _maintenanceEndsAt = value,
                                      );
                                    }
                                  },
                            onClear: _saving || _maintenanceEndsAt == null
                                ? null
                                : () => setState(
                                      () => _maintenanceEndsAt = null,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppSurface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            secondary:
                                const Icon(Icons.campaign_outlined),
                            title: const Text(
                              'ئاگادارکردنەوەی گشتی سیستەم',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: const Text(
                              'پەیامی گشتی پلاتفۆرم بەبێ داتای کاروبار',
                            ),
                            value: _announcementEnabled,
                            onChanged: _saving
                                ? null
                                : (value) => setState(
                                      () => _announcementEnabled = value,
                                    ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _announcementSeverity,
                            decoration: const InputDecoration(
                              labelText: 'ئاستی گرنگی',
                              prefixIcon:
                                  Icon(Icons.notification_important_outlined),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'info',
                                child: Text('زانیاری'),
                              ),
                              DropdownMenuItem(
                                value: 'success',
                                child: Text('سەرکەوتوو'),
                              ),
                              DropdownMenuItem(
                                value: 'warning',
                                child: Text('ئاگاداری'),
                              ),
                              DropdownMenuItem(
                                value: 'critical',
                                child: Text('زۆر گرنگ'),
                              ),
                            ],
                            onChanged: _saving
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(
                                        () => _announcementSeverity = value,
                                      );
                                    }
                                  },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _announcementTitleController,
                            enabled: !_saving,
                            maxLength: 160,
                            decoration: const InputDecoration(
                              labelText: 'ناونیشان',
                              prefixIcon: Icon(Icons.title_rounded),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _announcementMessageController,
                            enabled: !_saving,
                            minLines: 3,
                            maxLines: 6,
                            maxLength: 1500,
                            decoration: const InputDecoration(
                              labelText: 'دەقی ئاگادارکردنەوە',
                              alignLabelWithHint: true,
                              prefixIcon: Icon(Icons.message_outlined),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _scheduleRow(
                            title: 'دەستپێک',
                            value: _announcementStartsAt,
                            onPick: _saving
                                ? null
                                : () async {
                                    final value = await _pickDateTime(
                                      _announcementStartsAt,
                                    );
                                    if (mounted) {
                                      setState(
                                        () => _announcementStartsAt = value,
                                      );
                                    }
                                  },
                            onClear:
                                _saving || _announcementStartsAt == null
                                    ? null
                                    : () => setState(
                                          () => _announcementStartsAt = null,
                                        ),
                          ),
                          const SizedBox(height: 8),
                          _scheduleRow(
                            title: 'کۆتایی',
                            value: _announcementEndsAt,
                            onPick: _saving
                                ? null
                                : () async {
                                    final value = await _pickDateTime(
                                      _announcementEndsAt,
                                    );
                                    if (mounted) {
                                      setState(
                                        () => _announcementEndsAt = value,
                                      );
                                    }
                                  },
                            onClear: _saving || _announcementEndsAt == null
                                ? null
                                : () => setState(
                                      () => _announcementEndsAt = null,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(
                        _saving
                            ? 'پاشەکەوت دەکرێت...'
                            : 'پاشەکەوتکردنی ڕێکخستنەکانی پلاتفۆرم',
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }

  Widget _scheduleRow({
    required String title,
    required DateTime? value,
    required VoidCallback? onPick,
    required VoidCallback? onClear,
  }) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _dateLabel(value),
                  style: Theme.of(context).textTheme.bodySmall,
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'دیاریکردنی کات',
            onPressed: onPick,
            icon: const Icon(Icons.edit_calendar_outlined),
          ),
          IconButton(
            tooltip: 'سڕینەوەی کات',
            onPressed: onClear,
            icon: const Icon(Icons.clear_rounded),
          ),
        ],
      ),
    );
  }
}
