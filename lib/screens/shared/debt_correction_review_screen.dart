import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/debt_balance.dart';
import 'package:zhirox/utils/helpers.dart';

class DebtCorrectionReviewScreen extends StatefulWidget {
  final RecordModel debt;
  const DebtCorrectionReviewScreen({super.key, required this.debt});

  @override
  State<DebtCorrectionReviewScreen> createState() => _DebtCorrectionReviewScreenState();
}

class _DebtCorrectionReviewScreenState extends State<DebtCorrectionReviewScreen> {
  late final TextEditingController amountCtrl;
  late final TextEditingController noteCtrl;
  late final TextEditingController reasonCtrl;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    amountCtrl = TextEditingController(text: DebtBalance.amount(widget.debt).toStringAsFixed(0));
    noteCtrl = TextEditingController(text: widget.debt.getStringValue('description'));
    reasonCtrl = TextEditingController();
  }

  @override
  void dispose() {
    amountCtrl.dispose();
    noteCtrl.dispose();
    reasonCtrl.dispose();
    super.dispose();
  }

  double amount() => double.tryParse(amountCtrl.text.replaceAll(',', '').trim()) ?? 0;
  double paid() => DebtBalance.paid(widget.debt);
  double left() => (amount() - paid()).clamp(0, double.infinity).toDouble();

  String noteWithReason() {
    final note = noteCtrl.text.trim().isEmpty ? 'قەرزی نوێ' : noteCtrl.text.trim();
    final now = DateTime.now();
    final date = '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
    return '$note\nهۆکاری گۆڕانکاری: ${reasonCtrl.text.trim()}\nبەروار: $date';
  }

  String reviewText() {
    return 'کۆی قەرزی نوێ: ${AppHelpers.formatCurrency(amount())}\n'
        'پارەی پێشتر وەرگیراو: ${AppHelpers.formatCurrency(paid())}\n'
        'قەرزی ماوەی نوێ: ${AppHelpers.formatCurrency(left())}\n'
        'هۆکار: ${reasonCtrl.text.trim()}';
  }

  Future<void> save() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isManager && !auth.canEditDebts) {
      AppHelpers.showSnackBar(context, AppUserMessages.needsManagerApproval, isError: true);
      return;
    }
    if (widget.debt.getBoolValue('is_deleted')) {
      AppHelpers.showSnackBar(context, 'ئەم قەرزە پێش ڕاستکردنەوە پێویستی بە گەڕاندنەوە هەیە', isError: true);
      return;
    }
    if (amount() <= 0) {
      AppHelpers.showSnackBar(context, 'بڕی قەرز دەبێت لە سفر زیاتر بێت', isError: true);
      return;
    }
    if (amount() < paid()) {
      AppHelpers.showSnackBar(context, 'بڕی نوێ نابێت لە پارەی پێشتر وەرگیراو کەمتر بێت', isError: true);
      return;
    }
    if (reasonCtrl.text.trim().isEmpty) {
      AppHelpers.showSnackBar(context, 'هۆکاری گۆڕانکاری بنووسە', isError: true);
      return;
    }
    final ok = await AppHelpers.showConfirmDialog(
      context,
      title: 'پێشبینینی ڕاستکردنەوە',
      message: '${reviewText()}\n\nدڵنیایت ئەم ڕاستکردنەوەیە قەبوڵ دەکەیت؟',
    );
    if (!ok || !mounted) return;
    setState(() => saving = true);
    try {
      await PBService.pb.collection('debts').update(widget.debt.id, body: {
        'amount': amount(),
        'remaining': left(),
        'status': left() <= 0 ? 'paid' : 'active',
        'description': noteWithReason(),
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
    final card = isDark ? AppDarkColors.card : Colors.white;
    final text = isDark ? AppDarkColors.textPrimary : AppColors.textPrimary;
    final sub = isDark ? AppDarkColors.textSecondary : AppColors.textSecondary;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
        appBar: AppBar(title: const Text('ڕاستکردنەوەی قەرز')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          _Box(color: card, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('زانیاری قەرز', style: TextStyle(color: text, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(controller: amountCtrl, keyboardType: TextInputType.number, textDirection: TextDirection.ltr, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'کۆی قەرز', suffixText: 'د.ع')),
            const SizedBox(height: 10),
            TextField(controller: noteCtrl, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'تێبینی')),
            const SizedBox(height: 10),
            TextField(controller: reasonCtrl, minLines: 2, maxLines: 3, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'هۆکاری گۆڕانکاری')),
          ])),
          const SizedBox(height: 14),
          _Box(color: card, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('پێشبینینی پێش قەبوڵکردن', style: TextStyle(color: text, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _Row(label: 'کۆی قەرزی نوێ', value: AppHelpers.formatCurrency(amount()), color: text, subColor: sub),
            _Row(label: 'پارەی پێشتر وەرگیراو', value: AppHelpers.formatCurrency(paid()), color: AppColors.secondary, subColor: sub),
            _Row(label: 'قەرزی ماوەی نوێ', value: AppHelpers.formatCurrency(left()), color: left() <= 0 ? AppColors.secondary : AppColors.danger, subColor: sub),
            if (reasonCtrl.text.trim().isNotEmpty) Text('هۆکار: ${reasonCtrl.text.trim()}', style: TextStyle(color: sub, height: 1.5)),
          ])),
          const SizedBox(height: 18),
          SizedBox(height: 52, child: FilledButton.icon(onPressed: saving ? null : save, icon: const Icon(Icons.check_rounded), label: Text(saving ? 'نوێکردنەوە...' : 'ڕاستکردنەوە قەبوڵ بکە'))),
        ]),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  final Color color;
  final Widget child;
  const _Box({required this.color, required this.child});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(22)), child: child);
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color subColor;
  const _Row({required this.label, required this.value, required this.color, required this.subColor});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [Expanded(child: Text(label, style: TextStyle(color: subColor))), Text(value, textDirection: TextDirection.ltr, style: TextStyle(color: color, fontWeight: FontWeight.bold))]));
}
