import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/shared/user_profile_screen.dart';
import 'package:zhirox/services/notification_service.dart';

/// Converts trusted OneSignal notification payloads into in-app navigation.
///
/// Navigation is deliberately delayed until authentication has completed.
/// Tenant access is still enforced by the normal ZHIROX data layer; this
/// widget never treats notification payload data as authorization.
class RemoteNotificationGate extends StatefulWidget {
  final Widget child;

  const RemoteNotificationGate({super.key, required this.child});

  @override
  State<RemoteNotificationGate> createState() => _RemoteNotificationGateState();
}

class _RemoteNotificationGateState extends State<RemoteNotificationGate> {
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Map<String, dynamic>? _pending;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _subscription = NotificationService.remoteNotificationClicks.listen(
      (payload) {
        _pending = Map<String, dynamic>.from(payload);
        _scheduleOpen();
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  bool _asBool(Object? value) {
    if (value is bool) return value;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == 'true' || text == '1' || text == 'yes';
  }

  void _scheduleOpen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_openPending());
    });
  }

  Future<void> _openPending() async {
    if (_opening || !mounted) return;
    final payload = _pending;
    if (payload == null) return;

    final auth = context.read<AuthProvider>();
    if (auth.isInitializing || !auth.isLoggedIn) return;

    // Customer accounts already land on their own dashboard when the app is
    // opened from a push. The admin/employee experience can safely deep-link
    // into the selected customer profile.
    if (auth.userRole == 'customer') {
      _pending = null;
      return;
    }

    if (auth.userRole == 'employee' && !auth.canViewCustomers) {
      _pending = null;
      return;
    }

    final customerId = (payload['customer_id'] ?? '').toString().trim();
    if (customerId.isEmpty) {
      // Non-customer events such as sync_error intentionally open the app but
      // do not guess a destination.
      _pending = null;
      return;
    }

    final type = (payload['type'] ?? '').toString().trim();
    final openFinancialChat = _asBool(payload['open_financial_chat']) ||
        type == 'payment_received' ||
        type == 'new_debt' ||
        type == 'debt_limit_warning';

    _opening = true;
    _pending = null;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UserProfileScreen(
            userId: customerId,
            openFinancialChat: openFinancialChat,
          ),
        ),
      );
    } finally {
      _opening = false;
      if (_pending != null) _scheduleOpen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isInitializing && auth.isLoggedIn && _pending != null) {
      _scheduleOpen();
    }
    return widget.child;
  }
}
