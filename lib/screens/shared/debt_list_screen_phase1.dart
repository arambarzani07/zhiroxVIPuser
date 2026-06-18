import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/shared/add_debt_screen_clean.dart';
import 'package:zhirox/screens/shared/debt_detail_screen_clean.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class DebtListScreenPhase1 extends StatefulWidget {
  const DebtListScreenPhase1({super.key});

  @override
  State<DebtListScreenPhase1> createState() => _DebtListScreenPhase1State();
}

class _DebtListScreenPhase1State extends State<DebtListScreenPhase1> {
  final _searchController = TextEditingController();
  bool _isLoading = true;
  List<_CustomerDebtGroup> _groups = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDebts());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDebts() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    final adminId = auth.adminId.isNotEmpty ? auth.adminId : auth.userId;
    try {
      final debts = await PBService.getDebts(adminId: adminId, perPage: 500);
      if (mounted) _groups = _buildGroups(debts);
    } catch (_) {
      // Keep last visible state; no internal wording.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openAddDebt() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isManager && !auth.canGiveDebt) {
      AppHelpers.showSnackBar(context, AppUserMessages.needsManagerApproval, isError: true);
      return;
    }
    final created = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const AddDebtScreenClean()));
    if (created == true) await _loadDebts();
  }

  List<_CustomerDebtGroup> _buildGroups(List<RecordModel> debts) {
    final map = <String, _CustomerDebtGroup>{};
    for (final debt in debts) {
      final customer = debt.expand['customer']?.isNotEmpty == true ? debt.expand['customer']!.first : null;
      final customerId = customer?.id ?? debt.getStringValue('customer');
      if (customerId.isEmpty) continue;
      final name = customer?.getStringValue('name') ?? 'کڕیار';
      final phone = customer?.getStringValue('phone') ?? '';
      final group = map.putIfAbsent(customerId, () => _CustomerDebtGroup(id: customerId, name: name.isEmpty ? 'کڕیار' : name, phone: phone));
      group.debts.add(debt);
      group.totalDebt += debt.getDoubleValue('amount');
      group.totalRemaining += debt.getDoubleValue('remaining');
    }
    final list = map.values.toList();
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list.removeWhere((g) => !g.name.toLowerCase().contains(q) && !g.phone.toLowerCase().contains(q));
    }
    list.sort((a, b) => b.totalRemaining.compareTo(a.totalRemaining));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppDarkColors.card : Colors.white;
    final textColor = isDark ? AppDarkColors.textPrimary : AppColors.textPrimary;
    final subColor = isDark ? AppDarkColors.textSecondary : AppColors.textSecondary;
    final totalRemaining = _groups.fold<double>(0, (sum, g) => sum + g.totalRemaining);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: _loadDebts,
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
                    Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 30)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('قەرزەکان', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('قەرزی ماوە و کڕیارانی پێویست بە چاودێری', style: TextStyle(color: Colors.white.withOpacity(0.76), fontSize: 13)),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: _openAddDebt,
                icon: const Icon(Icons.add_card_rounded),
                label: const Text('قەرز پێدان'),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_rounded, color: AppColors.danger),
                  const SizedBox(width: 10),
                  Expanded(child: Text('قەرزی ماوە', style: TextStyle(color: subColor, fontWeight: FontWeight.w600))),
                  Text(AppHelpers.formatCurrency(totalRemaining), style: TextStyle(color: textColor, fontWeight: FontWeight.bold), textDirection: TextDirection.ltr),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() => _groups = _buildGroups(_groups.expand((g) => g.debts).toList())),
              decoration: InputDecoration(hintText: 'گەڕان بە ناو یان ژمارەی کڕیار', prefixIcon: const Icon(Icons.search_rounded)),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (_groups.isEmpty)
              _EmptyDebtList(cardColor: cardColor, textColor: textColor, subColor: subColor)
            else
              ..._groups.map((group) => _CustomerDebtCard(group: group, cardColor: cardColor, textColor: textColor, subColor: subColor)),
          ],
        ),
      ),
    );
  }
}

class _CustomerDebtCard extends StatelessWidget {
  final _CustomerDebtGroup group;
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const _CustomerDebtCard({required this.group, required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    final danger = group.totalRemaining > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: (danger ? AppColors.danger : AppColors.secondary).withOpacity(0.10), borderRadius: BorderRadius.circular(16)),
                child: Center(child: Text(group.name.isEmpty ? 'ک' : group.name[0], style: TextStyle(color: danger ? AppColors.danger : AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 20))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(group.name, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
              Text(AppHelpers.formatCurrency(group.totalRemaining), style: TextStyle(color: danger ? AppColors.danger : AppColors.secondary, fontWeight: FontWeight.bold), textDirection: TextDirection.ltr),
            ],
          ),
          const SizedBox(height: 12),
          ...group.debts.take(3).map((debt) => _DebtMiniRow(debt: debt, subColor: subColor, textColor: textColor)),
          if (group.debts.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('+${group.debts.length - 3} قەرزی تر', style: TextStyle(color: subColor, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _DebtMiniRow extends StatelessWidget {
  final RecordModel debt;
  final Color subColor;
  final Color textColor;

  const _DebtMiniRow({required this.debt, required this.subColor, required this.textColor});

  @override
  Widget build(BuildContext context) {
    final remaining = debt.getDoubleValue('remaining');
    final paid = debt.getStringValue('status') == 'paid' || remaining <= 0;
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DebtDetailScreenClean(debtId: debt.id))),
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Icon(paid ? Icons.verified_rounded : Icons.receipt_long_rounded, size: 18, color: paid ? AppColors.secondary : AppColors.warning),
            const SizedBox(width: 8),
            Expanded(child: Text(paid ? 'قەرز تەواوە' : 'قەرزی ماوە', style: TextStyle(color: textColor, fontSize: 13))),
            Text(AppHelpers.formatCurrency(remaining), style: TextStyle(color: paid ? AppColors.secondary : AppColors.danger, fontWeight: FontWeight.bold, fontSize: 12), textDirection: TextDirection.ltr),
          ],
        ),
      ),
    );
  }
}

class _EmptyDebtList extends StatelessWidget {
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const _EmptyDebtList({required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded, color: AppColors.secondary, size: 34),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('هێشتا هیچ قەرزێک تۆمار نەکراوە', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('کاتێک قەرز پێدان ئەنجام دەدرێت، لێرە دەردەکەوێت.', style: TextStyle(color: subColor)),
        ])),
      ]),
    );
  }
}

class _CustomerDebtGroup {
  final String id;
  final String name;
  final String phone;
  final List<RecordModel> debts = [];
  double totalDebt = 0;
  double totalRemaining = 0;

  _CustomerDebtGroup({required this.id, required this.name, required this.phone});
}
