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
  static const String requestSent = 'داواکاریت نێردرا، چاوەڕوان بە هەتا قبوڵ بکرێت';
  static const String notApproved = 'هێشتا داواکاریت قبوڵ نەکراوە';
  static const String debt = 'قەرز';
  static const String debts = 'قەرزەکان';
  static const String addDebt = 'قەرزی نوێ';
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
  static const String payment = 'پارەدانەوە';
  static const String payments = 'پارەدانەوەکان';
  static const String addPayment = 'پارەدانەوەی نوێ';
  static const String paymentAmount = 'بڕی پارەدانەوە';
  static const String note = 'تێبینی';
  static const String dashboard = 'داشبۆرد';
  static const String customers = 'کڕیارەکان';
  static const String employees = 'کارمەندەکان';
  static const String addCustomer = 'کڕیاری نوێ';
  static const String addEmployee = 'کارمەندی نوێ';
  static const String totalCustomers = 'کۆی کڕیارەکان';
  static const String totalDebts = 'کۆی قەرزەکان';
  static const String totalPayments = 'کۆی پارەدانەوەکان';
}

class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zfuvnczdqifihsnrhqzj.supabase.co',
  );
  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_HWmOdApexuI8Ha7ZPZKa6A_SYVwOozk',
  );
}

class PBConfig {
  static const String baseUrl = SupabaseConfig.url;
}

class AppConfig {
  static const String appVersion = '1.0.0';
}
