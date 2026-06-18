import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/utils/debt_balance.dart';

class PartialPayment {
  static double paymentAmount(String input) {
    return double.tryParse(input.replaceAll(',', '').trim()) ?? 0;
  }

  static double beforePayment(RecordModel debt) {
    return DebtBalance.remaining(debt);
  }

  static double afterPayment(RecordModel debt, double amount) {
    return DebtBalance.afterPayment(debt, amount);
  }

  static bool isFullPayment(RecordModel debt, double amount) {
    return amount > 0 && afterPayment(debt, amount) <= 0;
  }

  static bool isPartialPayment(RecordModel debt, double amount) {
    return amount > 0 && afterPayment(debt, amount) > 0;
  }

  static String statusLabel(RecordModel debt, double amount) {
    if (amount <= 0) return 'بڕی پارە بنووسە';
    if (isFullPayment(debt, amount)) return 'ئەم پارەیە قەرزەکە تەواو دەکات';
    if (isPartialPayment(debt, amount)) return 'ئەم پارەیە بەشێک لە قەرز کەم دەکاتەوە';
    return 'بڕی پارە بنووسە';
  }
}
