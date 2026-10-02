import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zhirox/services/pb_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static final StreamController<Map<String, dynamic>>
      _remoteNotificationClickController =
      StreamController<Map<String, dynamic>>.broadcast();

  static bool _initialized = false;
  static bool _oneSignalInitialized = false;
  static String? _oneSignalUserId;
  static String? _oneSignalAppId;
  static Map<String, dynamic>? _pendingRemoteClick;
  static StreamSubscription<AuthState>? _authSubscription;

  static Stream<Map<String, dynamic>> get remoteNotificationClicks =>
      _remoteNotificationClickController.stream;

  static Map<String, dynamic>? consumePendingRemoteClick() {
    final pending = _pendingRemoteClick;
    _pendingRemoteClick = null;
    return pending == null ? null : Map<String, dynamic>.from(pending);
  }

  /// Initialize local notifications and the Owner native push channel.
  static Future<void> init() async {
    if (!_initialized) {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _plugin.initialize(settings);
      _initialized = true;
    }

    // Owner push setup is intentionally non-blocking. A transient OneSignal
    // or network failure must never prevent the app from launching.
    unawaited(_initializeOneSignalOwnerPush());
  }

  static bool get _supportsNativePush {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  static Future<void> _initializeOneSignalOwnerPush() async {
    if (!_supportsNativePush || _oneSignalInitialized) return;

    try {
      await PBService.ensureInitialized();
      final response = await PBService.client.functions.invoke(
        'onesignal-config',
        body: const <String, dynamic>{},
      );
      final data = response.data;
      if (data is! Map) return;
      final appId = (data['app_id'] ?? '').toString().trim();
      if (appId.isEmpty) return;

      await OneSignal.initialize(appId);
      _oneSignalAppId = appId;
      _oneSignalInitialized = true;

      OneSignal.Notifications.addClickListener((event) {
        final raw = event.notification.additionalData;
        final data = raw == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(raw);
        if (data.isEmpty) return;
        _pendingRemoteClick = data;
        _remoteNotificationClickController.add(data);
      });

      await _syncOneSignalIdentity(PBService.client.auth.currentUser?.id);
      _authSubscription ??= PBService.client.auth.onAuthStateChange.listen(
        (state) => unawaited(_syncOneSignalIdentity(state.session?.user.id)),
      );
    } catch (error) {
      debugPrint('Owner OneSignal initialization deferred: $error');
    }
  }

  static Future<void> _syncOneSignalIdentity(String? userId) async {
    if (!_oneSignalInitialized) return;
    final normalized = userId?.trim() ?? '';

    try {
      if (normalized.isEmpty) {
        if (_oneSignalUserId != null) {
          await OneSignal.logout();
          _oneSignalUserId = null;
        }
        return;
      }

      if (_oneSignalUserId == normalized) return;
      await OneSignal.login(normalized);
      _oneSignalUserId = normalized;
      await OneSignal.User.addTags({
        'app_edition': 'owner',
        'platform': defaultTargetPlatform.name,
      });
    } catch (error) {
      debugPrint('Owner OneSignal identity sync deferred: $error');
    }
  }

  static String _mask(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return '';
    if (clean.length <= 8) return clean;
    return '${clean.substring(0, 4)}••••${clean.substring(clean.length - 4)}';
  }

  /// Safe, secret-free diagnostic state for the Owner UI.
  static Future<Map<String, dynamic>> pushDiagnostics() async {
    await init();
    if (!_oneSignalInitialized) {
      await _initializeOneSignalOwnerPush();
    }

    final currentUserId = PBService.client.auth.currentUser?.id.trim() ?? '';
    final permission = await isPermissionGranted();
    String subscriptionId = '';
    if (_oneSignalInitialized) {
      subscriptionId = OneSignal.User.pushSubscription.id?.trim() ?? '';
    }

    return <String, dynamic>{
      'supported': _supportsNativePush,
      'initialized': _oneSignalInitialized,
      'permission': permission,
      'identity_linked':
          currentUserId.isNotEmpty && _oneSignalUserId == currentUserId,
      'subscription_ready': subscriptionId.isNotEmpty,
      'subscription_hint': _mask(subscriptionId),
      'app_id_hint': _mask(_oneSignalAppId ?? ''),
      'bundle_id': 'com.karoxghafoor.zhirox.owner',
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
    };
  }

  /// Request notification permission (Android 13+ & iOS).
  static Future<bool> requestPermission() async {
    if (!_oneSignalInitialized && _supportsNativePush) {
      await _initializeOneSignalOwnerPush();
    }

    if (_oneSignalInitialized && _supportsNativePush) {
      try {
        if (OneSignal.Notifications.permission) return true;
        final canRequest = await OneSignal.Notifications.canRequest();
        if (canRequest) {
          return await OneSignal.Notifications.requestPermission(false);
        }
        return OneSignal.Notifications.permission;
      } catch (error) {
        debugPrint('OneSignal permission request deferred: $error');
      }
    }

    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Check if notification permission is granted.
  static Future<bool> isPermissionGranted() async {
    if (_oneSignalInitialized && _supportsNativePush) {
      return OneSignal.Notifications.permission;
    }
    return Permission.notification.isGranted;
  }

  /// Show a local notification.
  static Future<void> show({
    required String title,
    required String body,
    int id = 0,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'zhirox_debts',
      'قەرزەکان',
      channelDescription: 'ئاگادارکردنەوەکانی قەرز',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(id, title, body, details);
  }

  /// Show debt created notification.
  static Future<void> showDebtCreated({
    required String customerName,
    required String amount,
    required String employeeName,
  }) async {
    await show(
      title: 'قەرزی نوێ زیادکرا',
      body: 'قەرزی $amount بۆ $customerName لەلایەن $employeeName',
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
    );
  }

  /// Show due date reminder notification.
  static Future<void> showDueReminder({
    required String customerName,
    required String amount,
    required String dueDate,
  }) async {
    await show(
      title: 'بیرکردنەوەی بەرواری دانەوە',
      body: 'قەرزی $amount بۆ $customerName - بەرواری دانەوە: $dueDate',
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
    );
  }
}
