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
  static const String statementReady = 'کەشف حساب ئامادەیە ✅';
  static const String noCustomerDebt = 'هیچ قەرزێکی ماوەت نییە ✅';

  static String cleanSnackMessage(String message, {required bool isWarning}) {
    final normalized = message.toLowerCase();
    const blockedParts = [
      'api',
      'backend',
      'server',
      'database',
      'pocketbase',
      'exception',
      'failed',
      'null',
      'field',
      'collection',
      'record',
      'permission denied',
      'socket',
      'timeout',
      'connection',
      'هەڵە',
      'سێرڤەر',
      'داتابەیس',
      'پەیوەندی',
    ];

    final hasBlockedPart = blockedParts.any(normalized.contains);
    if (!hasBlockedPart) return message;

    return isWarning ? protectedForLater : saved;
  }
}

class ZhiroxPhase1Features {
  static const List<String> features = [
    '1. داخڵبوون بە پێی ڕۆڵ',
    '2. داشبۆردی بەڕێوەبەر',
    '3. میزکاری کارمەند',
    '4. داشبۆردی کڕیار',
    '5. ناوبەری جیاواز بۆ هەر ڕۆڵ',
    '6. دەسەڵاتی بەڕێوەبەر',
    '7. دەسەڵاتی کارمەند',
    '8. دەسەڵاتی کڕیار',
    '9. ڕێکخستنی دەسەڵاتی کارمەند',
    '10. پەیامی ڕێنماییی پاک',
    '11. شاراوەکردنی پەیامە ناوخۆییەکان',
    '12. پەیامی پاراستنی کردار کاتێک ئینتەرنێت نییە',
    '13. پاراستنی کردارەکان لە پشتەوە',
    '14. ڕووکار بە زمانی مارکێت',
    '15. RTL و وشەسازی یەکسان',
  ];
}
