import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

class AppUserMessages {
  static const String protectedOffline = 'پارێزرا ✅ کاتێک ئینتەرنێت گەڕایەوە، خۆکارانە تەواو دەبێت';
  static const String needsManagerApproval = 'ئەم کردارە پێویستی بە ڕێگەپێدانی بەڕێوەبەر هەیە';
  static const String debtLimitExceeded = 'ئەم بڕە سنووری قەرزی کڕیار تێدەپەڕێنێت';

  static const List<String> allowedValidationMessages = [
    'تکایە کڕیارێک هەڵبژێرە',
    'تکایە بڕی قەرز بنووسە',
    'بڕی قەرز دەبێت لە سفر زیاتر بێت',
    'تکایە لانیکەم یەک کاڵا زیاد بکە',
    'تکایە بەرواری دانەوە هەڵبژێرە',
    'تکایە ژمارەی مۆبایل بە دروستی بنووسە',
    'بڕی پارە نابێت زیاتر بێت لە قەرزی ماوە',
    'تکایە ژمارە مۆبایل بنووسە',
    'تکایە وشەی نهێنی بنووسە',
  ];

  static const List<String> allowedSuccessMessages = [
    'قەرز تۆمارکرا ✅',
    'پارە وەرگیرا ✅',
    'کڕیار زیادکرا ✅',
    'قەرزی ماوە نوێکرایەوە',
    'ڕاپۆرت ئامادەیە',
    'کەشف حساب درووستکرا',
    'دەسەڵاتی کارمەند نوێکرایەوە ✅',
  ];
}

class AppHelpers {
  // فۆرماتی پارە
  static String formatCurrency(double amount) {
    final formatter = NumberFormat('#,###', 'en');
    return '${formatter.format(amount)} د.ع';
  }

  // فۆرماتی پارە بە جۆری دراو
  static String formatCurrencyWithType(
    double amount,
    String currency, {
    double? dollarRate,
    bool showConversion = true,
  }) {
    final formatter = NumberFormat('#,###', 'en');
    if (currency == 'USD') {
      final formatted = NumberFormat('#,##0.00', 'en').format(amount);
      if (showConversion && dollarRate != null && dollarRate > 0) {
        final iqd = amount * dollarRate;
        return '\$$formatted (${formatter.format(iqd)} د.ع)';
      }
      return '\$$formatted';
    }
    return '${formatter.format(amount)} د.ع';
  }

  // فۆرماتی بەروار
  static String formatDate(String date) {
    try {
      final parsed = DateTime.parse(date).toLocal();
      return DateFormat('yyyy/MM/dd').format(parsed);
    } catch (_) {
      return '';
    }
  }

  static String formatDateTime(String date) {
    try {
      final parsed = DateTime.parse(date).toLocal();
      return DateFormat('yyyy/MM/dd  hh:mm a').format(parsed);
    } catch (_) {
      return '';
    }
  }

  // رەنگی بارودۆخ
  static Color statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'partial':
        return Colors.blue;
      case 'paid':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // ناوی بارودۆخ بە کوردی
  static String statusName(String status) {
    switch (status) {
      case 'pending':
        return 'چاوەڕوانە';
      case 'partial':
        return 'بەشێکی ماوە';
      case 'paid':
        return 'تەواوە';
      default:
        return '';
    }
  }

  // ناوی ڕۆڵ بە کوردی
  static String roleName(String role) {
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

  // ماوەی ماوە بە ڕۆژ
  static String remainingDays(int days) {
    if (days <= 0) return 'ئەمڕۆ';
    if (days == 1) return '١ ڕۆژ ماوە';
    return '$days ڕۆژ ماوە';
  }

  /// Final Phase-1 UI rule:
  /// Market users must see only helpful guidance, confirmations, protection,
  /// or manager-approval wording. Technical and internal wording is hidden.
  static String? businessSafeMessage(String rawMessage, {bool isError = false}) {
    final message = rawMessage.trim();
    if (message.isEmpty) return null;

    final lower = message.toLowerCase();

    final isInternetState =
        lower.contains('internet') ||
        lower.contains('network') ||
        lower.contains('connection') ||
        lower.contains('socket') ||
        lower.contains('timeout') ||
        lower.contains('offline') ||
        message.contains('ئینتەرنێت');

    if (isInternetState) return AppUserMessages.protectedOffline;

    final exactAllowed = <String>{
      ...AppUserMessages.allowedValidationMessages,
      ...AppUserMessages.allowedSuccessMessages,
      AppUserMessages.needsManagerApproval,
      AppUserMessages.debtLimitExceeded,
    };

    if (exactAllowed.contains(message)) return message;

    final isAllowedGuidance =
        message.contains('تکایە') ||
        message.contains('نابێت') ||
        message.contains('دەبێت') ||
        message.contains('ڕێگەپێدانی بەڕێوەبەر') ||
        message.contains('وشەی نهێنی') ||
        message.contains('ژمارە مۆبایل') ||
        message.contains('سنووری قەرز') ||
        message.contains('پارێزرا') ||
        message.contains('تۆمار کرا') ||
        message.contains('تۆمارکرا') ||
        message.contains('زیادکرا') ||
        message.contains('نوێکرایەوە') ||
        message.contains('وەرگیرا') ||
        message.contains('نێردرا') ||
        message.contains('ئامادەیە') ||
        message.contains('درووستکرا') ||
        message.contains('تەواو بوو');

    final forbidden = <String>[
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

    final hasForbidden = forbidden.any(lower.contains) || forbidden.any((word) => message.contains(word));
    if (hasForbidden) return null;

    if (isError && message.contains(':')) return null;
    if (isError && !isAllowedGuidance) return null;

    return message;
  }

  // پیشاندانی سناکبار بە یاسای ڕووکارە پاکەکان
  static void showSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    final safeMessage = businessSafeMessage(message, isError: isError);
    if (safeMessage == null || safeMessage.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(safeMessage, textDirection: TextDirection.rtl),
        backgroundColor: isError ? Colors.orange.shade800 : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // دیالۆگی دڵنیابوونەوە
  static Future<bool> showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, textDirection: TextDirection.rtl),
        content: Text(message, textDirection: TextDirection.rtl),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('نەخێر'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('بەڵێ'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  static String formatTime(String date) {
    try {
      final parsed = DateTime.parse(date).toLocal();
      return DateFormat('hh:mm a').format(parsed);
    } catch (_) {
      return '';
    }
  }

  static String getDaysCounter(String created, String updated, bool isPaid) {
    try {
      final start = DateTime.parse(created).toLocal();
      final end = isPaid ? DateTime.parse(updated).toLocal() : DateTime.now();

      final diff = end.difference(start);
      final days = diff.inDays;

      if (days <= 0) return 'ئەمڕۆ';
      if (days == 1) return '١ ڕۆژ';
      return '$days ڕۆژ';
    } catch (_) {
      return '';
    }
  }

  static void showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }
}
