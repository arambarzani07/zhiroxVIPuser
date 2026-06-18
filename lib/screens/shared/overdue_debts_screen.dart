import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/shared/debt_detail_screen_clean.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/debt_balance.dart';
import 'package:zhirox/utils/helpers.dart';

class OverdueDebtsScreen extends StatefulWidget {
  const OverdueDebtsScreen({super.key});

  @override
  State<OverdueDebtsScreen> createState() => _OverdueDebtsScreenState();
}

class _OverdueDebtsScreenState extends State<OverdueDebtsScreen> {
  List<RecordModel> _debts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDebts());
  }

  Future<void> _loadDebts() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    final adminId = auth.adminId.isNotEmpty ? auth.adminId : auth.userId;
    try {
      final debts = await PBService.getDebts(adminId: adminId, perPage: 500);
      final overdue = debts.where(_isOverdue).toList()
        ..sort((a, b) => _dueDate(a).compareTo(_dueDate(b)));
      if (mounted) _debts = overdue;
    } catch (_) {
      // Keep last visible state calmly.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isOverdue(RecordModel debt) {
    if (!DebtBalance.isActive(debt)) return false;
    final due = _dueDate(debt);
    if (due == null) return false;
    final today = DateTime.now();
    final dayStart = DateTime(today.year, today.month, today.day);
    return due.isBefore(dayStart);
  }

  DateTime? _dueDate(RecordModel debt) {
    final raw = debt.getStringValue('due_date');
    if (raw.isEmpty) return null;
    try {
      final parsed = DateTime.parse(raw).toLocal();
      return DateTime(parsed.year, parsed.month, parsed.day);
    } catch (_) {
      return null;
    }
  }

  int _lateDays(RecordModel debt) {
    final due = _dueDate(debt);
    if (due == null) return 0;
    final today = DateTime.now();
    final dayStart = DateTime(today.year, today.month, today.day);
    return dayStart.difference(due).inDays.clamp(0, 99999);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppDarkColors.card : Colors.white;
    final textColor = isDark ? AppDarkColors.textPrimary : AppColors.textPrimary;
    final subColor = isDark ? AppDarkColors.textSecondary : AppColors.textSecondary;
    final totalRemaining = DebtBalance.totalRemaining(_debts);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
        body: RefreshIndicator(
          onRefresh: _loadDebts,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _OverdueHero(count: _debts.length),
              const SizedBox(height: 14),
              _OverdueSummary(totalRemaining: totalRemaining, count: _debts.length, cardColor: cardColor, textColor: textColor, subColor: subColor),
              const SizedBox(height: 14),
              if (_isLoading)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else if (_debts.isEmpty)
                _NoOverdueCard(cardColor: cardColor, textColor: textColor, subColor: subColor)
              else
                ..._debts.map((debt) => _OverdueDebtCard(debt: debt, lateDays: _lateDays(debt), cardColor: cardColor, textColor: textColor, subColor: subColor)),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverdueHero extends StatelessWidget {
  final int count;

  const _OverdueHero({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.danger, AppColors.danger.withOpacity(0.72)], begin: Alignment.topRight, end: Alignment.bottomLeft),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: AppColors.danger.withOpacity(0.20), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(children: [
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
          const SizedBox(width: 6),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('قەرزی دواکەوتوو', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('$count قەرز پێویستی بە چاودێری هەیە', style: TextStyle(color: Colors.white.withOpacity(0.78), fontSize: 13)),
          ])),
        ]),
      ),
    );
  }
}

class _OverdueSummary extends StatelessWidget {
  final double totalRemaining;
  final int count;
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const _OverdueSummary({required this.totalRemaining, required this.count, required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('کۆی قەرزی دواکەوتوو', style: TextStyle(color: subColor, fontSize: 12)),
          const SizedBox(height: 4),
          Text(AppHelpers.formatCurrency(totalRemaining), textDirection: TextDirection.ltr, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 17)),
        ])),
        Text('$count', style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 20)),
      ]),
    );
  }
}

class _OverdueDebtCard extends StatelessWidget {
  final RecordModel debt;
  final int lateDays;
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const _OverdueDebtCard({required this.debt, required this.lateDays, required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    final customer = debt.expand['customer']?.isNotEmpty == true ? debt.expand['customer']!.first : null;
    final name = customer?.getStringValue('name') ?? 'کڕیار';
    final phone = customer?.getStringValue('phone') ?? '';
    final dueDate = debt.getStringValue('due_date');

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DebtDetailScreenClean(debtId: debt.id))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.10), borderRadius: BorderRadius.circular(16)),
              child: Center(child: Text(name.isEmpty ? 'ک' : name[0], style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 20))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              if (phone.isNotEmpty) Text(phone, textDirection: TextDirection.ltr, style: TextStyle(color: subColor, fontSize: 12)),
            ])),
            Text(AppHelpers.formatCurrency(DebtBalance.remaining(debt)), textDirection: TextDirection.ltr, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.event_busy_rounded, color: AppColors.warning, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text('بەرواری دانەوە: ${AppHelpers.formatDate(dueDate)}', style: TextStyle(color: subColor, fontSize: 12))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.10), borderRadius: BorderRadius.circular(99)),
              child: Text('$lateDays ڕۆژ دواکەوتوو', style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _NoOverdueCard extends StatelessWidget {
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const _NoOverdueCard({required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded, color: AppColors.secondary, size: 34),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('هیچ قەرزێکی دواکەوتوو نییە', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('ئەمە نیشانەی باشە بۆ پاراستنی پارەی مارکێت.', style: TextStyle(color: subColor, height: 1.5)),
        ])),
      ]),
    );
  }
}
