import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/debt_balance.dart';
import 'package:zhirox/utils/helpers.dart';

class CustomerStatementScreen extends StatefulWidget {
  final String? customerId;

  const CustomerStatementScreen({super.key, this.customerId});

  @override
  State<CustomerStatementScreen> createState() => _CustomerStatementScreenState();
}

class _CustomerStatementScreenState extends State<CustomerStatementScreen> {
  List<RecordModel> _customers = [];
  List<RecordModel> _debts = [];
  List<RecordModel> _payments = [];
  String? _customerId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _customerId = widget.customerId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStatement());
  }

  Future<void> _loadStatement() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    final adminId = auth.adminId.isNotEmpty ? auth.adminId : auth.userId;
    try {
      final customers = await PBService.getUsers(role: 'customer', adminId: adminId, approved: true);
      final selectedId = _customerId ?? (customers.isNotEmpty ? customers.first.id : null);
      var debts = <RecordModel>[];
      var payments = <RecordModel>[];
      if (selectedId != null && selectedId.isNotEmpty) {
        debts = await PBService.getDebts(customerId: selectedId, perPage: 500);
        payments = await PBService.getPayments(customerId: selectedId);
        payments.sort((a, b) => a.getStringValue('created').compareTo(b.getStringValue('created')));
      }
      if (mounted) {
        _customers = customers;
        _customerId = selectedId;
        _debts = debts;
        _payments = payments;
      }
    } catch (_) {
      // Keep last visible statement calmly.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  RecordModel? _selectedCustomer() {
    final id = _customerId;
    if (id == null) return null;
    for (final customer in _customers) {
      if (customer.id == id) return customer;
    }
    return null;
  }

  Future<void> _changeCustomer(String? value) async {
    if (value == null || value.isEmpty) return;
    setState(() => _customerId = value);
    await _loadStatement();
  }

  List<_StatementEvent> _events() {
    final events = <_StatementEvent>[
      ..._debts.map(_StatementEvent.debt),
      ..._payments.map(_StatementEvent.payment),
    ];
    events.sort((a, b) => a.created.compareTo(b.created));
    return events;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppDarkColors.card : Colors.white;
    final textColor = isDark ? AppDarkColors.textPrimary : AppColors.textPrimary;
    final subColor = isDark ? AppDarkColors.textSecondary : AppColors.textSecondary;
    final customer = _selectedCustomer();
    final totalDebt = _debts.fold<double>(0, (sum, debt) => sum + DebtBalance.amount(debt));
    final totalPaid = _payments.fold<double>(0, (sum, payment) => sum + payment.getDoubleValue('amount'));
    final totalRemaining = DebtBalance.totalRemaining(_debts);
    final activeCount = DebtBalance.activeCount(_debts);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
        body: RefreshIndicator(
          onRefresh: _loadStatement,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatementHero(customerName: customer?.getStringValue('name') ?? 'کڕیار'),
              const SizedBox(height: 16),
              if (_isLoading)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('کڕیار', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _customerId,
                      decoration: const InputDecoration(labelText: 'کڕیارێک هەڵبژێرە'),
                      items: _customers.map((customer) => DropdownMenuItem(value: customer.id, child: Text(customer.getStringValue('name').isEmpty ? 'کڕیار' : customer.getStringValue('name')))).toList(),
                      onChanged: _changeCustomer,
                    ),
                    if (customer != null && customer.getStringValue('phone').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(customer.getStringValue('phone'), textDirection: TextDirection.ltr, style: TextStyle(color: subColor)),
                    ],
                  ]),
                ),
                const SizedBox(height: 14),
                _StatementSummaryCard(
                  totalDebt: totalDebt,
                  totalPaid: totalPaid,
                  totalRemaining: totalRemaining,
                  activeCount: activeCount,
                  cardColor: cardColor,
                  textColor: textColor,
                  subColor: subColor,
                ),
                const SizedBox(height: 14),
                _StatementTimelineCard(events: _events(), cardColor: cardColor, textColor: textColor, subColor: subColor),
                const SizedBox(height: 14),
                _ShareReadyCard(cardColor: cardColor, subColor: subColor),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatementHero extends StatelessWidget {
  final String customerName;

  const _StatementHero({required this.customerName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.primary, AppColors.primary.withOpacity(0.72)], begin: Alignment.topRight, end: Alignment.bottomLeft),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.22), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(children: [
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
          const SizedBox(width: 6),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('کەشف حساب', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(customerName, style: TextStyle(color: Colors.white.withOpacity(0.78), fontSize: 13)),
          ])),
        ]),
      ),
    );
  }
}

class _StatementSummaryCard extends StatelessWidget {
  final double totalDebt;
  final double totalPaid;
  final double totalRemaining;
  final int activeCount;
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const _StatementSummaryCard({required this.totalDebt, required this.totalPaid, required this.totalRemaining, required this.activeCount, required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.summarize_rounded, color: AppColors.primary), const SizedBox(width: 8), Text('کورتەی کەشف حساب', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16))]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _SummaryTile(label: 'کۆی قەرز', value: AppHelpers.formatCurrency(totalDebt), color: textColor, subColor: subColor)),
          const SizedBox(width: 10),
          Expanded(child: _SummaryTile(label: 'پارەی وەرگیراو', value: AppHelpers.formatCurrency(totalPaid), color: AppColors.secondary, subColor: subColor)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _SummaryTile(label: 'قەرزی ماوە', value: AppHelpers.formatCurrency(totalRemaining), color: totalRemaining <= 0 ? AppColors.secondary : AppColors.danger, subColor: subColor)),
          const SizedBox(width: 10),
          Expanded(child: _SummaryTile(label: 'قەرزی چالاک', value: '$activeCount', color: AppColors.warning, subColor: subColor)),
        ]),
      ]),
    );
  }
}

class _StatementTimelineCard extends StatelessWidget {
  final List<_StatementEvent> events;
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const _StatementTimelineCard({required this.events, required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.receipt_long_rounded, color: AppColors.primary), const SizedBox(width: 8), Text('مێژووی کەشف حساب', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16))]),
        const SizedBox(height: 12),
        if (events.isEmpty)
          Text('هێشتا هیچ کردارێک بۆ ئەم کڕیارە تۆمار نەکراوە.', style: TextStyle(color: subColor, height: 1.6))
        else
          ...events.map((event) => _StatementEventRow(event: event, textColor: textColor, subColor: subColor)),
      ]),
    );
  }
}

class _StatementEventRow extends StatelessWidget {
  final _StatementEvent event;
  final Color textColor;
  final Color subColor;

  const _StatementEventRow({required this.event, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    final isDebt = event.type == _StatementEventType.debt;
    final color = isDebt ? AppColors.warning : AppColors.secondary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.12))),
      child: Row(children: [
        Icon(isDebt ? Icons.add_card_rounded : Icons.payments_rounded, color: color),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isDebt ? 'قەرز پێدرا' : 'پارە وەرگیرا', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
          if (event.note.isNotEmpty) Text(event.note, style: TextStyle(color: subColor, fontSize: 12), overflow: TextOverflow.ellipsis),
          Text(AppHelpers.formatDate(event.created), style: TextStyle(color: subColor, fontSize: 11)),
        ])),
        Text(AppHelpers.formatCurrency(event.amount), textDirection: TextDirection.ltr, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

class _ShareReadyCard extends StatelessWidget {
  final Color cardColor;
  final Color subColor;

  const _ShareReadyCard({required this.cardColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Row(children: [
        const Icon(Icons.verified_rounded, color: AppColors.secondary),
        const SizedBox(width: 10),
        Expanded(child: Text('کەشف حساب درووستکرا و ئامادەیە بۆ بینین و پشکنین.', style: TextStyle(color: subColor, height: 1.6))),
      ]),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color subColor;

  const _SummaryTile({required this.label, required this.value, required this.color, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.07), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: subColor, fontSize: 11)),
        const SizedBox(height: 6),
        Text(value, textDirection: TextDirection.ltr, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
      ]),
    );
  }
}

enum _StatementEventType { debt, payment }

class _StatementEvent {
  final _StatementEventType type;
  final double amount;
  final String note;
  final String created;

  const _StatementEvent({required this.type, required this.amount, required this.note, required this.created});

  factory _StatementEvent.debt(RecordModel debt) {
    return _StatementEvent(type: _StatementEventType.debt, amount: DebtBalance.amount(debt), note: debt.getStringValue('description'), created: debt.getStringValue('created'));
  }

  factory _StatementEvent.payment(RecordModel payment) {
    return _StatementEvent(type: _StatementEventType.payment, amount: payment.getDoubleValue('amount'), note: payment.getStringValue('note'), created: payment.getStringValue('created'));
  }
}
