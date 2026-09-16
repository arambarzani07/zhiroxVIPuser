import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/services/payment_receipt_service.dart';

void main() {
  test('payment receipt separates current debt values from customer totals', () {
    final summary = PaymentReceiptService.resolveFinancialSummary(
      paymentAmount: 25000,
      debtRemaining: 75000,
      customerTotalPaidIqd: 125000,
      customerTotalRemainingIqd: 275000,
    );

    expect(summary.currentPayment, 25000);
    expect(summary.customerTotalPaidIqd, 125000);
    expect(summary.currentDebtRemaining, 75000);
    expect(summary.customerTotalRemainingIqd, 275000);
  });
}
