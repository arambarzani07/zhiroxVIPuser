import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/services/financial_date_range_summary.dart';

void main() {
  test('date range includes both boundary days and both financial kinds', () {
    final entries = <FinancialRangeEntry>[
      FinancialRangeEntry(
        kind: 'debt',
        amount: 13000,
        date: DateTime(2026, 9, 1, 0, 1),
      ),
      FinancialRangeEntry(
        kind: 'payment',
        amount: 5000,
        date: DateTime(2026, 9, 5, 12, 30),
      ),
      FinancialRangeEntry(
        kind: 'debt',
        amount: 2000,
        date: DateTime(2026, 9, 11, 23, 59),
      ),
      FinancialRangeEntry(
        kind: 'payment',
        amount: 700,
        date: DateTime(2026, 8, 31, 23, 59),
      ),
      FinancialRangeEntry(
        kind: 'debt',
        amount: 900,
        date: DateTime(2026, 9, 12),
      ),
      FinancialRangeEntry(
        kind: 'system',
        amount: 999999,
        date: DateTime(2026, 9, 6),
      ),
    ];

    final summary = summarizeFinancialDateRange(
      entries: entries,
      start: DateTime(2026, 9, 1),
      end: DateTime(2026, 9, 11),
    );

    expect(summary.debtCount, 2);
    expect(summary.paymentCount, 1);
    expect(summary.debtTotal, 15000);
    expect(summary.paymentTotal, 5000);
    expect(summary.net, 10000);
  });

  test('date inclusion is day-based and inclusive at both ends', () {
    expect(
      isWithinFinancialDateRange(
        DateTime(2026, 9, 1, 0, 0),
        start: DateTime(2026, 9, 1, 18),
        end: DateTime(2026, 9, 11, 2),
      ),
      isTrue,
    );
    expect(
      isWithinFinancialDateRange(
        DateTime(2026, 9, 11, 23, 59, 59),
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 11),
      ),
      isTrue,
    );
    expect(
      isWithinFinancialDateRange(
        DateTime(2026, 9, 12),
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 11),
      ),
      isFalse,
    );
  });
}
