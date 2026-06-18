import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF1A73E8);
  static const Color secondary = Color(0xFF4CAF50);
  static const Color danger = Color(0xFFE53935);
  static const Color warning = Color(0xFFFFA726);
  static const Color background = Color(0xFFF5F7FA);
  static const Color cardBg = Colors.white;
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color success = Color(0xFF2E7D32);
  static const Color scaffoldBackground = Color(0xFFF5F7FA);
}

class AppDarkColors {
  static const Color background = Color(0xFF0F1523);
  static const Color surface = Color(0xFF1A2137);
  static const Color card = Color(0xFF1E2742);
  static const Color cardBorder = Color(0xFF2A3555);
  static const Color textPrimary = Color(0xFFE8ECF4);
  static const Color textSecondary = Color(0xFF8B95B0);
  static const Color divider = Color(0xFF2A3555);
  static const Color primary = Color(0xFF5B9CF6);
  static const Color primaryMuted = Color(0xFF2D4A7A);
  static const Color inputFill = Color(0xFF16203A);
  static const Color shimmer = Color(0xFF243052);
}

class AppStrings {
  static const String appName = 'ژیرۆکس';
  static const String appTagline = 'سیستەمی زیرەکی پاراستنی پارەی مارکێت';

  // گشتی
  static const String login = 'چوونەژوورەوە';
  static const String logout = 'چوونەدەرەوە';
  static const String phone = 'ژمارە مۆبایل';
  static const String password = 'وشەی نهێنی';
  static const String save = 'پاشەکەوتکردن';
  static const String cancel = 'پاشگەزبوونەوە';
  static const String delete = 'سڕینەوە';
  static const String edit = 'دەستکاریکردن';
  static const String search = 'گەڕان';
  static const String noData = 'هێشتا هیچ تۆمارێک نییە';
  static const String loading = 'ئامادەکردن...';
  static const String notice = 'ئاگاداری';
  static const String success = 'سەرکەوتوو';

  // ڕۆڵەکان
  static const String role = 'ڕۆڵ';
  static const String manager = 'بەڕێوەبەر';
  static const String admin = 'بەڕێوەبەر';
  static const String employee = 'کارمەند';
  static const String customer = 'کڕیار';

  // زانیاری کەسی
  static const String name = 'ناو';
  static const String fatherName = 'ناوی باوک';
  static const String grandfatherName = 'ناوی باپیر';
  static const String fullName = 'ناوی سیانی';
  static const String marketName = 'ناوی مارکێت';

  // تۆمارکردن
  static const String register = 'خۆتۆمارکردن';
  static const String registerAdmin = 'تۆمارکردنی بەڕێوەبەری نوێ';
  static const String registerCustomer = 'خۆتۆمارکردنی کڕیار';
  static const String selectMarket = 'مارکێت هەڵبژێرە';
  static const String pendingApproval = 'چاوەڕوانی ڕێگەپێدان';
  static const String pendingRequests = 'داواکارییەکان';
  static const String approve = 'ڕێگەپێدان';
  static const String reject = 'ڕەتکردنەوە';
  static const String debtDuration = 'ماوەی قەرز (ڕۆژ)';
  static const String requestSent = 'داواکارییەکەت نێردرا ✅';
  static const String notApproved = 'هێشتا پێویستی بە ڕێگەپێدانی بەڕێوەبەر هەیە';

  // قەرز
  static const String debt = 'قەرز';
  static const String debts = 'قەرزەکان';
  static const String addDebt = 'قەرز پێدان';
  static const String editDebt = 'دەستکاری قەرز';
  static const String amount = 'بڕی پارە';
  static const String description = 'تێبینی';
  static const String dueDate = 'بەرواری دانەوە';
  static const String status = 'بار';
  static const String pending = 'چاوەڕوانە';
  static const String partial = 'بەشێکی ماوە';
  static const String paid = 'تەواوە';
  static const String totalDebt = 'کۆی قەرز';
  static const String remainingDebt = 'قەرزی ماوە';
  static const String paidAmount = 'پارەی وەرگیراو';
  static const String remainingAmount = 'ماوە';
  static const String debtLimit = 'سنووری قەرز';
  static const String noDebtLimit = 'بێ سنوور';
  static const String debtGivenSaved = 'قەرز پێدان تۆمار کرا ✅';

  // دراو و کاڵا
  static const String currency = 'دراو';
  static const String iqd = 'دینار';
  static const String usd = 'دۆلار';
  static const String dollarRate = 'نرخی دۆلار';
  static const String itemName = 'ناوی کاڵا';
  static const String itemPrice = 'نرخ';
  static const String addItem = 'کاڵا زیاد بکە';
  static const String items = 'کاڵاکان';
  static const String total = 'کۆی گشتی';

  // پارە وەرگرتنەوە
  static const String payment = 'پارە وەرگرتنەوە';
  static const String payments = 'پارە وەرگرتنەوەکان';
  static const String addPayment = 'پارە وەرگرتنەوەی نوێ';
  static const String paymentAmount = 'بڕی پارەی وەرگیراو';
  static const String paymentForCustomer = 'پارە وەرگرتنەوە بۆ';
  static const String bulkPaymentNote = 'پارە وەرگرتنەوەی کۆمەڵ';
  static const String fullyReceivedDebt = 'قەرز تەواو وەرگیرا';
  static const String partiallyReceivedDebt = 'قەرز بەشێکی وەرگیرا';
  static const String paymentSaved = 'پارە وەرگرتنەوە تۆمار کرا ✅';
  static const String noPayments = 'هێشتا هیچ پارە وەرگرتنەوەیەک نییە';
  static const String receivedPercent = 'وەرگیراوە';
  static const String note = 'تێبینی';

  // داشبۆرد و ناوبەری
  static const String dashboard = 'داشبۆرد';
  static const String managerDashboard = 'داشبۆردی بەڕێوەبەر';
  static const String employeeDesk = 'میزکاری کارمەند';
  static const String customerHome = 'قەرزی من';
  static const String customers = 'کڕیارەکان';
  static const String employees = 'کارمەندەکان';
  static const String addCustomer = 'کڕیاری نوێ';
  static const String addEmployee = 'کارمەندی نوێ';
  static const String totalCustomers = 'کۆی کڕیارەکان';
  static const String totalDebts = 'کۆی قەرزەکان';
  static const String totalPayments = 'کۆی پارە وەرگرتنەوەکان';

  // پەیامە ڕێگەپێدراوەکانی قۆناغی یەکەم
  static const String chooseCustomer = 'تکایە کڕیارێک هەڵبژێرە';
  static const String enterDebtAmount = 'تکایە بڕی قەرز بنووسە';
  static const String enterPaymentAmount = 'تکایە بڕی پارەی وەرگیراو بنووسە';
  static const String amountMustBePositive = 'بڕی پارە دەبێت لە سفر زیاتر بێت';
  static const String paymentCannotExceedDebt =
      'بڕی پارەی وەرگیراو نابێت زیاتر بێت لە قەرزی ماوە';
  static const String managerApprovalNeeded =
      'ئەم کردارە پێویستی بە ڕێگەپێدانی بەڕێوەبەر هەیە';
  static const String savedForLater =
      'پارێزرا ✅ کاتێک ئینتەرنێت گەڕایەوە، خۆکارانە تەواو دەبێت';
}

class PBConfig {
  static const String baseUrl = 'https://pocketbase-production-18bc.up.railway.app';
}
