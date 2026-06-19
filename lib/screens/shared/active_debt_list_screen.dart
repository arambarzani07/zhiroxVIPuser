import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/shared/add_debt_screen_clean.dart';
import 'package:zhirox/screens/shared/add_payment_screen_clean.dart';
import 'package:zhirox/screens/shared/debt_detail_screen_clean.dart';
import 'package:zhirox/screens/shared/debt_restore_screen.dart';
import 'package:zhirox/screens/shared/overdue_debts_screen.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/debt_balance.dart';
import 'package:zhirox/utils/helpers.dart';

class ActiveDebtListScreen extends StatefulWidget {
  const ActiveDebtListScreen({super.key});

  @override
  State<ActiveDebtListScreen> createState() => _ActiveDebtListScreenState();
}

class _ActiveDebtListScreenState extends State<ActiveDebtListScreen> {
  final searchCtrl = TextEditingController();
  bool loading = true;
  List<RecordModel> debts = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() => loading = true);
    final auth = context.read<AuthProvider>();
    final adminId = auth.adminId.isNotEmpty ? auth.adminId : auth.userId;
    try {
      final list = await PBService.getDebts(adminId: adminId, perPage: 500);
      debts = list.where((debt) => !debt.getBoolValue('is_deleted')).toList();
    } catch (_) {
      // Keep calm visible state.
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> openAddDebt() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isManager && !auth.canGiveDebt) {
      AppHelpers.showSnackBar(context, AppUserMessages.needsManagerApproval, isError: true);
      return;
    }
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const AddDebtScreenClean()));
    if (ok == true) await load();
  }

  Future<void> openPayment() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isManager && !auth.canReceivePayment) {
      AppHelpers.showSnackBar(context, AppUserMessages.needsManagerApproval, isError: true);
      return;
    }
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const AddPaymentScreenClean()));
    if (ok == true) await load();
  }

  Future<void> openRestore() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isManager) {
      AppHelpers.showSnackBar(context, AppUserMessages.needsManagerApproval, isError: true);
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const DebtRestoreScreen()));
    await load();
  }

  List<RecordModel> shownDebts() {
    final q = searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return debts;
    return debts.where((debt) {
      final customer = debt.expand['customer']?.isNotEmpty == true ? debt.expand['customer']!.first : null;
      final name = customer?.getStringValue('name').toLowerCase() ?? '';
      final phone = customer?.getStringValue('phone').toLowerCase() ?? '';
      return name.contains(q) || phone.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppDarkColors.card : Colors.white;
    final textColor = isDark ? AppDarkColors.textPrimary : AppColors.textPrimary;
    final subColor = isDark ? AppDarkColors.textSecondary : AppColors.textSecondary;
    final list = shownDebts();
    final total = list.fold<double>(0, (sum, debt) => sum + DebtBalance.remaining(debt));

    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _Header(total: total),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: openAddDebt, icon: const Icon(Icons.add_card_rounded), label: const Text('قەرز پێدان'))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(onPressed: openPayment, icon: const Icon(Icons.payments_rounded), label: const Text('پارە وەرگرتنەوە'))),
          ]),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const OverdueDebtsScreen())); await load(); }, icon: const Icon(Icons.event_busy_rounded), label: const Text('قەرزی دواکەوتوو')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: openRestore, icon: const Icon(Icons.restore_rounded), label: const Text('گەڕاندنەوەی کردار')),
          const SizedBox(height: 12),
          TextField(controller: searchCtrl, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'گەڕان بە ناو یان ژمارەی کڕیار', prefixIcon: Icon(Icons.search_rounded))),
          const SizedBox(height: 16),
          if (loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (list.isEmpty)
            _Empty(cardColor: cardColor, textColor: textColor, subColor: subColor)
          else
            ...list.map((debt) => _DebtTile(debt: debt, cardColor: cardColor, textColor: textColor, subColor: subColor)),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final double total;
  const _Header({required this.total});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.primary, AppColors.primary.withOpacity(0.72)]), borderRadius: BorderRadius.circular(26)),
        child: Row(children: [
          const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 34),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('قەرزە چالاکەکان', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            Text(AppHelpers.formatCurrency(total), textDirection: TextDirection.ltr, style: TextStyle(color: Colors.white.withOpacity(0.78))),
          ])),
        ]),
      );
}

class _DebtTile extends StatelessWidget {
  final RecordModel debt;
  final Color cardColor;
  final Color textColor;
  final Color subColor;
  const _DebtTile({required this.debt, required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    final customer = debt.expand['customer']?.isNotEmpty == true ? debt.expand['customer']!.first : null;
    final name = customer?.getStringValue('name') ?? 'کڕیار';
    final remaining = DebtBalance.remaining(debt);
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DebtDetailScreenClean(debtId: debt.id))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          const Icon(Icons.receipt_long_rounded, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(name.isEmpty ? 'کڕیار' : name, style: TextStyle(color: textColor, fontWeight: FontWeight.bold))),
          Text(AppHelpers.formatCurrency(remaining), textDirection: TextDirection.ltr, style: TextStyle(color: remaining <= 0 ? AppColors.secondary : AppColors.danger, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final Color cardColor;
  final Color textColor;
  final Color subColor;
  const _Empty({required this.cardColor, required this.textColor, required this.subColor});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)), child: Text('هێشتا هیچ قەرزێکی چالاک نییە.', style: TextStyle(color: subColor)));
}
