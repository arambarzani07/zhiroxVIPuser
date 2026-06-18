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
    final paused = DebtLock.shouldPauseNewDebt(customer, debts);
    final color = paused ? AppColors.danger : AppColors.secondary;
    final title = DebtLock.pauseTitle(customer, debts);
    final reason = DebtLock.reason(customer, debts);
    final message = DebtLock.pauseMessage(customer, debts);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(paused ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: color),
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
