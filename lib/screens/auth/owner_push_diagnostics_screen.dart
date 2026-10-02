import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/notification_service.dart';
import 'package:zhirox/widgets/app_design.dart';

class OwnerPushDiagnosticsScreen extends StatefulWidget {
  const OwnerPushDiagnosticsScreen({super.key});

  @override
  State<OwnerPushDiagnosticsScreen> createState() =>
      _OwnerPushDiagnosticsScreenState();
}

class _OwnerPushDiagnosticsScreenState
    extends State<OwnerPushDiagnosticsScreen> {
  bool _loading = true;
  bool _working = false;
  String? _error;
  Map<String, dynamic> _state = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await NotificationService.pushDiagnostics();
      if (!mounted) return;
      setState(() => _state = state);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestPermission() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await NotificationService.requestPermission();
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Widget _row(
    BuildContext context, {
    required String title,
    required String value,
    required bool ok,
    IconData? icon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final tint = ok ? const Color(0xFF0B9270) : scheme.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon ?? (ok ? Icons.check_circle_rounded : Icons.error_rounded),
              size: 21, color: tint),
          const SizedBox(width: 9),
          Expanded(
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.left,
              style: TextStyle(
                color: ok ? scheme.onSurfaceVariant : tint,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isOwner = auth.user?.getBoolValue('is_system_owner') ?? false;
    final scheme = Theme.of(context).colorScheme;

    if (!isOwner) {
      return Scaffold(
        appBar: AppBar(title: const Text('Push Diagnostics')),
        body: const OwnerStatePanel.error(
          title: 'دەستگەیشتن ڕێگەپێنەدراوە',
          message: 'تەنها System Owner دەتوانێت دۆخی Push ببینێت.',
          actionLabel: null,
        ),
      );
    }

    final supported = _state['supported'] == true;
    final initialized = _state['initialized'] == true;
    final permission = _state['permission'] == true;
    final identityLinked = _state['identity_linked'] == true;
    final subscriptionReady = _state['subscription_ready'] == true;
    final healthy = supported && initialized && permission && identityLinked && subscriptionReady;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Push Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'نوێکردنەوە',
            onPressed: _loading || _working ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            AppSurface(
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: (healthy ? const Color(0xFF0B9270) : scheme.error)
                          .withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      healthy
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_off_rounded,
                      color: healthy ? const Color(0xFF0B9270) : scheme.error,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          healthy ? 'Native Push ئامادەیە' : 'Push پێویستی بە پشکنین هەیە',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          healthy
                              ? 'ئەم ئامێرە بۆ Owner push subscription تۆمارکراوە.'
                              : 'خوارەوە ببینە کام بەش هێشتا تەواو نییە.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppSurface(
              child: Column(
                children: [
                  _row(
                    context,
                    title: 'Native platform',
                    value: supported ? (_state['platform']?.toString() ?? '—') : 'ناپشتیوانیکراو',
                    ok: supported,
                    icon: Icons.phone_iphone_rounded,
                  ),
                  const Divider(height: 1),
                  _row(
                    context,
                    title: 'OneSignal SDK',
                    value: initialized ? 'چالاکە' : 'چالاک نییە',
                    ok: initialized,
                    icon: Icons.hub_rounded,
                  ),
                  const Divider(height: 1),
                  _row(
                    context,
                    title: 'مۆڵەتی Notification',
                    value: permission ? 'ڕێگەپێدراوە' : 'ڕێگەپێنەدراوە',
                    ok: permission,
                    icon: Icons.verified_user_rounded,
                  ),
                  const Divider(height: 1),
                  _row(
                    context,
                    title: 'Owner identity',
                    value: identityLinked ? 'پەیوەستە' : 'پەیوەست نییە',
                    ok: identityLinked,
                    icon: Icons.person_pin_circle_rounded,
                  ),
                  const Divider(height: 1),
                  _row(
                    context,
                    title: 'Push subscription',
                    value: subscriptionReady
                        ? (_state['subscription_hint']?.toString() ?? 'ئامادەیە')
                        : 'هێشتا دروست نەبووە',
                    ok: subscriptionReady,
                    icon: Icons.cloud_done_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ناسنامەی iOS', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text('Bundle ID: ${_state['bundle_id'] ?? 'com.karoxghafoor.zhirox.owner'}'),
                  const SizedBox(height: 5),
                  Text('OneSignal App: ${_state['app_id_hint']?.toString().isNotEmpty == true ? _state['app_id_hint'] : '—'}'),
                  const SizedBox(height: 10),
                  Text(
                    'بۆ push ـی iPhone کاتێک ئەپ داخراوە، OneSignal ـەکە دەبێت APNs credential ـی گونجاو بە همین Owner Bundle ID ـەوە هەبێت.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.6),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: scheme.error, fontWeight: FontWeight.w700)),
            ],
            if (_loading || _working) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _working ? null : _requestPermission,
                icon: const Icon(Icons.notifications_active_rounded),
                label: const Text('چالاککردنی مۆڵەتی Push'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
