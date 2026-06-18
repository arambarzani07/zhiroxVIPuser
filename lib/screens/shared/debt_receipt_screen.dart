import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/debt_balance.dart';
import 'package:zhirox/utils/helpers.dart';

class DebtReceiptScreen extends StatefulWidget {
  final String debtId;

  const DebtReceiptScreen({super.key, required this.debtId});

  @override
  State<DebtReceiptScreen> createState() => _DebtReceiptScreenState();
}

class _DebtReceiptScreenState extends State<DebtReceiptScreen> {
  RecordModel? _debt;
  List<RecordModel> _payments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadReceipt());
  }

  Future<void> _loadReceipt() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final debt = await PBService.getDebt(widget.debtId);
      final payments = await PBService.getPayments(debtId: widget.debtId);
      if (mounted) {
        _debt = debt;
        _payments = payments;
      }
    } catch (_) {
      // Keep receipt calm and preserve visible state.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppDarkColors.card : Colors.white;
    final textColor = isDark ? AppDarkColors.textPrimary : AppColors.textPrimary;
    final subColor = isDark ? AppDarkColors.textSecondary : AppColors.textSecondary;
    final debt = _debt;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
        appBar: AppBar(title: const Text('وەصڵ')),
        body: RefreshIndicator(
          onRefresh: _loadReceipt,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_isLoading)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else if (debt == null)
                _QuietReceipt(cardColor: cardColor, subColor: subColor)
              else
                _ReceiptCard(debt: debt, payments: _payments, cardColor: cardColor, textColor: textColor, subColor: subColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  final RecordModel debt;
  final List<RecordModel> payments;
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const _ReceiptCard({required this.debt, required this.payments, required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    final customer = debt.expand['customer']?.isNotEmpty == true ? debt.expand['customer']!.first : null;
    final createdBy = debt.expand['created_by']?.isNotEmpty == true ? debt.expand['created_by']!.first : null;
    final customerName = customer?.getStringValue('name') ?? 'کڕیار';
    final customerPhone = customer?.getStringValue('phone') ?? '';
    final marketName = customer?.getStringValue('market_name').isNotEmpty == true
        ? customer!.getStringValue('market_name')
        : (createdBy?.getStringValue('market_name') ?? 'مارکێت');
    final totalDebt = DebtBalance.amount(debt);
    final totalPaid = payments.fold<double>(0, (sum, payment) => sum + payment.getDoubleValue('amount'));
    final remaining = DebtBalance.remaining(debt);
    final isPaid = DebtBalance.isPaid(debt);
    final receiptNo = 'ZRX-${debt.id.length > 8 ? debt.id.substring(0, 8).toUpperCase() : debt.id.toUpperCase()}';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.primary.withOpacity(0.10))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Column(children: [
            const Icon(Icons.verified_rounded, color: AppColors.secondary, size: 42),
            const SizedBox(height: 8),
            Text('وەصڵ', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 24)),
            const SizedBox(height: 4),
            Text(marketName, style: TextStyle(color: subColor, fontSize: 13)),
          ]),
        ),
        const SizedBox(height: 18),
        _ReceiptRow(label: 'ژمارەی وەصڵ', value: receiptNo, subColor: subColor, ltr: true),
        _ReceiptRow(label: 'کڕیار', value: customerName, subColor: subColor),
        if (customerPhone.isNotEmpty) _ReceiptRow(label: 'ژمارەی مۆبایل', value: customerPhone, subColor: subColor, ltr: true),
        _ReceiptRow(label: 'بەروار', value: AppHelpers.formatDate(debt.getStringValue('created')), subColor: subColor),
        const Divider(height: 26),
        _AmountLine(label: 'کۆی قەرز', value: AppHelpers.formatCurrency(totalDebt), color: textColor),
        _AmountLine(label: 'پارەی وەرگیراو', value: AppHelpers.formatCurrency(totalPaid), color: AppColors.secondary),
        _AmountLine(label: 'قەرزی ماوە', value: AppHelpers.formatCurrency(remaining), color: isPaid ? AppColors.secondary : AppColors.danger),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: (isPaid ? AppColors.secondary : AppColors.warning).withOpacity(0.08), borderRadius: BorderRadius.circular(16)),
          child: Text(isPaid ? 'دۆخ: قەرز تەواوە' : 'دۆخ: قەرزی ماوە', style: TextStyle(color: isPaid ? AppColors.secondary : AppColors.warning, fontWeight: FontWeight.bold)),
        ),
        if (debt.getStringValue('description').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(debt.getStringValue('description'), style: TextStyle(color: subColor, height: 1.6)),
        ],
        const SizedBox(height: 16),
        Row(children: [
          const Icon(Icons.shield_rounded, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('ئەم وەصڵە بۆ پشکنینی هەژماری قەرزی کڕیار ئامادەکراوە.', style: TextStyle(color: subColor, height: 1.5, fontSize: 12))),
        ]),
      ]),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final Color subColor;
  final bool ltr;

  const _ReceiptRow({required this.label, required this.value, required this.subColor, this.ltr = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(children: [
        Text(label, style: TextStyle(color: subColor, fontSize: 13)),
        const Spacer(),
        Flexible(child: Text(value, textDirection: ltr ? TextDirection.ltr : TextDirection.rtl, textAlign: TextAlign.left, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

class _AmountLine extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _AmountLine({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(value, textDirection: TextDirection.ltr, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

class _QuietReceipt extends StatelessWidget {
  final Color cardColor;
  final Color subColor;

  const _QuietReceipt({required this.cardColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Text('وەصڵەکە لە ئێستادا بەردەست نییە.', style: TextStyle(color: subColor, height: 1.6)),
    );
  }
}
