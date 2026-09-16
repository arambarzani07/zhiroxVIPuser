/// One debt or repayment entry used by the selected financial date range.
class FinancialRangeEntry {
  final String kind;
  final double amount;
  final DateTime date;

  const FinancialRangeEntry({
    required this.kind,
    required this.amount,
    required this.date,
  });
}

class FinancialRangeSummary {
  final double debtTotal;
  final double paymentTotal;
  final int debtCount;
  final int paymentCount;
  final double openingBalance;

  const FinancialRangeSummary({
    required this.debtTotal,
    required this.paymentTotal,
    required this.debtCount,
    required this.paymentCount,
    required this.openingBalance,
  });

  double get net => debtTotal - paymentTotal;
  double get closingBalance => openingBalance + net;
  int get transactionCount => debtCount + paymentCount;
}

enum FinancialQuickRange {
  today,
  yesterday,
  last7Days,
  last30Days,
  thisMonth,
  lastMonth,
  thisYear,
}

class FinancialDateRange {
  final DateTime start;
  final DateTime end;

  const FinancialDateRange({required this.start, required this.end});
}

DateTime _dayOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

FinancialDateRange _normalizedRange(DateTime start, DateTime end) {
  var first = _dayOnly(start);
  var last = _dayOnly(end);
  if (last.isBefore(first)) {
    final swap = first;
    first = last;
    last = swap;
  }
  return FinancialDateRange(start: first, end: last);
}

/// Compares calendar days only; both the start and end days are included.
bool isWithinFinancialDateRange(
  DateTime value, {
  required DateTime start,
  required DateTime end,
}) {
  final day = _dayOnly(value);
  final range = _normalizedRange(start, end);
  return !day.isBefore(range.start) && !day.isAfter(range.end);
}

FinancialDateRange resolveFinancialQuickRange(
  FinancialQuickRange preset,
  DateTime now,
) {
  final today = _dayOnly(now);
  switch (preset) {
    case FinancialQuickRange.today:
      return FinancialDateRange(start: today, end: today);
    case FinancialQuickRange.yesterday:
      final yesterday = today.subtract(const Duration(days: 1));
      return FinancialDateRange(start: yesterday, end: yesterday);
    case FinancialQuickRange.last7Days:
      return FinancialDateRange(
        start: today.subtract(const Duration(days: 6)),
        end: today,
      );
    case FinancialQuickRange.last30Days:
      return FinancialDateRange(
        start: today.subtract(const Duration(days: 29)),
        end: today,
      );
    case FinancialQuickRange.thisMonth:
      return FinancialDateRange(
        start: DateTime(today.year, today.month, 1),
        end: today,
      );
    case FinancialQuickRange.lastMonth:
      final firstOfThisMonth = DateTime(today.year, today.month, 1);
      final lastOfPreviousMonth =
          firstOfThisMonth.subtract(const Duration(days: 1));
      return FinancialDateRange(
        start: DateTime(
          lastOfPreviousMonth.year,
          lastOfPreviousMonth.month,
          1,
        ),
        end: lastOfPreviousMonth,
      );
    case FinancialQuickRange.thisYear:
      return FinancialDateRange(
        start: DateTime(today.year, 1, 1),
        end: today,
      );
  }
}

FinancialRangeSummary summarizeFinancialDateRange({
  required Iterable<FinancialRangeEntry> entries,
  required DateTime start,
  required DateTime end,
}) {
  final range = _normalizedRange(start, end);
  var debtTotal = 0.0;
  var paymentTotal = 0.0;
  var debtCount = 0;
  var paymentCount = 0;
  var openingBalance = 0.0;

  for (final entry in entries) {
    if (entry.kind != 'debt' && entry.kind != 'payment') continue;

    final day = _dayOnly(entry.date);
    if (day.isBefore(range.start)) {
      openingBalance += entry.kind == 'payment' ? -entry.amount : entry.amount;
      continue;
    }
    if (day.isAfter(range.end)) continue;

    switch (entry.kind) {
      case 'debt':
        debtTotal += entry.amount;
        debtCount++;
        break;
      case 'payment':
        paymentTotal += entry.amount;
        paymentCount++;
        break;
    }
  }

  if (openingBalance.abs() < 0.000001) openingBalance = 0;

  return FinancialRangeSummary(
    debtTotal: debtTotal,
    paymentTotal: paymentTotal,
    debtCount: debtCount,
    paymentCount: paymentCount,
    openingBalance: openingBalance,
  );
}
