import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/services/dashboard_recent_activity.dart';

void main() {
  group('dashboard recent activity', () {
    final now = DateTime.utc(2026, 9, 17, 12);

    test('keeps only debt/payment activity from the inclusive last 24 hours', () {
      final rows = <Map<String, dynamic>>[
        {
          'id': 'old-debt',
          'event_type': 'debt',
          'created_at': now.subtract(const Duration(hours: 24, seconds: 1)).toIso8601String(),
        },
        {
          'id': 'boundary-debt',
          'event_type': 'debt',
          'created_at': now.subtract(const Duration(hours: 24)).toIso8601String(),
        },
        {
          'id': 'payment',
          'event_type': 'payment',
          'created_at': now.subtract(const Duration(hours: 2)).toIso8601String(),
        },
        {
          'id': 'new-debt',
          'event_type': 'debt',
          'created_at': now.subtract(const Duration(minutes: 5)).toIso8601String(),
        },
        {
          'id': 'other',
          'event_type': 'profile_update',
          'created_at': now.subtract(const Duration(minutes: 1)).toIso8601String(),
        },
      ];

      final result = filterAndSortRecentDashboardActivity(rows, now: now);

      expect(
        result.map((row) => row['id']).toList(),
        ['new-debt', 'payment', 'boundary-debt'],
      );
    });

    test('sorts newest first and uses id as a deterministic tie-breaker', () {
      final timestamp = now.subtract(const Duration(minutes: 10)).toIso8601String();
      final rows = <Map<String, dynamic>>[
        {'id': 'a', 'event_type': 'debt', 'created_at': timestamp},
        {'id': 'c', 'event_type': 'payment', 'created_at': timestamp},
        {'id': 'b', 'event_type': 'debt', 'created_at': timestamp},
      ];

      final result = filterAndSortRecentDashboardActivity(rows, now: now);

      expect(result.map((row) => row['id']).toList(), ['c', 'b', 'a']);
    });
  });
}
