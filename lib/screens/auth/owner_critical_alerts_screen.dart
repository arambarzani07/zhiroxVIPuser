import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/notification_service.dart';
import 'package:zhirox/services/owner_critical_alert_service.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerCriticalAlertsScreen extends StatefulWidget {
  const OwnerCriticalAlertsScreen({super.key});

  @override
  State<OwnerCriticalAlertsScreen> createState() =>
      _OwnerCriticalAlertsScreenState();
}

class _OwnerCriticalAlertsScreenState extends State<OwnerCriticalAlertsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_subscribeRealtime());
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
    super.dispose();
  }

  Future<void> _subscribeRealtime() async {
    try {
      await PBService.ensureInitialized();
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id ?? '';
      if (userId.isEmpty || !mounted) return;

      final previous = _channel;
      if (previous != null) await client.removeChannel(previous);

      final channel = client
          .channel('owner-critical-alerts:$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'app_realtime_notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'recipient_user_id',
              value: userId,
            ),
            callback: (payload) {
              unawaited(_handleRealtimeRow(payload.newRecord));
            },
          )
          .subscribe();
      _channel = channel;
    } catch (_) {
      // Pull-to-refresh remains available if a realtime connection is unavailable.
    }
  }

  Future<void> _handleRealtimeRow(Map<String, dynamic> raw) async {
    final type = raw['event_type']?.toString() ?? '';
    if (type != 'owner_autopilot_critical' &&
        type != 'owner_autopilot_recovery') {
      return;
    }

    final row = Map<String, dynamic>.from(raw);
    final id = row['id']?.toString() ?? '';
    if (mounted) {
      setState(() {
        final withoutDuplicate = _items
            .where((item) => item['id']?.toString() != id)
            .toList(growable: false);
        _items = [row, ...withoutDuplicate].take(100).toList(growable: false);
      });
    }

    try {
      await NotificationService.init();
      await NotificationService.show(
        title: row['title']?.toString() ?? 'ZHIROX AutoPilot',
        body: row['body']?.toString() ?? '',
        id: id.isEmpty
            ? DateTime.now().millisecondsSinceEpoch.remainder(100000)
            : id.hashCode & 0x7fffffff,
      );
      if (id.isNotEmpty) {
        await OwnerCriticalAlertService.markDelivered(id);
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await OwnerCriticalAlertService.recent(limit: 100);
      if (!mounted) return;
      setState(() => _items = items);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _when(dynamic raw) {
    final value = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (value == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}/${two(value.month)}/${two(value.day)}  ${two(value.hour)}:${two(value.minute)}';
  }

  Future<void> _markRead(Map<String, dynamic> item) async {
    if (item['read_at'] != null) return;
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return;
    await OwnerCriticalAlertService.markRead(id);
    if (!mounted) return;
    setState(() {
      final index = _items.indexWhere((row) => row['id'] == item['id']);
      if (index >= 0) {
        final copy = Map<String, dynamic>.from(_items[index]);
        copy['read_at'] = DateTime.now().toUtc().toIso8601String();
        _items = [..._items]..[index] = copy;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isOwner = auth.user?.getBoolValue('is_system_owner') ?? false;
    final scheme = Theme.of(context).colorScheme;

    if (!isOwner) {
      return Scaffold(
        appBar: AppBar(title: const Text('Critical Alerts')),
        body: const OwnerStatePanel.error(
          title: 'دەستگەیشتن ڕێگەپێنەدراوە',
          message: 'تەنها System Owner دەتوانێت ئەم ئاگادارکردنەوانە ببینێت.',
          actionLabel: null,
        ),
      );
    }

    if (_loading && _items.isEmpty) {
      return const Scaffold(body: SafeArea(child: OwnerStatePanel.loading()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Critical Alerts'),
        actions: [
          IconButton(
            tooltip: 'نوێکردنەوە',
            onPressed: _loading ? null : () => unawaited(_load()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            const AppSectionHeader(
              title: 'ئاگادارکردنەوە گرنگەکان',
              subtitle: 'AutoPilot Attention، Dead-letter، Failed و Critical Risk',
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(
                  color: scheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_items.isEmpty)
              const OwnerStatePanel.empty(
                title: 'هیچ ئاگادارکردنەوەیەکی گرنگ نییە',
                message: 'دۆخی AutoPilot ئێستا ئارامە.',
              )
            else
              for (final item in _items) ...[
                Builder(
                  builder: (context) {
                    final critical =
                        item['event_type']?.toString() == 'owner_autopilot_critical';
                    final unread = item['read_at'] == null;
                    final tint = critical ? scheme.error : const Color(0xFF0B9270);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => unawaited(_markRead(item)),
                        child: AppSurface(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: tint.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  critical
                                      ? Icons.crisis_alert_rounded
                                      : Icons.check_circle_rounded,
                                  color: tint,
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item['title']?.toString() ?? 'ZHIROX Alert',
                                            style: TextStyle(
                                              fontWeight: unread
                                                  ? FontWeight.w900
                                                  : FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        if (unread)
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: tint,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      item['body']?.toString() ?? '',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(height: 1.6),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _when(item['created_at']),
                                      style: Theme.of(context).textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
          ],
        ),
      ),
    );
  }
}
