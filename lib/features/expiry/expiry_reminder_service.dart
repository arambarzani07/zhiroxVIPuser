import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhirox/services/notification_service.dart';

class ExpiryReminder {
  const ExpiryReminder(this.when, this.count);

  final DateTime when;
  final int count;
}

class ExpiryReminderService {
  ExpiryReminderService._();

  static const _notificationBase = 970000;
  // iOS keeps at most 64 pending notifications for an app. Leave capacity
  // for its other features, and aggregate products due on the same day.
  static const maxScheduledDays = 40;
  static const _scheduledIdsKey = 'expiry_scheduled_notification_ids';

  static String _enabledKey(String tenant, String user) =>
      'expiry_reminders_${tenant}_$user';

  static Future<bool> enabled(String tenant, String user) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey(tenant, user)) ?? true;
  }

  static List<ExpiryReminder> plan(
    List<Map<String, dynamic>> arrivals,
    DateTime now,
  ) {
    final grouped = <DateTime, int>{};
    for (final arrival in arrivals) {
      if (arrival['resolved_at'] != null) continue;
      final expires = DateTime.tryParse('${arrival['expiry_date'] ?? ''}');
      if (expires == null) continue;
      for (final days in const [30, 7, 1]) {
        // Calendar construction preserves 09:00 local time around DST.
        final when = DateTime(
          expires.year,
          expires.month,
          expires.day - days,
          9,
        );
        if (when.isAfter(now)) grouped[when] = (grouped[when] ?? 0) + 1;
      }
    }
    final dates = grouped.keys.toList()..sort();
    return [
      for (final date in dates.take(maxScheduledDays))
        ExpiryReminder(date, grouped[date]!),
    ];
  }

  static Future<void> clearDeviceSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_scheduledIdsKey) ?? const <String>[];
    for (final raw in ids) {
      final id = int.tryParse(raw);
      if (id != null) await NotificationService.cancelExpiry(id);
    }
    await prefs.remove(_scheduledIdsKey);
  }

  static Future<int> refresh({
    required String tenant,
    required String user,
    required List<Map<String, dynamic>> arrivals,
  }) async {
    await clearDeviceSchedules();
    if (!await enabled(tenant, user) ||
        !await NotificationService.isPermissionGranted())
      return 0;
    final prefs = await SharedPreferences.getInstance();
    final scheduled = <String>[];
    try {
      for (final reminder in plan(arrivals, DateTime.now())) {
        final id = _notificationBase + scheduled.length;
        await NotificationService.scheduleExpiry(
          id: id,
          when: reminder.when,
          body:
              '${reminder.count} بەرواری کاڵا نزیک دەبنەوە؛ بەشی چاودێری کاڵا بپشکنە.',
        );
        scheduled.add('$id');
        await prefs.setStringList(_scheduledIdsKey, scheduled);
      }
      return scheduled.length;
    } catch (_) {
      await clearDeviceSchedules();
      rethrow;
    }
  }

  static Future<int> setEnabled({
    required String tenant,
    required String user,
    required bool value,
    required List<Map<String, dynamic>> arrivals,
  }) async {
    if (value && !await NotificationService.requestPermission()) {
      throw const FormatException(
        'مۆڵەتی ئاگادارکردنەوە لە ڕێکخستنەکانی ئامێر چالاک بکە.',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey(tenant, user), value);
    try {
      return await refresh(tenant: tenant, user: user, arrivals: arrivals);
    } catch (_) {
      if (value) await prefs.setBool(_enabledKey(tenant, user), false);
      rethrow;
    }
  }
}
