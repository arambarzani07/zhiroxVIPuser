class MarketLanguage {
  static const String productIdentity = 'سیستەمی زیرەکی پاراستنی پارەی مارکێت';
  static const String moneyProtectionCenter = 'ناوەندی پاراستنی پارە';
  static const String customerMoneyView = 'قەرزی من';
  static const String employeeWorkDesk = 'میزکاری کارمەند';
  static const String managerAuthority = 'دەسەڵاتی بەڕێوەبەر';
  static const String employeeAuthority = 'دەسەڵاتەکانی کارمەند';
  static const String customerAuthority = 'دەسەڵاتی کڕیار';

  static const List<String> marketMenus = [
    'داشبۆرد',
    'کڕیارەکان',
    'قەرزەکان',
    'پارە وەرگرتنەوە',
    'کەشف حساب',
    'قەرزی دواکەوتوو',
    'پێشنیاری سیستەم',
    'پاراستنی پارە',
    'ئاگادارییەکان',
    'ڕاپۆرتەکان',
    'کارمەندەکان',
    'ڕێکخستنەکان',
  ];

  static const List<String> marketSuccessMessages = [
    'قەرز تۆمارکرا ✅',
    'پارە وەرگیرا ✅',
    'کڕیار زیادکرا ✅',
    'قەرزی ماوە نوێکرایەوە',
    'ڕاپۆرت ئامادەیە',
    'کەشف حساب درووستکرا',
  ];

  static const List<String> marketGuidanceMessages = [
    'تکایە کڕیارێک هەڵبژێرە',
    'تکایە بڕی قەرز بنووسە',
    'بڕی قەرز دەبێت لە سفر زیاتر بێت',
    'تکایە لانیکەم یەک کاڵا زیاد بکە',
    'تکایە بەرواری دانەوە هەڵبژێرە',
    'تکایە ژمارەی مۆبایل بە دروستی بنووسە',
    'بڕی پارە نابێت زیاتر بێت لە قەرزی ماوە',
  ];

  static const Map<String, String> technicalToMarketWords = {
    'admin': 'بەڕێوەبەر',
    'employee': 'کارمەند',
    'customer': 'کڕیار',
    'user': 'هەژمار',
    'users': 'هەژمارەکان',
    'debt': 'قەرز',
    'debts': 'قەرزەکان',
    'payment': 'پارەدانەوە',
    'payments': 'پارەدانەوەکان',
    'permission': 'دەسەڵات',
    'permissions': 'دەسەڵاتەکان',
    'notification': 'ئاگاداری',
    'notifications': 'ئاگادارییەکان',
  };

  static String roleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'بەڕێوەبەر';
      case 'employee':
        return 'کارمەند';
      case 'customer':
        return 'کڕیار';
      default:
        return '';
    }
  }

  static String marketWord(String word) {
    return technicalToMarketWords[word] ?? word;
  }
}
