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

  const FinancialRangeSummary({
    required this.debtTotal,
    required this.paymentTotal,
    required this.debtCount,
    required this.paymentCount,
  });

  double get net => debtTotal - paymentTotal;
  int get transactionCount => debtCount + paymentCount;
}

DateTime _dayOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool isWithinFinancialDateRange(
  DateTime value, {
  required DateTime start,
  required DateTime end,
}) {
  final day = _dayOnly(value);
  var first = _dayOnly(start);
  var last = _dayOnly(end);
  if (last.isBefore(first)) {
    final swap = first;
    first = last;
    last = swap;
  }
  return !day.isBefore(first) && !day.isAfter(last);
}

FinancialRangeSummary summarizeFinancialDateRange({
  required Iterable<FinancialRangeEntry> entries,
  required DateTime start,
  required DateTime end,
}) {
  var debtTotal = 0.0;
  var paymentTotal = 0.0;
  var debtCount = 0;
  var paymentCount = 0;

  for (final entry in entries) {
    if (!isWithinFinancialDateRange(entry.date, start: start, end: end)) {
      continue;
    }
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

  return FinancialRangeSummary(
    debtTotal: debtTotal,
    paymentTotal: paymentTotal,
    debtCount: debtCount,
    paymentCount: paymentCount,
  );
}
