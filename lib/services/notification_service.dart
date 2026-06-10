import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Initialize the notification plugin (call once in main.dart)
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
  }

  /// Request notification permission (Android 13+ & iOS)
  static Future<bool> requestPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Check if notification permission is granted
  static Future<bool> isPermissionGranted() async {
    return await Permission.notification.isGranted;
  }

  /// Show a local notification
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

  /// Show debt created notification
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

  /// Show due date reminder notification
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
