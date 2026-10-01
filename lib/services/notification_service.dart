import 'dart:async';
import 'dart:convert';

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

  static const String _buildOneSignalAppId = String.fromEnvironment(
    'ONESIGNAL_APP_ID',
  );

  static final StreamController<Map<String, dynamic>>
      _remoteNotificationClickController =
      StreamController<Map<String, dynamic>>.broadcast();

  static StreamSubscription<AuthState>? _authSubscription;
  static RealtimeChannel? _realtimeChannel;
  static String? _realtimeRecipientUserId;
  static final Set<String> _realtimeSeenEventIds = <String>{};
  static String? _oneSignalExternalId;
  static String? _runtimeOneSignalAppId;
  static bool _initialized = false;
  static bool _timezoneReady = false;
  static bool _oneSignalReady = false;

  static String get _effectiveOneSignalAppId {
    final buildValue = _buildOneSignalAppId.trim();
    if (buildValue.isNotEmpty) return buildValue;
    return _runtimeOneSignalAppId?.trim() ?? '';
  }

  static bool get isOneSignalConfigured =>
      !kIsWeb && _effectiveOneSignalAppId.isNotEmpty;

  static bool get isOneSignalReady => _oneSignalReady;

  static Stream<Map<String, dynamic>> get remoteNotificationClicks =>
      _remoteNotificationClickController.stream;

  static String? get pushSubscriptionId {
    if (!_oneSignalReady) return null;
    return OneSignal.User.pushSubscription.id;
  }

  static Future<String> _resolveOneSignalAppId() async {
    final buildValue = _buildOneSignalAppId.trim();
    if (buildValue.isNotEmpty) return buildValue;
    if (kIsWeb) return '';

    final cached = _runtimeOneSignalAppId?.trim() ?? '';
    if (cached.isNotEmpty) return cached;

    try {
      await PBService.ensureInitialized();
      final response = await PBService.client.functions.invoke(
        'onesignal-config',
        body: const <String, dynamic>{},
      );
      final data = response.data;
      if (data is Map) {
        final appId = data['app_id']?.toString().trim() ?? '';
        if (appId.isNotEmpty) {
          _runtimeOneSignalAppId = appId;
          return appId;
        }
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('OneSignal runtime configuration failed: $error');
      }
    }
    return '';
  }

  /// Initialize local notifications, Supabase Realtime fallback and OneSignal.
  ///
  /// Realtime is intentionally independent from OneSignal. This lets the app
  /// receive notifications while it is running even when the current iOS
  /// signing provider does not expose an APNs credential. iOS can still
  /// suspend a background/force-quit app, so APNs remains required for a
  /// reliable remote wake-up.
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

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload?.trim() ?? '';
        if (payload.isEmpty) return;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map) {
            _remoteNotificationClickController.add(
              Map<String, dynamic>.from(decoded),
            );
          }
        } catch (_) {}
      },
    );
    _initialized = true;

    if (kIsWeb) return;

    try {
      await PBService.ensureInitialized();
      final currentUserId = PBService.client.auth.currentUser?.id;
      await _syncRealtimeIdentity(currentUserId);

      _authSubscription ??=
          PBService.client.auth.onAuthStateChange.listen((state) {
        final userId = state.session?.user.id;
        unawaited(_syncRealtimeIdentity(userId));
        unawaited(_syncOneSignalIdentity(userId));
      });
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Realtime notification initialization failed: $error');
      }
    }

    final appId = await _resolveOneSignalAppId();
    if (appId.isEmpty) return;

    try {
      await OneSignal.initialize(appId);
      _oneSignalReady = true;

      OneSignal.Notifications.addClickListener((event) {
        final data = event.notification.additionalData;
        if (data == null || data.isEmpty) return;
        _remoteNotificationClickController.add(
          Map<String, dynamic>.from(data),
        );
      });

      await _syncOneSignalIdentity(PBService.client.auth.currentUser?.id);
    } catch (error) {
      _oneSignalReady = false;
      if (kDebugMode) {
        debugPrint('OneSignal initialization failed: $error');
      }
    }
  }

  static Future<void> _syncRealtimeIdentity(String? userId) async {
    final normalized = userId?.trim() ?? '';

    if (normalized.isEmpty) {
      final oldChannel = _realtimeChannel;
      _realtimeChannel = null;
      _realtimeRecipientUserId = null;
      _realtimeSeenEventIds.clear();
      if (oldChannel != null) {
        try {
          await PBService.client.removeChannel(oldChannel);
        } catch (_) {}
      }
      return;
    }

    if (_realtimeRecipientUserId == normalized && _realtimeChannel != null) {
      return;
    }

    final oldChannel = _realtimeChannel;
    if (oldChannel != null) {
      try {
        await PBService.client.removeChannel(oldChannel);
      } catch (_) {}
    }

    _realtimeSeenEventIds.clear();
    _realtimeRecipientUserId = normalized;

    final channel = PBService.client.channel(
      'app-notifications-$normalized',
    );
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'app_realtime_notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'recipient_user_id',
        value: normalized,
      ),
      callback: (payload) {
        unawaited(_handleRealtimeRecord(payload.newRecord));
      },
    );
    channel.subscribe();
    _realtimeChannel = channel;

    // Realtime does not replay inserts that happened while iOS had the app
    // suspended. Catch up on recent undelivered rows whenever the app starts.
    await _drainPendingRealtime(normalized);
  }

  static Future<void> _drainPendingRealtime(String userId) async {
    try {
      final since = DateTime.now().toUtc().subtract(const Duration(days: 1));
      final rows = await PBService.client
          .from('app_realtime_notifications')
          .select()
          .eq('recipient_user_id', userId)
          .gt('created_at', since.toIso8601String())
          .order('created_at', ascending: true)
          .limit(100);

      for (final row in rows) {
        final record = Map<String, dynamic>.from(row);
        if (record['delivered_at'] != null) continue;
        await _handleRealtimeRecord(record);
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Realtime notification catch-up failed: $error');
      }
    }
  }

  static Future<void> _handleRealtimeRecord(
    Map<String, dynamic> record,
  ) async {
    final currentUserId = PBService.client.auth.currentUser?.id;
    final recipient = record['recipient_user_id']?.toString() ?? '';
    if (currentUserId == null || recipient != currentUserId) return;
    if (record['delivered_at'] != null) return;

    final eventId = record['id']?.toString().trim() ?? '';
    if (eventId.isEmpty || !_realtimeSeenEventIds.add(eventId)) return;

    final expiresAt = DateTime.tryParse(record['expires_at']?.toString() ?? '');
    if (expiresAt != null && expiresAt.isBefore(DateTime.now().toUtc())) {
      await _markRealtimeDelivered(currentUserId, eventId);
      return;
    }

    final title = record['title']?.toString().trim() ?? '';
    final body = record['body']?.toString().trim() ?? '';
    if (title.isEmpty || body.isEmpty) return;

    final rawData = record['data'];
    final clickData = <String, dynamic>{
      if (rawData is Map) ...Map<String, dynamic>.from(rawData),
      'event_id': eventId,
      'event_type': record['event_type']?.toString() ?? 'general',
    };

    await show(
      title: title,
      body: body,
      id: _notificationIdForEvent(eventId),
      payload: clickData,
    );
    await _markRealtimeDelivered(currentUserId, eventId);
  }

  static int _notificationIdForEvent(String eventId) {
    final compact = eventId.replaceAll('-', '');
    if (compact.length >= 8) {
      final parsed = int.tryParse(compact.substring(0, 8), radix: 16);
      if (parsed != null) return parsed & 0x7fffffff;
    }
    return eventId.hashCode & 0x7fffffff;
  }

  static Future<void> _markRealtimeDelivered(
    String userId,
    String eventId,
  ) async {
    try {
      await PBService.client
          .from('app_realtime_notifications')
          .update({'delivered_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', eventId)
          .eq('recipient_user_id', userId);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Could not mark realtime notification delivered: $error');
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
        final granted = await OneSignal.Notifications.requestPermission(true);
        if (granted) return true;
      } catch (_) {}
    }

    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Check if notification permission is granted.
  static Future<bool> isPermissionGranted() async {
    if (_oneSignalReady && OneSignal.Notifications.permission) return true;
    return await Permission.notification.isGranted;
  }

  /// Show a local notification.
  static Future<void> show({
    required String title,
    required String body,
    int id = 0,
    Map<String, dynamic>? payload,
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

    await _plugin.show(
      id,
      title,
      body,
      details,
      payload: payload == null ? null : jsonEncode(payload),
    );
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
