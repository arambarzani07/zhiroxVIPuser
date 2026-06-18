import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class DebtDetailScreenClean extends StatefulWidget {
  final String debtId;

  const DebtDetailScreenClean({super.key, required this.debtId});

  @override
  State<DebtDetailScreenClean> createState() => _DebtDetailScreenCleanState();
}

class _DebtDetailScreenCleanState extends State<DebtDetailScreenClean> {
  RecordModel? _debt;
  List<RecordModel> _payments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetail());
  }

  Future<void> _loadDetail() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final debt = await PBService.pb.collection('debts').getOne(widget.debtId, expand: 'customer,created_by');
      final payments = await PBService.getPayments(debtId: widget.debtId);
      if (mounted) {
        _debt = debt;
        _payments = payments;
      }
    } catch (_) {
      // Keep details screen calm; do not show internal wording.
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
        body: RefreshIndicator(
          onRefresh: _loadDetail,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.primary, AppColors.primary.withOpacity(0.72)], begin: Alignment.topRight, end: Alignment.bottomLeft),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.22), blurRadius: 20, offset: const Offset(0, 10))],
                ),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
                      const SizedBox(width: 6),
                      const Expanded(child: Text('وردەکاری قەرز', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else if (debt == null)
                _QuietEmpty(cardColor: cardColor, textColor: textColor, subColor: subColor)
              else ...[
                _DebtSummaryCard(debt: debt, payments: _payments, cardColor: cardColor, textColor: textColor, subColor: subColor),
                const SizedBox(height: 16),
                Text('مێژووی پارە وەرگرتنەوە', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (_payments.isEmpty)
                  _NoPayments(cardColor: cardColor, textColor: textColor, subColor: subColor)
                else
                  ..._payments.map((payment) => _PaymentCard(payment: payment, cardColor: cardColor, textColor: textColor, subColor: subColor)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DebtSummaryCard extends StatelessWidget {
  final RecordModel debt;
  final List<RecordModel> payments;
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const _DebtSummaryCard({required this.debt, required this.payments, required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    final amount = debt.getDoubleValue('amount');
    final remaining = debt.getDoubleValue('remaining');
    final paid = (amount - remaining).clamp(0, double.infinity).toDouble();
    final status = debt.getStringValue('status');
    final isPaid = status == 'paid' || remaining <= 0;
    final customer = debt.expand['customer']?.isNotEmpty == true ? debt.expand['customer']!.first : null;
    final customerName = customer?.getStringValue('name') ?? 'کڕیار';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isPaid ? Icons.verified_rounded : Icons.receipt_long_rounded, color: isPaid ? AppColors.secondary : AppColors.warning),
              const SizedBox(width: 8),
              Expanded(child: Text(customerName, style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold))),
              _StatusPill(isPaid: isPaid),
            ],
          ),
          const SizedBox(height: 16),
          _MoneyRow(label: 'کۆی قەرز', value: AppHelpers.formatCurrency(amount), color: textColor),
          _MoneyRow(label: 'پارەی وەرگیراو', value: AppHelpers.formatCurrency(paid), color: AppColors.secondary),
          _MoneyRow(label: 'قەرزی ماوە', value: AppHelpers.formatCurrency(remaining), color: isPaid ? AppColors.secondary : AppColors.danger),
          const SizedBox(height: 8),
          Text('ژمارەی پارە وەرگرتنەوە: ${payments.length}', style: TextStyle(color: subColor, fontSize: 12)),
          if (debt.getStringValue('description').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(debt.getStringValue('description'), style: TextStyle(color: subColor, height: 1.6)),
          ],
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final RecordModel payment;
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const _PaymentCard({required this.payment, required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    final amount = payment.getDoubleValue('amount');
    final note = payment.getStringValue('note');
    final date = payment.getStringValue('created');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.secondary.withOpacity(0.10), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.payments_rounded, color: AppColors.secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppHelpers.formatCurrency(amount), textDirection: TextDirection.ltr, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                if (note.isNotEmpty) Text(note, style: TextStyle(color: subColor, fontSize: 12), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Text(AppHelpers.formatDate(date), style: TextStyle(color: subColor, fontSize: 11)),
        ],
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MoneyRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          const Spacer(),
          Text(value, textDirection: TextDirection.ltr, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool isPaid;

  const _StatusPill({required this.isPaid});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: (isPaid ? AppColors.secondary : AppColors.warning).withOpacity(0.10), borderRadius: BorderRadius.circular(99)),
      child: Text(isPaid ? 'تەواوە' : 'چالاکە', style: TextStyle(color: isPaid ? AppColors.secondary : AppColors.warning, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

class _NoPayments extends StatelessWidget {
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const _NoPayments({required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(18)),
      child: Text('هێشتا پارەیەک بۆ ئەم قەرزە وەرنەگیراوە', style: TextStyle(color: subColor)),
    );
  }
}

class _QuietEmpty extends StatelessWidget {
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const _QuietEmpty({required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text('وردەکارییەکانی ئەم قەرزە لە ئێستادا بەردەست نین.', style: TextStyle(color: subColor))),
        ],
      ),
    );
  }
}
