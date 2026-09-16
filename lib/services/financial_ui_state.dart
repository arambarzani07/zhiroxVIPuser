enum FinancialPaymentStep { target, amount, review }

int countActiveFinancialFilters({
  required String query,
  required bool hasDateRange,
  required String typeFilter,
}) {
  var count = 0;
  if (query.trim().isNotEmpty) count++;
  if (hasDateRange) count++;
  final normalizedType = typeFilter.trim();
  if (normalizedType.isNotEmpty && normalizedType != 'all') count++;
  return count;
}

bool shouldExpandFinancialFilters({
  required bool requestedExpanded,
  required int activeFilterCount,
}) =>
    requestedExpanded || activeFilterCount > 0;

FinancialPaymentStep resolveFinancialPaymentStep({
  required bool targetSelected,
  required double amount,
  required double maximum,
  required bool reviewRequested,
}) {
  if (!targetSelected) return FinancialPaymentStep.target;
  final amountValid = amount.isFinite &&
      maximum.isFinite &&
      amount > 0 &&
      maximum > 0 &&
      amount <= maximum + 0.0001;
  if (!amountValid) return FinancialPaymentStep.amount;
  return reviewRequested
      ? FinancialPaymentStep.review
      : FinancialPaymentStep.amount;
}
