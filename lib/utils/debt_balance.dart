import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/utils/helpers.dart';

class DebtBalance {
  static double amount(RecordModel debt) {
    final value = debt.getDoubleValue('amount');
    return value < 0 ? 0 : value;
  }

  static double remaining(RecordModel debt) {
    final value = debt.getDoubleValue('remaining');
    return value < 0 ? 0 : value;
  }

  static double paid(RecordModel debt) {
    final value = amount(debt) - remaining(debt);
    return value < 0 ? 0 : value;
  }

  static bool isPaid(RecordModel debt) {
    return remaining(debt) <= 0 || debt.getStringValue('status') == 'paid';
  }

  static bool isActive(RecordModel debt) {
    return remaining(debt) > 0 && !isPaid(debt);
  }

  static double totalRemaining(Iterable<RecordModel> debts) {
    return debts.fold<double>(0, (sum, debt) => sum + remaining(debt));
  }

  static double totalPaid(Iterable<RecordModel> debts) {
    return debts.fold<double>(0, (sum, debt) => sum + paid(debt));
  }

  static int activeCount(Iterable<RecordModel> debts) {
    return debts.where(isActive).length;
  }

  static String statusLabel(RecordModel debt) {
    return isPaid(debt) ? 'قەرز تەواوە' : 'قەرزی ماوە';
  }

  static String formatRemaining(RecordModel debt) {
    return AppHelpers.formatCurrency(remaining(debt));
  }

  static double afterPayment(RecordModel debt, double paymentAmount) {
    final value = remaining(debt) - paymentAmount;
    return value < 0 ? 0 : value;
  }
}
