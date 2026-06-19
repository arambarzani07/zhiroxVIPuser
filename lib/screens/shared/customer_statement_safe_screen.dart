import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/debt_balance.dart';
import 'package:zhirox/utils/helpers.dart';

class CustomerStatementSafeScreen extends StatefulWidget {
  final String customerId;
  const CustomerStatementSafeScreen({super.key, required this.customerId});

  @override
  State<CustomerStatementSafeScreen> createState() => _CustomerStatementSafeScreenState();
}

class _CustomerStatementSafeScreenState extends State<CustomerStatementSafeScreen> {
  RecordModel? customer;
  List<RecordModel> debts = [];
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
      customer = await PBService.getUser(widget.customerId);
      final allDebts = await PBService.getDebts(customerId: widget.customerId, perPage: 500);
      debts = DebtBalance.visible(allDebts).toList();
      final debtIds = debts.map((debt) => debt.id).toSet();
      final allPayments = await PBService.getPayments(customerId: widget.customerId);
      payments = allPayments.where((payment) => debtIds.contains(payment.getStringValue('debt'))).toList();
      payments.sort((a, b) => a.getStringValue('created').compareTo(b.getStringValue('created')));
    } catch (_) {
      debts = [];
      payments = [];
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<_StatementItem> items() {
    final list = <_StatementItem>[
      ...debts.map((debt) => _StatementItem.debt(debt)),
      ...payments.map((payment) => _StatementItem.payment(payment)),
    ];
    list.sort((a, b) => a.created.compareTo(b.created));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? AppDarkColors.card : Colors.white;
    final text = isDark ? AppDarkColors.textPrimary : AppColors.textPrimary;
    final sub = isDark ? AppDarkColors.textSecondary : AppColors.textSecondary;
    final totalDebt = debts.fold<double>(0, (sum, debt) => sum + DebtBalance.amount(debt));
    final totalPaid = payments.fold<double>(0, (sum, payment) => sum + payment.getDoubleValue('amount'));
    final totalRemaining = DebtBalance.totalRemaining(debts);
    final activeCount = DebtBalance.activeCount(debts);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
        appBar: AppBar(title: const Text('کەشف حساب')),
        body: RefreshIndicator(
          onRefresh: load,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            _Hero(name: customer?.getStringValue('name') ?? 'کڕیار'),
            const SizedBox(height: 14),
            if (loading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else ...[
              _Summary(card: card, text: text, sub: sub, totalDebt: totalDebt, totalPaid: totalPaid, totalRemaining: totalRemaining, activeCount: activeCount),
              const SizedBox(height: 14),
              _Timeline(card: card, text: text, sub: sub, items: items()),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final String name;
  const _Hero({required this.name});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.primary, AppColors.primary.withOpacity(0.72)]), borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('کەشف حسابی پارێزراو', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
          const SizedBox(height: 4),
          Text(name, style: TextStyle(color: Colors.white.withOpacity(0.78))),
        ]),
      );
}

class _Summary extends StatelessWidget {
  final Color card;
  final Color text;
  final Color sub;
  final double totalDebt;
  final double totalPaid;
  final double totalRemaining;
  final int activeCount;
  const _Summary({required this.card, required this.text, required this.sub, required this.totalDebt, required this.totalPaid, required this.totalRemaining, required this.activeCount});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('کورتەی کەشف حساب', style: TextStyle(color: text, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _Row(label: 'کۆی قەرز', value: AppHelpers.formatCurrency(totalDebt), color: text, sub: sub),
          _Row(label: 'پارەی وەرگیراو', value: AppHelpers.formatCurrency(totalPaid), color: AppColors.secondary, sub: sub),
          _Row(label: 'قەرزی ماوە', value: AppHelpers.formatCurrency(totalRemaining), color: totalRemaining <= 0 ? AppColors.secondary : AppColors.danger, sub: sub),
          _Row(label: 'قەرزی چالاک', value: '$activeCount', color: AppColors.warning, sub: sub),
        ]),
      );
}

class _Timeline extends StatelessWidget {
  final Color card;
  final Color text;
  final Color sub;
  final List<_StatementItem> items;
  const _Timeline({required this.card, required this.text, required this.sub, required this.items});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('مێژووی کەشف حساب', style: TextStyle(color: text, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Text('هێشتا هیچ کردارێک بۆ ئەم کڕیارە تۆمار نەکراوە.', style: TextStyle(color: sub))
          else
            ...items.map((item) => _ItemRow(item: item, text: text, sub: sub)),
        ]),
      );
}

class _ItemRow extends StatelessWidget {
  final _StatementItem item;
  final Color text;
  final Color sub;
  const _ItemRow({required this.item, required this.text, required this.sub});

  @override
  Widget build(BuildContext context) {
    final color = item.isDebt ? AppColors.warning : AppColors.secondary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(item.isDebt ? Icons.add_card_rounded : Icons.payments_rounded, color: color),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.isDebt ? 'قەرز پێدرا' : 'پارە وەرگیرا', style: TextStyle(color: text, fontWeight: FontWeight.bold)),
          if (item.note.isNotEmpty) Text(item.note, style: TextStyle(color: sub, fontSize: 12), overflow: TextOverflow.ellipsis),
          Text(AppHelpers.formatDate(item.created), style: TextStyle(color: sub, fontSize: 11)),
        ])),
        Text(AppHelpers.formatCurrency(item.amount), textDirection: TextDirection.ltr, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color sub;
  const _Row({required this.label, required this.value, required this.color, required this.sub});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [Expanded(child: Text(label, style: TextStyle(color: sub))), Text(value, textDirection: TextDirection.ltr, style: TextStyle(color: color, fontWeight: FontWeight.bold))]),
      );
}

class _StatementItem {
  final bool isDebt;
  final double amount;
  final String note;
  final String created;
  const _StatementItem({required this.isDebt, required this.amount, required this.note, required this.created});

  factory _StatementItem.debt(RecordModel debt) => _StatementItem(isDebt: true, amount: DebtBalance.amount(debt), note: debt.getStringValue('description'), created: debt.getStringValue('created'));
  factory _StatementItem.payment(RecordModel payment) => _StatementItem(isDebt: false, amount: payment.getDoubleValue('amount'), note: payment.getStringValue('note'), created: payment.getStringValue('created'));
}
