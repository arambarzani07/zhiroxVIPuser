import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/shared/debt_detail_screen.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class DebtListScreen extends StatefulWidget {
  const DebtListScreen({super.key});

  @override
  State<DebtListScreen> createState() => _DebtListScreenState();
}

class _DebtListScreenState extends State<DebtListScreen> {
  final _searchController = TextEditingController();
  bool _isLoading = true;
  List<_CustomerDebtGroup> _groups = [];
  String _sortMode = 'amount';

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
      // Keep market UI calm and preserve last visible state.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<_CustomerDebtGroup> _buildGroups(List<RecordModel> debts) {
    final map = <String, _CustomerDebtGroup>{};

    for (final debt in debts) {
      final customer = debt.expand['customer']?.isNotEmpty == true
          ? debt.expand['customer']!.first
          : null;
      final customerId = customer?.id ?? debt.getStringValue('customer');
      if (customerId.isEmpty) continue;
      final name = customer?.getStringValue('name') ?? 'کڕیار';
      final phone = customer?.getStringValue('phone') ?? '';

      final group = map.putIfAbsent(
        customerId,
        () => _CustomerDebtGroup(id: customerId, name: name.isEmpty ? 'کڕیار' : name, phone: phone),
      );
      group.debts.add(debt);
      group.totalDebt += debt.getDoubleValue('amount');
      group.totalRemaining += debt.getDoubleValue('remaining');
    }

    final list = map.values.toList();
    _applySearchAndSort(list);
    return list;
  }

  void _applySearchAndSort(List<_CustomerDebtGroup> list) {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list.removeWhere((c) =>
          !c.name.toLowerCase().contains(q) && !c.phone.toLowerCase().contains(q));
    }

    switch (_sortMode) {
      case 'name':
        list.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'count':
        list.sort((a, b) => b.activeCount.compareTo(a.activeCount));
        break;
      case 'amount':
      default:
        list.sort((a, b) => b.totalRemaining.compareTo(a.totalRemaining));
    }
  }

  void _refreshFilters() {
    setState(() => _groups = List<_CustomerDebtGroup>.from(_groups)..clear());
    _loadDebts();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
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
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primary.withOpacity(0.72)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.22),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(18)),
                      child: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 30),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('قەرزەکان', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            auth.isManager ? 'چاودێری قەرزی مارکێت' : 'کاری قەرز و پارە وەرگرتنەوە',
                            style: TextStyle(color: Colors.white.withOpacity(0.76), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_rounded, color: AppColors.danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('قەرزی ماوە', style: TextStyle(color: subColor, fontSize: 12)),
                        const SizedBox(height: 3),
                        Text(AppHelpers.formatCurrency(totalRemaining), style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold), textDirection: TextDirection.ltr),
                      ],
                    ),
                  ),
                  Text('${_groups.length} کڕیار', style: TextStyle(color: subColor, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: (_) => _refreshFilters(),
              decoration: InputDecoration(
                hintText: 'گەڕان بە ناو یان ژمارەی کڕیار',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchController.clear();
                          _refreshFilters();
                        },
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _sortChip('زۆرترین قەرز', 'amount'),
                _sortChip('بەپێی ناو', 'name'),
                _sortChip('ژمارەی قەرز', 'count'),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (_groups.isEmpty)
              _EmptyDebtList(cardColor: cardColor, textColor: textColor, subColor: subColor)
            else
              ..._groups.map((group) => _CustomerDebtCard(
                    group: group,
                    cardColor: cardColor,
                    textColor: textColor,
                    subColor: subColor,
                    onTap: () => _openCustomerDebts(group),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _sortChip(String label, String mode) {
    final selected = _sortMode == mode;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _sortMode = mode);
        _loadDebts();
      },
    );
  }

  void _openCustomerDebts(_CustomerDebtGroup group) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDark ? AppDarkColors.textPrimary : AppColors.textPrimary;
        final subColor = isDark ? AppDarkColors.textSecondary : AppColors.textSecondary;
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(99)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(group.name, style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('قەرزی ماوە: ${AppHelpers.formatCurrency(group.totalRemaining)}', style: TextStyle(color: subColor), textDirection: TextDirection.ltr),
                  const SizedBox(height: 16),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: group.debts.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) => _DebtRow(debt: group.debts[index]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CustomerDebtCard extends StatelessWidget {
  final _CustomerDebtGroup group;
  final Color cardColor;
  final Color textColor;
  final Color subColor;
  final VoidCallback onTap;

  const _CustomerDebtCard({required this.group, required this.cardColor, required this.textColor, required this.subColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final danger = group.totalRemaining > 0;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: (danger ? AppColors.danger : AppColors.secondary).withOpacity(0.10),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Center(
                child: Text(group.name.isEmpty ? 'ک' : group.name.characters.first, style: TextStyle(color: danger ? AppColors.danger : AppColors.secondary, fontSize: 21, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.name, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text('${group.activeCount} قەرزی چالاک', style: TextStyle(color: subColor, fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(AppHelpers.formatCurrency(group.totalRemaining), style: TextStyle(color: danger ? AppColors.danger : AppColors.secondary, fontWeight: FontWeight.bold), textDirection: TextDirection.ltr),
                const SizedBox(height: 4),
                Icon(Icons.chevron_left_rounded, color: subColor),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DebtRow extends StatelessWidget {
  final RecordModel debt;

  const _DebtRow({required this.debt});

  @override
  Widget build(BuildContext context) {
    final amount = debt.getDoubleValue('amount');
    final remaining = debt.getDoubleValue('remaining');
    final status = debt.getStringValue('status');
    final paid = status == 'paid' || remaining <= 0;
    return ListTile(
      onTap: () {
        Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: (_) => DebtDetailScreen(debtId: debt.id)));
      },
      leading: Icon(paid ? Icons.verified_rounded : Icons.receipt_long_rounded, color: paid ? AppColors.secondary : AppColors.warning),
      title: Text(paid ? 'قەرز تەواوە' : 'قەرزی ماوە'),
      subtitle: Text('کۆی قەرز: ${AppHelpers.formatCurrency(amount)}', textDirection: TextDirection.ltr),
      trailing: Text(AppHelpers.formatCurrency(remaining), textDirection: TextDirection.ltr, style: TextStyle(color: paid ? AppColors.secondary : AppColors.danger, fontWeight: FontWeight.bold)),
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
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.secondary, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('هێشتا هیچ قەرزێک تۆمار نەکراوە', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('کاتێک قەرز پێدان ئەنجام دەدرێت، لێرە دەردەکەوێت.', style: TextStyle(color: subColor)),
              ],
            ),
          ),
        ],
      ),
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

  int get activeCount => debts.where((d) => d.getStringValue('status') != 'paid' && d.getDoubleValue('remaining') > 0).length;
}
