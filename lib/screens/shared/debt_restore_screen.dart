import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/shared/debt_detail_screen_clean.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/debt_balance.dart';
import 'package:zhirox/utils/helpers.dart';

class DebtRestoreScreen extends StatefulWidget {
  const DebtRestoreScreen({super.key});

  @override
  State<DebtRestoreScreen> createState() => _DebtRestoreScreenState();
}

class _DebtRestoreScreenState extends State<DebtRestoreScreen> {
  List<RecordModel> debts = [];
  bool loading = true;
  String savingId = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() => loading = true);
    final auth = context.read<AuthProvider>();
    final adminId = auth.adminId.isNotEmpty ? auth.adminId : auth.userId;
    try {
      final result = await PBService.pb.collection('debts').getList(
        page: 1,
        perPage: 500,
        filter: 'admin_id="$adminId" && is_deleted=true',
        sort: '-updated',
        expand: 'customer,created_by',
      );
      if (mounted) debts = result.items;
    } catch (_) {
      if (mounted) debts = [];
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> restore(RecordModel debt) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isManager) {
      AppHelpers.showSnackBar(context, AppUserMessages.needsManagerApproval, isError: true);
      return;
    }
    final ok = await AppHelpers.showConfirmDialog(
      context,
      title: 'گەڕاندنەوەی کردار',
      message: 'ئەم قەرزە دەگەڕێتەوە بۆ لیستەکان، و هۆکاری سڕینەوە لە مێژوودا دەمێنێتەوە. دڵنیایت؟',
    );
    if (!ok || !mounted) return;
    setState(() => savingId = debt.id);
    try {
      await PBService.pb.collection('debts').update(debt.id, body: {
        'is_deleted': false,
      });
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'قەرزی ماوە نوێکرایەوە');
      await load();
    } catch (_) {
      if (!mounted) return;
      AppHelpers.showSnackBar(context, AppUserMessages.protectedOffline);
    } finally {
      if (mounted) setState(() => savingId = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppDarkColors.card : Colors.white;
    final textColor = isDark ? AppDarkColors.textPrimary : AppColors.textPrimary;
    final subColor = isDark ? AppDarkColors.textSecondary : AppColors.textSecondary;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
        appBar: AppBar(title: const Text('گەڕاندنەوەی کردار')),
        body: RefreshIndicator(
          onRefresh: load,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (loading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (debts.isEmpty)
              _Empty(cardColor: cardColor, textColor: textColor, subColor: subColor)
            else
              ...debts.map((debt) => _ArchivedDebtCard(
                    debt: debt,
                    saving: savingId == debt.id,
                    cardColor: cardColor,
                    textColor: textColor,
                    subColor: subColor,
                    onRestore: () => restore(debt),
                  )),
          ]),
        ),
      ),
    );
  }
}

class _ArchivedDebtCard extends StatelessWidget {
  final RecordModel debt;
  final bool saving;
  final Color cardColor;
  final Color textColor;
  final Color subColor;
  final VoidCallback onRestore;

  const _ArchivedDebtCard({required this.debt, required this.saving, required this.cardColor, required this.textColor, required this.subColor, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    final customer = debt.expand['customer']?.isNotEmpty == true ? debt.expand['customer']!.first : null;
    final name = customer?.getStringValue('name') ?? 'کڕیار';
    final reason = debt.getStringValue('delete_reason');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.restore_rounded, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(name.isEmpty ? 'کڕیار' : name, style: TextStyle(color: textColor, fontWeight: FontWeight.bold))),
          Text(AppHelpers.formatCurrency(DebtBalance.remaining(debt)), textDirection: TextDirection.ltr, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
        ]),
        if (reason.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(reason, style: TextStyle(color: subColor, fontSize: 12, height: 1.5)),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DebtDetailScreenClean(debtId: debt.id))), icon: const Icon(Icons.visibility_rounded), label: const Text('بینین'))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton.icon(onPressed: saving ? null : onRestore, icon: const Icon(Icons.restore_rounded), label: Text(saving ? 'نوێکردنەوە...' : 'گەڕاندنەوە'))),
        ]),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  final Color cardColor;
  final Color textColor;
  final Color subColor;
  const _Empty({required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        const Icon(Icons.verified_rounded, color: AppColors.secondary),
        const SizedBox(width: 10),
        Expanded(child: Text('هیچ کردارێکی گەڕاندنەوە لە ئێستادا نییە.', style: TextStyle(color: subColor, height: 1.5))),
      ]),
    );
  }
}
