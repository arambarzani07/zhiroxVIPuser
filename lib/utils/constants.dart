import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF3157E0);
  static const Color primarySoft = Color(0xFFE9EDFF);
  static const Color secondary = Color(0xFF12A594);
  static const Color accent = Color(0xFFFFB547);
  static const Color danger = Color(0xFFE5484D);
  static const Color warning = Color(0xFFF59E0B);
  static const Color success = Color(0xFF0E9F6E);
  static const Color background = Color(0xFFF6F7FB);
  static const Color scaffoldBackground = background;
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF0F2F8);
  static const Color cardBg = surface;
  static const Color border = Color(0xFFE2E5EF);
  static const Color textPrimary = Color(0xFF171B2E);
  static const Color textSecondary = Color(0xFF687086);
}

class AppDarkColors {
  static const Color background = Color(0xFF0B1020);
  static const Color surface = Color(0xFF11182B);
  static const Color card = Color(0xFF151E34);
  static const Color cardBorder = Color(0xFF27324A);
  static const Color textPrimary = Color(0xFFF4F6FB);
  static const Color textSecondary = Color(0xFFA6AFC3);
  static const Color divider = cardBorder;
  static const Color primary = Color(0xFF8CA4FF);
  static const Color primaryMuted = Color(0xFF263B78);
  static const Color inputFill = Color(0xFF10182C);
  static const Color shimmer = Color(0xFF202C47);
}

class AppStrings {
  static const String appName = 'ژیرۆکس';
  static const String login = 'چوونەژوورەوە';
  static const String logout = 'چوونەدەرەوە';
  static const String phone = 'ژمارە مۆبایل';
  static const String password = 'وشەی نهێنی';
  static const String save = 'پاشەکەوتکردن';
  static const String cancel = 'پاشگەزبوونەوە';
  static const String delete = 'سڕینەوە';
  static const String edit = 'دەستکاریکردن';
  static const String search = 'گەڕان';
  static const String noData = 'هیچ داتایەک نییە';
  static const String loading = 'چاوەڕوان بە...';
  static const String error = 'هەڵە';
  static const String success = 'سەرکەوتوو';

  static const String name = 'ناو';
  static const String fatherName = 'ناوی باوک';
  static const String grandfatherName = 'ناوی باپیر';
  static const String fullName = 'ناوی سیانی';
  static const String role = 'ڕۆڵ';
  static const String admin = 'بەڕێوبەر';
  static const String employee = 'کارمەند';
  static const String customer = 'کڕیار';
  static const String marketName = 'ناوی مارکێت';

  static const String register = 'خۆتۆمارکردن';
  static const String registerAdmin = 'تۆمارکردنی بەڕێوبەری نوێ';
  static const String registerCustomer = 'خۆتۆمارکردنی کڕیار';
  static const String selectMarket = 'مارکێت هەڵبژێرە';
  static const String pendingApproval = 'چاوەڕوانی قبوڵکردن';
  static const String pendingRequests = 'داواکاریەکان';
  static const String approve = 'قبوڵکردن';
  static const String reject = 'ڕەتکردنەوە';
  static const String debtDuration = 'ماوەی قەرز (ڕۆژ)';
  static const String requestSent =
      'داواکاریت نێردرا، چاوەڕوان بە هەتا قبوڵ بکرێت';
  static const String notApproved = 'هێشتا داواکاریت قبوڵ نەکراوە';

  static const String debt = 'قەرز';
  static const String debts = 'قەرزەکان';
  static const String addDebt = 'قەرز پێدان';
  static const String amount = 'بڕی پارە';
  static const String description = 'تێچوون';
  static const String dueDate = 'بەرواری دوایین';
  static const String status = 'بارودۆخ';
  static const String pending = 'چاوەڕوانە';
  static const String partial = 'بەشێکی دراوە';
  static const String paid = 'دراوە';
  static const String totalDebt = 'کۆی قەرز';
  static const String remainingDebt = 'قەرزی ماوە';

  static const String currency = 'دراو';
  static const String iqd = 'دینار';
  static const String usd = 'دۆلار';
  static const String dollarRate = 'نرخی دۆلار';
  static const String itemName = 'ناوی کاڵا';
  static const String itemPrice = 'نرخ';
  static const String addItem = 'کاڵا زیادبکە';
  static const String items = 'کاڵاکان';
  static const String total = 'کۆی گشتی';

  static const String payment = 'پارە وەرگرتنەوە';
  static const String payments = 'پارە وەرگرتنەوەکان';
  static const String addPayment = 'پارە وەرگرتنەوەی نوێ';
  static const String paymentAmount = 'بڕی پارەی وەرگیراو';
  static const String note = 'تێبینی';

  static const String dashboard = 'داشبۆرد';
  static const String customers = 'کڕیارەکان';
  static const String employees = 'کارمەندەکان';
  static const String addCustomer = 'کڕیاری نوێ';
  static const String addEmployee = 'کارمەندی نوێ';
  static const String totalCustomers = 'کۆی کڕیارەکان';
  static const String totalDebts = 'کۆی قەرزەکان';
  static const String totalPayments = 'کۆی پارە وەرگرتنەوەکان';
}

class SupabaseConfig {
  static const String url = 'https://hsoyfbtpvwfmjokudznx.supabase.co';
  static const String publishableKey =
      'sb_publishable_EU2ZhecxlnsvNMQkk76x2A_X-jF6aOr';
}

// Compatibility alias retained so older files do not need a broad rename.
class PBConfig {
  static const String baseUrl = SupabaseConfig.url;
}
