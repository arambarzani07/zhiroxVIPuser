import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:zhirox/services/pb_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _oneSignalAppId = String.fromEnvironment(
    'ONESIGNAL_APP_ID',
  );

  static final StreamController<Map<String, dynamic>>
      _remoteNotificationClickController =
      StreamController<Map<String, dynamic>>.broadcast();

  static StreamSubscription<AuthState>? _authSubscription;
  static String? _oneSignalExternalId;
  static bool _initialized = false;
  static bool _timezoneReady = false;
  static bool _oneSignalReady = false;

  static bool get isOneSignalConfigured =>
      !kIsWeb && _oneSignalAppId.trim().isNotEmpty;

  static bool get isOneSignalReady => _oneSignalReady;

  static Stream<Map<String, dynamic>> get remoteNotificationClicks =>
      _remoteNotificationClickController.stream;

  static String? get pushSubscriptionId {
    if (!_oneSignalReady) return null;
    return OneSignal.User.pushSubscription.id;
  }

  /// Initialize local notifications and OneSignal push notifications.
  ///
  /// OneSignal is enabled only when the release/build provides:
  /// --dart-define=ONESIGNAL_APP_ID=<app-id>
  static Future<void> init() async {
    if (_initialized) return;

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

    if (!isOneSignalConfigured) return;

    try {
      await OneSignal.initialize(_oneSignalAppId.trim());
      _oneSignalReady = true;

      OneSignal.Notifications.addClickListener((event) {
        final data = event.notification.additionalData;
        if (data == null || data.isEmpty) return;
        _remoteNotificationClickController.add(
          Map<String, dynamic>.from(data),
        );
      });

      await PBService.ensureInitialized();
      await _syncOneSignalIdentity(PBService.client.auth.currentUser?.id);

      _authSubscription ??=
          PBService.client.auth.onAuthStateChange.listen((state) {
        unawaited(_syncOneSignalIdentity(state.session?.user.id));
      });
    } catch (error) {
      _oneSignalReady = false;
      if (kDebugMode) {
        debugPrint('OneSignal initialization failed: $error');
      }
    }
  }

  static Future<void> _syncOneSignalIdentity(String? userId) async {
    if (!_oneSignalReady) return;

    final normalized = userId?.trim() ?? '';
    if (normalized.isEmpty) {
      if (_oneSignalExternalId != null) {
        try {
          await OneSignal.logout();
        } catch (_) {}
        _oneSignalExternalId = null;
      }
      return;
    }

    if (_oneSignalExternalId == normalized) return;

    try {
      await OneSignal.login(normalized);
      _oneSignalExternalId = normalized;
      await OneSignal.User.addTags({
        'app_edition': 'user',
        'platform': defaultTargetPlatform.name,
      });
    } catch (error) {
      if (kDebugMode) {
        debugPrint('OneSignal user sync failed: $error');
      }
    }
  }

  /// Request notification permission (Android 13+ & iOS).
  static Future<bool> requestPermission() async {
    if (_oneSignalReady) {
      try {
        return await OneSignal.Notifications.requestPermission(true);
      } catch (_) {}
    }

    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Check if notification permission is granted.
  static Future<bool> isPermissionGranted() async {
    if (_oneSignalReady) {
      return OneSignal.Notifications.permission;
    }
    return await Permission.notification.isGranted;
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

  /// Schedule one generic expiry summary. Keep the IDs in a separate range
  /// so cancelling them never affects financial reminders.
  static Future<void> scheduleExpiry({
    required int id,
    required DateTime when,
    required String body,
  }) async {
    await init();
    if (!_timezoneReady) {
      tzdata.initializeTimeZones();
      _timezoneReady = true;
    }
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'zhirox_expiry',
        'بەرواری کاڵاکان',
        channelDescription: 'بیرخستنەوەی بەسەرچوونی کاڵا',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );
    await _plugin.zonedSchedule(
      id,
      'ئاگادارکردنەوەی بەرواری کاڵا',
      body,
      tz.TZDateTime.from(when.toUtc(), tz.UTC),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancelExpirySchedules({
    required int firstId,
    required int limit,
  }) async {
    await init();
    final pending = await _plugin.pendingNotificationRequests();
    for (final notice in pending) {
      if (notice.id >= firstId && notice.id < firstId + limit) {
        await _plugin.cancel(notice.id);
      }
    }
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
