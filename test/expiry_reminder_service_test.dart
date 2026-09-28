import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/features/expiry/expiry_reminder_service.dart';

void main() {
  test('schedules one summary per day at 30, 7 and 1 day before expiry', () {
    final planned = ExpiryReminderService.plan([
      {'expiry_date': '2027-01-31', 'resolved_at': null},
      {'expiry_date': '2027-01-31', 'resolved_at': null},
      {'expiry_date': '2027-01-30', 'resolved_at': '2026-11-01T00:00:00Z'},
    ], DateTime(2026, 12, 1));
    expect(planned.map((p) => p.when).toList(), [
      DateTime(2027, 1, 1, 9),
      DateTime(2027, 1, 24, 9),
      DateTime(2027, 1, 30, 9),
    ]);
    expect(planned.map((p) => p.count).toList(), [2, 2, 2]);
  });

  test('limits pending reminders to leave room for other app notices', () {
    final arrivals = List.generate(
      100,
      (i) => {
        'expiry_date': DateTime(
          2027,
          1,
          i + 31,
        ).toIso8601String().substring(0, 10),
        'resolved_at': null,
      },
    );
    final reminders = ExpiryReminderService.plan(
      arrivals,
      DateTime(2026, 12, 1),
    );
    expect(reminders.length, ExpiryReminderService.maxScheduledDays);
    expect(reminders.first.when.isBefore(reminders.last.when), isTrue);
  });
}
