import 'package:zhirox/utils/constants.dart';

class PaymentPreviewText {
  const PaymentPreviewText._();

  static String fullyReceivedDebtLabel(int count) {
    return '✓ $count ${AppStrings.paid}';
  }

  static String partiallyReceivedDebtLabel(int count) {
    return '◐ $count ${AppStrings.partial}';
  }
}
