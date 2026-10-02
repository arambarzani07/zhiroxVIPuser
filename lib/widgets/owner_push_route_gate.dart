import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zhirox/screens/auth/owner_critical_alerts_screen.dart';
import 'package:zhirox/services/notification_service.dart';

class OwnerPushRouteGate extends StatefulWidget {
  const OwnerPushRouteGate({super.key, required this.child});

  final Widget child;

  @override
  State<OwnerPushRouteGate> createState() => _OwnerPushRouteGateState();
}

class _OwnerPushRouteGateState extends State<OwnerPushRouteGate> {
  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool _openingCriticalAlerts = false;

  @override
  void initState() {
    super.initState();
    _subscription = NotificationService.remoteNotificationClicks.listen((data) {
      NotificationService.consumePendingRemoteClick();
      _route(data);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = NotificationService.consumePendingRemoteClick();
      if (pending != null) _route(pending);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _route(Map<String, dynamic> data) {
    final route = data['zhirox_route']?.toString() ?? '';
    final type = data['type']?.toString() ?? '';
    final shouldOpenCriticalAlerts =
        route == 'owner_critical_alerts' ||
        type == 'owner_autopilot_critical' ||
        type == 'owner_autopilot_recovery';

    if (!shouldOpenCriticalAlerts || _openingCriticalAlerts || !mounted) return;
    _openingCriticalAlerts = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _openingCriticalAlerts = false;
        return;
      }
      try {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const OwnerCriticalAlertsScreen(),
          ),
        );
      } finally {
        _openingCriticalAlerts = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
