import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/services/customer_payment_allocator.dart';

void main() {
  test('spreads a full customer payment across every open debt oldest first', () {
    final allocations = allocateCustomerPayment(
      amount: 21000,
      debts: [
        CustomerPaymentDebt(
          id: 'newest',
          remaining: 6000,
          sortAt: DateTime(2026, 9, 12, 13, 30),
        ),
        CustomerPaymentDebt(
          id: 'oldest',
          remaining: 13000,
          sortAt: DateTime(2026, 9, 12, 13, 28),
        ),
        CustomerPaymentDebt(
          id: 'middle',
          remaining: 2000,
          sortAt: DateTime(2026, 9, 12, 13, 29),
        ),
      ],
    );

    expect(
      allocations
          .map((allocation) => '${allocation.debtId}:${allocation.amount.toInt()}')
          .toList(),
      ['oldest:13000', 'middle:2000', 'newest:6000'],
    );
  });

  test('a partial customer payment stops when the entered amount is exhausted', () {
    final allocations = allocateCustomerPayment(
      amount: 14000,
      debts: [
        CustomerPaymentDebt(
          id: 'oldest',
          remaining: 13000,
          sortAt: DateTime(2026, 9, 12, 13, 28),
        ),
        CustomerPaymentDebt(
          id: 'middle',
          remaining: 2000,
          sortAt: DateTime(2026, 9, 12, 13, 29),
        ),
        CustomerPaymentDebt(
          id: 'newest',
          remaining: 6000,
          sortAt: DateTime(2026, 9, 12, 13, 30),
        ),
      ],
    );

    expect(allocations.length, 2);
    expect(allocations[0].debtId, 'oldest');
    expect(allocations[0].amount, 13000);
    expect(allocations[1].debtId, 'middle');
    expect(allocations[1].amount, 1000);
  });

  test('rejects a customer payment that exceeds the total open balance', () {
    expect(
      () => allocateCustomerPayment(
        amount: 22000,
        debts: [
          CustomerPaymentDebt(
            id: 'a',
            remaining: 13000,
            sortAt: DateTime(2026, 9, 12, 13, 28),
          ),
          CustomerPaymentDebt(
            id: 'b',
            remaining: 2000,
            sortAt: DateTime(2026, 9, 12, 13, 29),
          ),
          CustomerPaymentDebt(
            id: 'c',
            remaining: 6000,
            sortAt: DateTime(2026, 9, 12, 13, 30),
          ),
        ],
      ),
      throwsArgumentError,
    );
  });
}
