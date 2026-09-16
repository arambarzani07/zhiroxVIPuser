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

  test('range summary exposes opening and closing ledger balances', () {
    final entries = <FinancialRangeEntry>[
      FinancialRangeEntry(
        kind: 'debt',
        amount: 20000,
        date: DateTime(2026, 8, 20),
      ),
      FinancialRangeEntry(
        kind: 'payment',
        amount: 5000,
        date: DateTime(2026, 8, 25),
      ),
      FinancialRangeEntry(
        kind: 'debt',
        amount: 13000,
        date: DateTime(2026, 9, 1),
      ),
      FinancialRangeEntry(
        kind: 'payment',
        amount: 4000,
        date: DateTime(2026, 9, 6),
      ),
      FinancialRangeEntry(
        kind: 'debt',
        amount: 2000,
        date: DateTime(2026, 9, 11, 23, 59),
      ),
      FinancialRangeEntry(
        kind: 'payment',
        amount: 1000,
        date: DateTime(2026, 9, 12),
      ),
    ];

    final summary = summarizeFinancialDateRange(
      entries: entries,
      start: DateTime(2026, 9, 1),
      end: DateTime(2026, 9, 11),
    );

    expect(summary.openingBalance, 15000);
    expect(summary.debtTotal, 15000);
    expect(summary.paymentTotal, 4000);
    expect(summary.closingBalance, 26000);
  });

  test('quick ranges resolve stable calendar boundaries', () {
    final now = DateTime(2026, 9, 16, 21, 33);

    final today = resolveFinancialQuickRange(FinancialQuickRange.today, now);
    expect(today.start, DateTime(2026, 9, 16));
    expect(today.end, DateTime(2026, 9, 16));

    final yesterday =
        resolveFinancialQuickRange(FinancialQuickRange.yesterday, now);
    expect(yesterday.start, DateTime(2026, 9, 15));
    expect(yesterday.end, DateTime(2026, 9, 15));

    final last7 =
        resolveFinancialQuickRange(FinancialQuickRange.last7Days, now);
    expect(last7.start, DateTime(2026, 9, 10));
    expect(last7.end, DateTime(2026, 9, 16));

    final last30 =
        resolveFinancialQuickRange(FinancialQuickRange.last30Days, now);
    expect(last30.start, DateTime(2026, 8, 18));
    expect(last30.end, DateTime(2026, 9, 16));

    final month =
        resolveFinancialQuickRange(FinancialQuickRange.thisMonth, now);
    expect(month.start, DateTime(2026, 9, 1));
    expect(month.end, DateTime(2026, 9, 16));

    final previousMonth =
        resolveFinancialQuickRange(FinancialQuickRange.lastMonth, now);
    expect(previousMonth.start, DateTime(2026, 8, 1));
    expect(previousMonth.end, DateTime(2026, 8, 31));

    final year = resolveFinancialQuickRange(FinancialQuickRange.thisYear, now);
    expect(year.start, DateTime(2026, 1, 1));
    expect(year.end, DateTime(2026, 9, 16));
  });
}
