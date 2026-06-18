class ZhiroxRoles {
  static const String manager = 'admin';
  static const String employee = 'employee';
  static const String customer = 'customer';

  static const List<String> visibleRoles = [manager, employee, customer];

  static String label(String role) {
    switch (role) {
      case manager:
        return 'بەڕێوەبەر';
      case employee:
        return 'کارمەند';
      case customer:
        return 'کڕیار';
      default:
        return '';
    }
  }

  static bool isVisibleRole(String role) => visibleRoles.contains(role);
}

class ZhiroxEmployeePermission {
  static const String addCustomer = 'add_customer';
  static const String giveDebt = 'give_debt';
  static const String receivePayment = 'receive_payment';
  static const String createStatement = 'create_statement';
  static const String recordPromise = 'record_promise';
  static const String editDebt = 'edit_debt';
  static const String editPayment = 'edit_payment';
  static const String viewReports = 'view_reports';
  static const String confirmSensitiveActions = 'confirm_sensitive_actions';

  static const List<String> phase1Defaults = [
    addCustomer,
    giveDebt,
    receivePayment,
    createStatement,
    recordPromise,
  ];
}

class ZhiroxMarketUiPolicy {
  static const String protectedInternetMessage =
      'پارێزرا ✅ کاتێک ئینتەرنێت گەڕایەوە، خۆکارانە تەواو دەبێت';

  static const List<String> allowedGuidanceSignals = [
    'تکایە',
    'نابێت',
    'دەبێت',
    'ڕێگەپێدانی بەڕێوەبەر',
    'وشەی نهێنی',
    'ژمارە مۆبایل',
    'سنووری قەرز',
    'ئینتەرنێت',
    'پارێزرا',
    'تۆمار کرا',
    'تۆمارکرا',
    'نوێکرایەوە',
    'وەرگیرا',
    'نێردرا',
    'ئامادەیە',
    'تەواو بوو',
  ];

  static const List<String> internetSignals = [
    'internet',
    'network',
    'connection',
    'socket',
    'timeout',
    'offline',
    'ئینتەرنێت',
  ];

  static const List<String> forbiddenVisibleSignals = [
    'database',
    'server',
    'api',
    'backend',
    'pocketbase',
    'collection',
    'field',
    'record',
    'relation',
    'admin_id',
    'null',
    'exception',
    'failed',
    'failure',
    'clientexception',
    'socketexception',
    'formatexception',
    'stack',
    'debug',
    'schema',
    'try again',
    'something went wrong',
    'هەڵە لە',
    'هەڵە ڕوویدا',
    'داتابەیس',
    'سێرڤەر',
    'باکێند',
    'کۆلێکشن',
    'فیلد',
  ];

  static String? cleanMessage(String rawMessage, {bool isError = false}) {
    final message = rawMessage.trim();
    if (message.isEmpty) return null;

    final lower = message.toLowerCase();
    final isInternetState = internetSignals.any((signal) => lower.contains(signal.toLowerCase())) ||
        internetSignals.any((signal) => message.contains(signal));

    if (isInternetState) return protectedInternetMessage;

    final isAllowedGuidance = allowedGuidanceSignals.any(message.contains);
    final hasForbidden = forbiddenVisibleSignals.any((signal) => lower.contains(signal.toLowerCase())) ||
        forbiddenVisibleSignals.any((signal) => message.contains(signal));

    if (hasForbidden && !isAllowedGuidance) return null;
    if (isError && message.contains(':') && !isAllowedGuidance) return null;

    return message;
  }
}

class ZhiroxPhase1Feature {
  static const List<String> approved = [
    '1. داخڵبوون بە پێی ڕۆڵ',
    '2. داشبۆردی بەڕێوەبەر',
    '3. میزکاری کارمەند',
    '4. داشبۆردی کڕیار',
    '5. ناوبەری جیاواز بۆ هەر ڕۆڵ',
    '6. دەسەڵاتی بەڕێوەبەر',
    '7. دەسەڵاتی کارمەند',
    '8. دەسەڵاتی کڕیار',
    '9. ڕێکخستنی permission ـی کارمەند',
    '10. پەیامی ڕێنماییی پاک',
    '11. قەدەغەکردنی پەیامی هەڵە/داتابەیس/API',
    '12. پەیامی ئینتەرنێت بە شێوەی پاراستن',
    '13. cache/queue لە پشتەوە',
    '14. ڕووکار بە زمانی مارکێت',
    '15. RTL و وشەسازی یەکسان',
  ];
}
