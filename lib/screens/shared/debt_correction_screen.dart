import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/debt_balance.dart';
import 'package:zhirox/utils/helpers.dart';

class DebtCorrectionScreen extends StatefulWidget {
  final RecordModel debt;
  const DebtCorrectionScreen({super.key, required this.debt});

  @override
  State<DebtCorrectionScreen> createState() => _DebtCorrectionScreenState();
}

class _DebtCorrectionScreenState extends State<DebtCorrectionScreen> {
  late final TextEditingController amountCtrl;
  late final TextEditingController noteCtrl;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    amountCtrl = TextEditingController(text: DebtBalance.amount(widget.debt).toStringAsFixed(0));
    noteCtrl = TextEditingController(text: widget.debt.getStringValue('description'));
  }

  @override
  void dispose() {
    amountCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  double newAmount() => double.tryParse(amountCtrl.text.replaceAll(',', '').trim()) ?? 0;
  double newRemaining() => (newAmount() - DebtBalance.paid(widget.debt)).clamp(0, double.infinity).toDouble();

  Future<void> save() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isManager && !auth.canEditDebts) {
      AppHelpers.showSnackBar(context, AppUserMessages.needsManagerApproval, isError: true);
      return;
    }
    final amount = newAmount();
    if (amount <= 0) {
      AppHelpers.showSnackBar(context, 'بڕی قەرز دەبێت لە سفر زیاتر بێت', isError: true);
      return;
    }
    final ok = await AppHelpers.showConfirmDialog(context, title: 'ڕاستکردنەوەی قەرز', message: 'زانیارییەکانی ئەم قەرزە نوێ دەکرێنەوە. دڵنیایت؟');
    if (!ok || !mounted) return;
    setState(() => saving = true);
    final left = newRemaining();
    try {
      await PBService.pb.collection('debts').update(widget.debt.id, body: {
        'amount': amount,
        'remaining': left,
        'status': left <= 0 ? 'paid' : 'active',
        'description': noteCtrl.text.trim().isEmpty ? 'قەرزی نوێ' : noteCtrl.text.trim(),
      });
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'قەرزی ماوە نوێکرایەوە');
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      AppHelpers.showSnackBar(context, AppUserMessages.protectedOffline);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppDarkColors.card : Colors.white;
    final textColor = isDark ? AppDarkColors.textPrimary : AppColors.textPrimary;
    final subColor = isDark ? AppDarkColors.textSecondary : AppColors.textSecondary;
    final paid = DebtBalance.paid(widget.debt);
    final left = newRemaining();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
        appBar: AppBar(title: const Text('ڕاستکردنەوەی قەرز')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('زانیاری قەرز', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              TextField(controller: amountCtrl, keyboardType: TextInputType.number, textDirection: TextDirection.ltr, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'کۆی قەرز', suffixText: 'د.ع')),
              const SizedBox(height: 10),
              TextField(controller: noteCtrl, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'تێبینی')),
            ]),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
            child: Column(children: [
              _Row(label: 'پارەی پێشتر وەرگیراو', value: AppHelpers.formatCurrency(paid), color: AppColors.secondary, subColor: subColor),
              _Row(label: 'قەرزی ماوەی نوێ', value: AppHelpers.formatCurrency(left), color: left <= 0 ? AppColors.secondary : AppColors.danger, subColor: subColor),
            ]),
          ),
          const SizedBox(height: 18),
          SizedBox(height: 52, child: FilledButton.icon(onPressed: saving ? null : save, icon: const Icon(Icons.check_rounded), label: Text(saving ? 'نوێکردنەوە...' : 'ڕاستکردنەوە قەبوڵ بکە'))),
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color subColor;
  const _Row({required this.label, required this.value, required this.color, required this.subColor});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [Expanded(child: Text(label, style: TextStyle(color: subColor))), Text(value, textDirection: TextDirection.ltr, style: TextStyle(color: color, fontWeight: FontWeight.bold))]),
      );
}
