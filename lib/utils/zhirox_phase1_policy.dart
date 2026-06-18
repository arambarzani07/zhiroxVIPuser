class ZhiroxRoles {
  static const String manager = 'admin';
  static const String employee = 'employee';
  static const String customer = 'customer';

  static const List<String> all = [manager, employee, customer];

  static String label(String role) {
    switch (role) {
      case manager:
        return 'بەڕێوەبەر';
      case employee:
        return 'کارمەند';
      case customer:
        return 'کڕیار';
      default:
        return 'کڕیار';
    }
  }
}

class ZhiroxBusinessMessages {
  static const String selectCustomer = 'تکایە کڕیارێک هەڵبژێرە';
  static const String enterDebtAmount = 'تکایە بڕی قەرز بنووسە';
  static const String amountMustBePositive = 'بڕی پارە دەبێت لە سفر زیاتر بێت';
  static const String paymentCannotExceedRemaining =
      'بڕی پارەی وەرگیراو نابێت زیاتر بێت لە قەرزی ماوە';
  static const String managerApprovalRequired =
      'ئەم کردارە پێویستی بە ڕێگەپێدانی بەڕێوەبەر هەیە';
  static const String protectedForLater =
      'پارێزرا ✅ کاتێک ئینتەرنێت گەڕایەوە، خۆکارانە تەواو دەبێت';
  static const String saved = 'تۆمارکرا ✅';
  static const String updated = 'نوێکرایەوە ✅';
  static const String received = 'پارە وەرگیرا ✅';

  static String cleanSnackMessage(String message, {required bool isWarning}) {
    final text = message.trim();
    if (text.isEmpty) return isWarning ? protectedForLater : saved;
    if (text.length > 120) return isWarning ? protectedForLater : saved;
    return text;
  }
}
