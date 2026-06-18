import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/debt_lock.dart';

class CustomerDebtLockCard extends StatelessWidget {
  final RecordModel customer;
  final List<RecordModel> debts;
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const CustomerDebtLockCard({
    super.key,
    required this.customer,
    required this.debts,
    required this.cardColor,
    required this.textColor,
    required this.subColor,
  });

  @override
  Widget build(BuildContext context) {
    final locked = DebtLock.isLocked(customer, debts);
    final color = locked ? AppColors.danger : AppColors.secondary;
    final title = locked ? 'قەرزی قفڵکراو' : 'قەرزی نوێ کراوەیە';
    final reason = DebtLock.reason(customer, debts);
    final message = locked
        ? 'قەرزی نوێ بۆ ئەم کڕیارە پێویستی بە ڕێگەپێدانی بەڕێوەبەر هەیە.'
        : 'دەتوانرێت قەرزی نوێ بە شێوەی ئاسایی تۆمار بکرێت.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(locked ? Icons.lock_rounded : Icons.lock_open_rounded, color: color),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 5),
          Text(reason, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 5),
          Text(message, style: TextStyle(color: subColor, height: 1.5, fontSize: 12)),
        ])),
      ]),
    );
  }
}
