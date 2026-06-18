import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/utils/debt_balance.dart';

class DebtLock {
  static bool hasOverLimit(RecordModel customer, Iterable<RecordModel> debts) {
    final limit = customer.getDoubleValue('debt_limit');
    if (limit <= 0) return false;
    return DebtBalance.totalRemaining(debts) > limit;
  }

  static bool hasOverdue(Iterable<RecordModel> debts) {
    return debts.any(isOverdueDebt);
  }

  static bool isOverdueDebt(RecordModel debt) {
    if (!DebtBalance.isActive(debt)) return false;
    final due = dueDate(debt);
    if (due == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return due.isBefore(today);
  }

  static DateTime? dueDate(RecordModel debt) {
    final raw = debt.getStringValue('due_date');
    if (raw.isEmpty) return null;
    try {
      final parsed = DateTime.parse(raw).toLocal();
      return DateTime(parsed.year, parsed.month, parsed.day);
    } catch (_) {
      return null;
    }
  }

  static bool isLocked(RecordModel customer, Iterable<RecordModel> debts) {
    return hasOverLimit(customer, debts) || hasOverdue(debts);
  }

  static bool shouldPauseNewDebt(RecordModel customer, Iterable<RecordModel> debts) {
    return isLocked(customer, debts);
  }

  static String reason(RecordModel customer, Iterable<RecordModel> debts) {
    if (hasOverLimit(customer, debts)) return 'سنووری قەرز تێپەڕیوە';
    if (hasOverdue(debts)) return 'قەرزی دواکەوتوو هەیە';
    return 'قەرزی نوێ کراوەیە';
  }

  static String pauseTitle(RecordModel customer, Iterable<RecordModel> debts) {
    return shouldPauseNewDebt(customer, debts) ? 'قەرزی نوێ ڕاگیراوە' : 'قەرزی نوێ کراوەیە';
  }

  static String pauseMessage(RecordModel customer, Iterable<RecordModel> debts) {
    return shouldPauseNewDebt(customer, debts)
        ? 'تەنها بەڕێوەبەر دەتوانێت بە بڕیاری خۆی قەرزی نوێ زیاد بکات.'
        : 'دەتوانرێت قەرزی نوێ بە شێوەی ئاسایی تۆمار بکرێت.';
  }
}
