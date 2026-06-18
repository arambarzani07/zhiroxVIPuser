import 'package:zhirox/utils/constants.dart';

class PaymentPreviewText {
  const PaymentPreviewText._();

  static String titleForCustomer(String customerName) {
    return '${AppStrings.paymentForCustomer} $customerName';
  }

  static String amountLabel() {
    return AppStrings.paymentAmount;
  }

  static String bulkNote() {
    return AppStrings.bulkPaymentNote;
  }

  static String savedForDebtCount(int count) {
    return '${AppStrings.paymentSaved} ($count ${AppStrings.debt})';
  }

  static String fullyReceivedDebtLabel(int count) {
    return '✓ $count ${AppStrings.paid}';
  }

  static String partiallyReceivedDebtLabel(int count) {
    return '◐ $count ${AppStrings.partial}';
  }
}
