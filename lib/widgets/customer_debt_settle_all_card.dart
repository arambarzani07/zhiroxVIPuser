import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/debt_balance.dart';
import 'package:zhirox/utils/helpers.dart';

class CustomerDebtSettleAllCard extends StatefulWidget {
  final List<RecordModel> debts;
  final Color cardColor;
  final Color textColor;
  final Color subColor;
  final VoidCallback onSaved;

  const CustomerDebtSettleAllCard({
    super.key,
    required this.debts,
    required this.cardColor,
    required this.textColor,
    required this.subColor,
    required this.onSaved,
  });

  @override
  State<CustomerDebtSettleAllCard> createState() => _CustomerDebtSettleAllCardState();
}

class _CustomerDebtSettleAllCardState extends State<CustomerDebtSettleAllCard> {
  bool _saving = false;

  List<RecordModel> get _activeDebts => widget.debts.where(DebtBalance.isActive).toList();

  double get _remaining => DebtBalance.totalRemaining(_activeDebts);

  Future<void> _settleAll() async {
    if (_saving) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isManager) {
      AppHelpers.showSnackBar(context, AppUserMessages.needsManagerApproval, isError: true);
      return;
    }
    if (_activeDebts.isEmpty) return;

    final confirm = await AppHelpers.showConfirmDialog(
      context,
      title: 'هەموو قەرز پاککردنەوە',
      message: 'هەموو قەرزی ماوەی ئەم کڕیارە بە بڕیاری بەڕێوەبەر دادەخرێت. دڵنیایت؟',
    );
    if (!confirm || !mounted) return;

    setState(() => _saving = true);
    try {
      for (final debt in _activeDebts) {
        await PBService.pb.collection('debts').update(debt.id, body: {
          'remaining': 0,
          'status': 'paid',
        });
      }
      widget.onSaved();
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'قەرزی ماوە نوێکرایەوە');
    } catch (_) {
      if (!mounted) return;
      AppHelpers.showSnackBar(context, AppUserMessages.protectedOffline);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _activeDebts.length;
    final hasDebt = activeCount > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: widget.cardColor, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(hasDebt ? Icons.cleaning_services_rounded : Icons.verified_rounded, color: hasDebt ? AppColors.warning : AppColors.secondary),
          const SizedBox(width: 8),
          Expanded(child: Text('هەموو قەرز پاککردنەوە', style: TextStyle(color: widget.textColor, fontWeight: FontWeight.bold, fontSize: 16))),
        ]),
        const SizedBox(height: 10),
        Text(hasDebt ? 'هەموو قەرزی ماوەی کڕیار بە بڕیاری بەڕێوەبەر دادەخرێت.' : 'هیچ قەرزی ماوە بۆ پاککردنەوە نییە.', style: TextStyle(color: widget.subColor, height: 1.5, fontSize: 12)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _MiniInfo(label: 'قەرزی چالاک', value: '$activeCount', color: hasDebt ? AppColors.warning : AppColors.secondary, subColor: widget.subColor)),
          const SizedBox(width: 10),
          Expanded(child: _MiniInfo(label: 'قەرزی ماوە', value: AppHelpers.formatCurrency(_remaining), color: hasDebt ? AppColors.danger : AppColors.secondary, subColor: widget.subColor)),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton.icon(
            onPressed: hasDebt && !_saving ? _settleAll : null,
            icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.done_all_rounded),
            label: Text(_saving ? 'نوێکردنەوە...' : 'هەموو قەرز پاک بکەوە'),
          ),
        ),
      ]),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color subColor;

  const _MiniInfo({required this.label, required this.value, required this.color, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: subColor, fontSize: 11)),
        const SizedBox(height: 6),
        Text(value, textDirection: TextDirection.ltr, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}
