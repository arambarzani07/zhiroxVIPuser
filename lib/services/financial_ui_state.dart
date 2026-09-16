/// Presentation state for the single-sheet customer payment flow.
enum FinancialPaymentStep { target, amount, review }

/// Counts the independent filter dimensions currently narrowing Financial Chat.
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

/// Active filters keep the compact filter panel visible until they are cleared.
bool shouldExpandFinancialFilters({
  required bool requestedExpanded,
  required int activeFilterCount,
}) =>
    requestedExpanded || activeFilterCount > 0;

/// Resolves which payment step should be emphasized without changing data.
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
