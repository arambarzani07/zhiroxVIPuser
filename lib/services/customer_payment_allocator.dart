class CustomerPaymentDebt {
  final String id;
  final double remaining;
  final DateTime sortAt;

  const CustomerPaymentDebt({
    required this.id,
    required this.remaining,
    required this.sortAt,
  });
}

class CustomerPaymentAllocation {
  final String debtId;
  final double amount;

  const CustomerPaymentAllocation({
    required this.debtId,
    required this.amount,
  });
}

List<CustomerPaymentAllocation> allocateCustomerPayment({
  required double amount,
  required List<CustomerPaymentDebt> debts,
}) {
  if (!amount.isFinite || amount <= 0) {
    throw ArgumentError.value(amount, 'amount', 'must be greater than zero');
  }

  final open = debts
      .where((debt) => debt.remaining.isFinite && debt.remaining > 0)
      .toList(growable: false)
    ..sort((a, b) {
      final byDate = a.sortAt.compareTo(b.sortAt);
      if (byDate != 0) return byDate;
      return a.id.compareTo(b.id);
    });

  final total = open.fold<double>(0, (sum, debt) => sum + debt.remaining);
  const epsilon = 0.0001;
  if (amount > total + epsilon) {
    throw ArgumentError.value(
      amount,
      'amount',
      'cannot exceed the customer open balance',
    );
  }

  var left = amount;
  final result = <CustomerPaymentAllocation>[];
  for (final debt in open) {
    if (left <= epsilon) break;
    final allocation = left < debt.remaining ? left : debt.remaining;
    if (allocation > epsilon) {
      result.add(
        CustomerPaymentAllocation(
          debtId: debt.id,
          amount: allocation,
        ),
      );
      left -= allocation;
    }
  }

  if (left > epsilon) {
    throw StateError('customer payment allocation did not consume full amount');
  }
  return result;
}
