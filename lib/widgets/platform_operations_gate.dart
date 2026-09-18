import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';

class PlatformOperationsGate extends StatefulWidget {
  const PlatformOperationsGate({super.key, required this.child});

  final Widget child;

  @override
  State<PlatformOperationsGate> createState() =>
      _PlatformOperationsGateState();
}

class _PlatformOperationsGateState extends State<PlatformOperationsGate>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _state;
  Timer? _timer;
  bool _refreshing = false;
  String? _dismissedAnnouncementStamp;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refresh());
    });
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final state = await PBService.getPlatformOperationsState();
      if (!mounted) return;
      setState(() => _state = state);
    } catch (_) {
      // Fail open. Connectivity/availability is handled separately by
      // the online-only gate and must not create a false maintenance lock.
    } finally {
      _refreshing = false;
    }
  }

  DateTime? _date(dynamic value) =>
      DateTime.tryParse((value ?? '').toString())?.toLocal();

  String _stamp(Map<String, dynamic> state) =>
      '${state['updated_at'] ?? ''}|${state['announcement_title'] ?? ''}';

  Color _severityColor(String severity) => switch (severity) {
        'success' => Colors.green,
        'warning' => Colors.orange,
        'critical' => Colors.red,
        _ => AppColors.primary,
      };

  IconData _severityIcon(String severity) => switch (severity) {
        'success' => Icons.check_circle_outline_rounded,
        'warning' => Icons.warning_amber_rounded,
        'critical' => Icons.error_outline_rounded,
        _ => Icons.info_outline_rounded,
      };

  String _statusTitle(String status) => switch (status) {
        'degraded' => 'خزمەتگوزاری کەمێک خاو بووە',
        'partial_outage' => 'هەندێک خزمەتگوزاری بەردەست نییە',
        'maintenance' => 'Maintenance',
        _ => '',
      };

  String _statusMessage(String status) => switch (status) {
        'degraded' =>
          'هەندێک بەشی پلاتفۆرم لەوانەیە بە خێرایی ئاسایی کار نەکات.',
        'partial_outage' =>
          'هەندێک خزمەتگوزاری بە شێوەی کاتی بەردەست نییە.',
        'maintenance' =>
          'پلاتفۆرم لە دۆخی Maintenance ـدایە.',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) return widget.child;

    final auth = context.watch<AuthProvider>();
    final isSystemOwner =
        auth.user?.getBoolValue('is_system_owner') ?? false;
    final maintenance = state['maintenance_effective'] == true;
    final announcement = state['announcement_effective'] == true;
    final platformStatus =
        (state['platform_status'] ?? 'operational').toString();

    if (maintenance && !isSystemOwner) {
      return _maintenanceView(context, state);
    }

    final stamp = _stamp(state);
    final showAnnouncement =
        announcement && _dismissedAnnouncementStamp != stamp;
    final showStatus =
        !showAnnouncement && platformStatus != 'operational';

    if (!showAnnouncement && !showStatus) return widget.child;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        SafeArea(
          minimum: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.topCenter,
            child: showAnnouncement
                ? _announcementCard(context, state, stamp)
                : _statusCard(context, platformStatus),
          ),
        ),
      ],
    );
  }

  Widget _maintenanceView(
    BuildContext context,
    Map<String, dynamic> state,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppDarkColors.card : Colors.white;
    final textColor = isDark ? AppDarkColors.textPrimary : const Color(0xFF101828);
    final secondary =
        isDark ? AppDarkColors.textSecondary : const Color(0xFF667085);
    final endsAt = _date(state['maintenance_ends_at']);
    final message = (state['maintenance_message'] ?? '').toString().trim();

    return Material(
      color: isDark ? AppDarkColors.background : const Color(0xFFF7F8FA),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.build_circle_outlined,
                        color: Colors.orange,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'سیستەم لە Maintenance ـدایە',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message.isEmpty
                          ? 'پلاتفۆرم بۆ ماوەیەکی کورت نوێ دەکرێتەوە.'
                          : message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: secondary,
                        height: 1.65,
                      ),
                    ),
                    if (endsAt != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'کاتی کۆتایی: '
                        '${endsAt.year}/${endsAt.month.toString().padLeft(2, '0')}/'
                        '${endsAt.day.toString().padLeft(2, '0')} '
                        '${endsAt.hour.toString().padLeft(2, '0')}:'
                        '${endsAt.minute.toString().padLeft(2, '0')}',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          color: secondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _refreshing ? null : _refresh,
                        icon: _refreshing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded),
                        label: const Text('پشکنینەوە'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _announcementCard(
    BuildContext context,
    Map<String, dynamic> state,
    String stamp,
  ) {
    final severity =
        (state['announcement_severity'] ?? 'info').toString();
    final color = _severityColor(severity);
    final title = (state['announcement_title'] ?? '').toString();
    final message = (state['announcement_message'] ?? '').toString();

    return Material(
      color: Theme.of(context).cardColor,
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_severityIcon(severity), color: color, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(height: 1.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'داخستن',
                onPressed: () {
                  setState(() => _dismissedAnnouncementStamp = stamp);
                },
                icon: const Icon(Icons.close_rounded, size: 19),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusCard(BuildContext context, String status) {
    final color = status == 'partial_outage'
        ? Colors.red
        : status == 'maintenance'
            ? Colors.orange
            : Colors.amber.shade800;

    return Material(
      color: Theme.of(context).cardColor,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.monitor_heart_outlined, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _statusTitle(status),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _statusMessage(status),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'نوێکردنەوە',
                onPressed: _refreshing ? null : _refresh,
                icon: const Icon(Icons.refresh_rounded, size: 19),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
