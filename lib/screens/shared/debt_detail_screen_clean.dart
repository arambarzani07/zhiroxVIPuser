import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/screens/shared/debt_correction_review_screen.dart';
import 'package:zhirox/screens/shared/debt_protected_delete_screen.dart';
import 'package:zhirox/screens/shared/debt_receipt_screen.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/debt_balance.dart';
import 'package:zhirox/utils/helpers.dart';

class DebtDetailScreenClean extends StatefulWidget {
  final String debtId;
  const DebtDetailScreenClean({super.key, required this.debtId});

  @override
  State<DebtDetailScreenClean> createState() => _DebtDetailScreenCleanState();
}

class _DebtDetailScreenCleanState extends State<DebtDetailScreenClean> {
  RecordModel? debt;
  List<RecordModel> payments = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() => loading = true);
    try {
      final d = await PBService.getDebt(widget.debtId);
      final p = await PBService.getPayments(debtId: widget.debtId);
      p.sort((a, b) => a.getStringValue('created').compareTo(b.getStringValue('created')));
      if (mounted) {
        debt = d;
        payments = p;
      }
    } catch (_) {
      // UI stays calm.
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> correctDebt() async {
    final d = debt;
    if (d == null) return;
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => DebtCorrectionReviewScreen(debt: d)));
    if (saved == true) await load();
  }

  Future<void> protectedDeleteDebt() async {
    final d = debt;
    if (d == null) return;
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => DebtProtectedDeleteScreen(debt: d)));
    if (saved == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppDarkColors.card : Colors.white;
    final textColor = isDark ? AppDarkColors.textPrimary : AppColors.textPrimary;
    final subColor = isDark ? AppDarkColors.textSecondary : AppColors.textSecondary;
    final d = debt;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
        appBar: AppBar(title: const Text('وردەکاری قەرز')),
        body: RefreshIndicator(
          onRefresh: load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (loading)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else if (d == null)
                _Box(color: cardColor, child: Text('وردەکارییەکانی ئەم قەرزە لە ئێستادا بەردەست نین.', style: TextStyle(color: subColor)))
              else ...[
                _Summary(debt: d, payments: payments, color: cardColor, textColor: textColor, subColor: subColor),
                const SizedBox(height: 12),
                _Action(color: cardColor, subColor: subColor, icon: Icons.edit_note_rounded, text: 'بڕ و تێبینی ئەم قەرزە بە شێوەی پارێزراو ڕاست بکەوە.', label: 'ڕاستکردنەوە', onTap: correctDebt),
                const SizedBox(height: 12),
                _Action(color: cardColor, subColor: subColor, icon: Icons.receipt_rounded, text: 'وەصڵی ئەم قەرزە ئامادەیە بۆ بینین و پشکنین.', label: 'وەصڵ', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DebtReceiptScreen(debtId: d.id)))),
                const SizedBox(height: 12),
                _Action(color: cardColor, subColor: subColor, icon: Icons.shield_rounded, text: 'ئەم قەرزە بە شێوەی پارێزراو لە لیستە چالاکەکان بشارەوە.', label: 'سڕینەوەی پارێزراو', onTap: protectedDeleteDebt),
                const SizedBox(height: 16),
                _ChangeLog(debt: d, color: cardColor, textColor: textColor, subColor: subColor),
                const SizedBox(height: 16),
                _History(debt: d, payments: payments, color: cardColor, textColor: textColor, subColor: subColor),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final RecordModel debt;
  final List<RecordModel> payments;
  final Color color;
  final Color textColor;
  final Color subColor;
  const _Summary({required this.debt, required this.payments, required this.color, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    final name = debt.expand['customer']?.isNotEmpty == true ? debt.expand['customer']!.first.getStringValue('name') : 'کڕیار';
    final remaining = DebtBalance.remaining(debt);
    return _Box(color: color, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(name.isEmpty ? 'کڕیار' : name, style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold))), Text(DebtBalance.statusLabel(debt), style: TextStyle(color: remaining <= 0 ? AppColors.secondary : AppColors.warning, fontWeight: FontWeight.bold))]),
      const SizedBox(height: 12),
      _Line('کۆی قەرز', AppHelpers.formatCurrency(DebtBalance.amount(debt)), textColor, subColor),
      _Line('پارەی وەرگیراو', AppHelpers.formatCurrency(DebtBalance.paid(debt)), AppColors.secondary, subColor),
      _Line('قەرزی ماوە', AppHelpers.formatCurrency(remaining), remaining <= 0 ? AppColors.secondary : AppColors.danger, subColor),
      Text('ژمارەی پارە وەرگرتنەوە: ${payments.length}', style: TextStyle(color: subColor, fontSize: 12)),
    ]));
  }
}

class _ChangeLog extends StatelessWidget {
  final RecordModel debt;
  final Color color;
  final Color textColor;
  final Color subColor;
  const _ChangeLog({required this.debt, required this.color, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    final text = debt.getStringValue('description');
    final lines = text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final reasons = lines.where((line) => line.startsWith('هۆکاری گۆڕانکاری:')).toList();
    final dates = lines.where((line) => line.startsWith('بەروار:')).toList();
    if (reasons.isEmpty && dates.isEmpty) return const SizedBox.shrink();
    final reason = reasons.isNotEmpty ? reasons.last.replaceFirst('هۆکاری گۆڕانکاری:', '').trim() : 'تۆمارکراو';
    final date = dates.isNotEmpty ? dates.last.replaceFirst('بەروار:', '').trim() : '';
    return _Box(color: color, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.manage_history_rounded, color: AppColors.primary), const SizedBox(width: 8), Text('مێژووی گۆڕانکارییەکان', style: TextStyle(color: textColor, fontWeight: FontWeight.bold))]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('هۆکار', style: TextStyle(color: subColor, fontSize: 12)),
          const SizedBox(height: 4),
          Text(reason, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, height: 1.5)),
          if (date.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('بەروار: $date', style: TextStyle(color: subColor, fontSize: 12)),
          ],
        ]),
      ),
    ]));
  }
}

class _Action extends StatelessWidget {
  final Color color;
  final Color subColor;
  final IconData icon;
  final String text;
  final String label;
  final VoidCallback onTap;
  const _Action({required this.color, required this.subColor, required this.icon, required this.text, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => _Box(color: color, child: Row(children: [Icon(icon, color: AppColors.primary), const SizedBox(width: 10), Expanded(child: Text(text, style: TextStyle(color: subColor, height: 1.5))), const SizedBox(width: 8), OutlinedButton(onPressed: onTap, child: Text(label))]));
}

class _History extends StatelessWidget {
  final RecordModel debt;
  final List<RecordModel> payments;
  final Color color;
  final Color textColor;
  final Color subColor;
  const _History({required this.debt, required this.payments, required this.color, required this.textColor, required this.subColor});
  @override
  Widget build(BuildContext context) => _Box(color: color, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('مێژووی قەرز و پارە بە شێوەی چات', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
    const SizedBox(height: 12),
    _Event(title: 'قەرز پێدرا', amount: DebtBalance.amount(debt), note: debt.getStringValue('description'), textColor: textColor, subColor: subColor, debt: true),
    ...payments.map((p) => _Event(title: 'پارە وەرگیرا', amount: p.getDoubleValue('amount'), note: p.getStringValue('note'), textColor: textColor, subColor: subColor, debt: false)),
  ]));
}

class _Event extends StatelessWidget {
  final String title;
  final double amount;
  final String note;
  final Color textColor;
  final Color subColor;
  final bool debt;
  const _Event({required this.title, required this.amount, required this.note, required this.textColor, required this.subColor, required this.debt});
  @override
  Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: (debt ? AppColors.warning : AppColors.secondary).withOpacity(0.08), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Expanded(child: Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.bold))), Text(AppHelpers.formatCurrency(amount), textDirection: TextDirection.ltr)]), if (note.isNotEmpty) Text(note, style: TextStyle(color: subColor, fontSize: 12))]));
}

class _Box extends StatelessWidget {
  final Color color;
  final Widget child;
  const _Box({required this.color, required this.child});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(22)), child: child);
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color subColor;
  const _Line(this.label, this.value, this.color, this.subColor);
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [Expanded(child: Text(label, style: TextStyle(color: subColor))), Text(value, textDirection: TextDirection.ltr, style: TextStyle(color: color, fontWeight: FontWeight.bold))]));
}
