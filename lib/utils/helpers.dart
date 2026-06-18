import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:zhirox/utils/zhirox_phase1_policy.dart';

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
      return date;
    }
  }

  static String formatDateTime(String date) {
    try {
      final parsed = DateTime.parse(date).toLocal();
      return DateFormat('yyyy/MM/dd  hh:mm a').format(parsed);
    } catch (_) {
      return date;
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
        return status;
    }
  }

  // ناوی ڕۆڵ بە کوردی
  static String roleName(String role) => ZhiroxRoles.label(role);

  // ماوەی ماوە بە ڕۆژ
  static String remainingDays(int days) {
    if (days <= 0) return 'تەواو بووە';
    if (days == 1) return '١ ڕۆژ ماوە';
    return '$days ڕۆژ ماوە';
  }

  // پیشاندانی پەیامی پاکی کاربەر
  static void showSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    final safeMessage = ZhiroxBusinessMessages.cleanSnackMessage(
      message,
      isWarning: isError,
    );

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
