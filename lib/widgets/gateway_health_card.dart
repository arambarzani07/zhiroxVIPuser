import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zhirox/services/hikvision_admin_service.dart';

/// Uses server time, so a wrong phone clock cannot report a gateway outage.
class GatewayHealthCard extends StatefulWidget {
  const GatewayHealthCard({super.key, this.showHistory = false, this.onOpen});
  final bool showHistory;
  final VoidCallback? onOpen;
  @override
  State<GatewayHealthCard> createState() => _GatewayHealthCardState();
}

class _GatewayHealthCardState extends State<GatewayHealthCard>
    with WidgetsBindingObserver {
  GatewayHealth? _health;
  Timer? _timer;
  bool _busy = false;
  bool _saving = false;
  bool _error = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    _timer?.cancel();
    unawaited(_load());
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_load()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _timer?.cancel();
    }
  }

  Future<void> _load() async {
    if (_busy) return;
    _busy = true;
    try {
      final health = await HikvisionAdminService.gatewayHealth();
      if (!mounted) return;
      final previous = _health;
      setState(() {
        _health = health;
        _error = false;
      });
      if (previous != null &&
          previous.status != health.status &&
          (health.status == 'offline' ||
              (health.status == 'online' && previous.status == 'offline'))) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              health.status == 'online'
                  ? 'Gateway دووبارە چالاک بوو'
                  : health.label,
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      _busy = false;
    }
  }

  Future<void> _setAlerts(bool enabled) async {
    setState(() => _saving = true);
    try {
      await HikvisionAdminService.setGatewayAlerts(enabled);
      await _load();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ڕێکخستنی ئاگاداری پاشەکەوت نەکرا؛ دووبارە هەوڵ بدە.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _date(dynamic value) {
    final d = DateTime.tryParse('$value')?.toLocal();
    if (d == null) return 'هێشتا نییە';
    String pad(int x) => '$x'.padLeft(2, '0');
    return '${d.year}/${pad(d.month)}/${pad(d.day)} ${pad(d.hour)}:${pad(d.minute)}:${pad(d.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final health = _health;
    if (!widget.showHistory &&
        (health == null ||
            health.status == 'disabled' ||
            health.status == 'unpaired'))
      return const SizedBox.shrink();
    final color = _error
        ? Colors.grey
        : health?.status == 'online'
        ? Colors.green
        : health?.status == 'offline'
        ? Colors.deepOrange
        : Colors.grey;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                health?.status == 'online' && !_error
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
                color: color,
              ),
              title: Text(
                _error
                    ? 'نەتوانرا دۆخی Gateway نوێ بکرێتەوە'
                    : health?.label ?? 'بارکردنی دۆخی Gateway…',
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
              subtitle: Text('کۆتا پەیام: ${_date(health?.lastSeenAt)}'),
              onTap: widget.onOpen,
              trailing: IconButton(
                onPressed: _saving ? null : _load,
                icon: const Icon(Icons.refresh),
                tooltip: 'نوێکردنەوە',
              ),
            ),
            if (health?.status == 'offline' && !_error)
              const Text(
                'زیاتر لە سێ خولەکە پەیام نەهاتووە. PC، ئینتەرنێت و بەرنامەی Gateway بپشکنە.',
              ),
            if (widget.showHistory && health != null) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('ئاگاداری پچڕان و چالاکبوونەوە'),
                subtitle: const Text(
                  'ڕووداوەکان لە سێرڤەر تۆمار دەکرێن؛ لە ئەپ دەتوانیت بیانبینیت.',
                ),
                value: health.alertsEnabled,
                onChanged: _saving ? null : _setAlerts,
              ),
              const Text(
                'پەیوەندی چالاک بە تەنها دروستی کلیپ پشتڕاست ناکاتەوە.',
              ),
              const SizedBox(height: 8),
              const Text(
                'مێژووی پەیوەندی Gateway',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              if (health.events.isEmpty)
                const Text('هێشتا ڕووداوی پچڕان یان گەڕانەوە تۆمار نەکراوە.'),
              for (final event in health.events)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    event['state'] == 'online'
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_rounded,
                    color: event['state'] == 'online'
                        ? Colors.green
                        : Colors.deepOrange,
                  ),
                  title: Text(
                    event['state'] == 'online'
                        ? 'Gateway دووبارە چالاک بوو'
                        : 'پەیوەندی Gateway پچڕا',
                  ),
                  subtitle: Text(_date(event['occurred_at'])),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
