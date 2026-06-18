import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/debt_balance.dart';
import 'package:zhirox/utils/helpers.dart';

class CustomerLimitSummaryCard extends StatelessWidget {
  final RecordModel customer;
  final List<RecordModel> debts;
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const CustomerLimitSummaryCard({
    super.key,
    required this.customer,
    required this.debts,
    required this.cardColor,
    required this.textColor,
    required this.subColor,
  });

  @override
  Widget build(BuildContext context) {
    final limit = customer.getDoubleValue('debt_limit');
    final used = DebtBalance.totalRemaining(debts);
    final left = limit <= 0 ? 0 : (limit - used).clamp(0, double.infinity).toDouble();
    final over = limit > 0 && used > limit;
    final progress = limit <= 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(over ? Icons.warning_amber_rounded : Icons.shield_rounded, color: over ? AppColors.danger : AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('سنووری قەرز', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 12),
        _LimitLine(label: 'سنووری گشتی', value: limit <= 0 ? 'بێ سنوور' : AppHelpers.formatCurrency(limit), color: textColor, subColor: subColor),
        _LimitLine(label: 'قەرزی بەکارهاتوو', value: AppHelpers.formatCurrency(used), color: over ? AppColors.danger : textColor, subColor: subColor),
        _LimitLine(label: 'سنووری ماوە', value: limit <= 0 ? 'بێ سنوور' : AppHelpers.formatCurrency(left), color: over ? AppColors.danger : AppColors.secondary, subColor: subColor),
        if (limit > 0) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: subColor.withOpacity(0.14), color: over ? AppColors.danger : AppColors.primary),
          ),
          const SizedBox(height: 8),
          Text(over ? 'ئەم کڕیارە سنووری قەرزی تێپەڕاندووە.' : 'سنووری قەرز لە چوارچێوەی پاراستنی پارەدا چاودێری دەکرێت.', style: TextStyle(color: subColor, fontSize: 12, height: 1.5)),
        ] else ...[
          const SizedBox(height: 8),
          Text('بۆ ئەم کڕیارە سنووری قەرز دانەنراوە.', style: TextStyle(color: subColor, fontSize: 12, height: 1.5)),
        ],
      ]),
    );
  }
}

class _LimitLine extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color subColor;

  const _LimitLine({required this.label, required this.value, required this.color, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Text(label, style: TextStyle(color: subColor, fontSize: 13)),
        const Spacer(),
        Text(value, textDirection: TextDirection.ltr, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}
