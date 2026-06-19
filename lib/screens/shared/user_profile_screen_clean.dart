import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/shared/customer_statement_safe_screen.dart';
import 'package:zhirox/screens/shared/debt_detail_screen_clean.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/debt_balance.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/customer_debt_lock_card.dart';
import 'package:zhirox/widgets/customer_debt_settle_all_card.dart';
import 'package:zhirox/widgets/customer_limit_summary_card.dart';
import 'package:zhirox/widgets/employee_access_settings_card.dart';

class UserProfileScreenClean extends StatefulWidget {
  final String userId;

  const UserProfileScreenClean({super.key, required this.userId});

  @override
  State<UserProfileScreenClean> createState() => _UserProfileScreenCleanState();
}

class _UserProfileScreenCleanState extends State<UserProfileScreenClean> {
  RecordModel? _user;
  List<RecordModel> _debts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final user = await PBService.getUser(widget.userId);
      final debts = user.getStringValue('role') == 'customer' ? await PBService.getDebts(customerId: widget.userId) : <RecordModel>[];
      final visibleDebts = DebtBalance.visible(debts).toList();
      if (mounted) {
        _user = user;
        _debts = visibleDebts;
      }
    } catch (_) {
      if (mounted) _debts = [];
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isOwnProfile = auth.userId == widget.userId;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppDarkColors.card : Colors.white;
    final textColor = isDark ? AppDarkColors.textPrimary : AppColors.textPrimary;
    final subColor = isDark ? AppDarkColors.textSecondary : AppColors.textSecondary;
    final user = _user;
    final name = user?.getStringValue('name') ?? (isOwnProfile ? auth.userName : '');
    final role = user?.getStringValue('role') ?? (isOwnProfile ? auth.userRole : '');
    final phone = user?.getStringValue('phone') ?? '';
    final marketName = user?.getStringValue('market_name') ?? auth.marketName;
    final debtLimit = user?.getDoubleValue('debt_limit') ?? 0;
    final isCustomer = role == 'customer';
    final canManageEmployeeAccess = auth.isManager && role == 'employee' && user != null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
        body: RefreshIndicator(
          onRefresh: _loadProfile,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ProfileHero(name: name, role: role),
              const SizedBox(height: 16),
              if (_isLoading)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else ...[
                _InfoCard(title: 'زانیاری گشتی', cardColor: cardColor, textColor: textColor, children: [
                  _InfoRow(label: 'ناو', value: name.isEmpty ? '—' : name, subColor: subColor),
                  _InfoRow(label: 'ڕۆڵ', value: role.isEmpty ? '—' : AppHelpers.roleName(role), subColor: subColor),
                  if (phone.isNotEmpty) _InfoRow(label: 'ژمارە مۆبایل', value: phone, subColor: subColor, ltr: true),
                  if (marketName.isNotEmpty) _InfoRow(label: 'مارکێت', value: marketName, subColor: subColor),
                  if (isCustomer) _InfoRow(label: 'سنووری قەرز', value: debtLimit <= 0 ? 'بێ سنوور' : AppHelpers.formatCurrency(debtLimit), subColor: subColor, ltr: true),
                ]),
                if (isCustomer && user != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerStatementSafeScreen(customerId: widget.userId))),
                      icon: const Icon(Icons.summarize_rounded),
                      label: const Text('کەشف حساب'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  CustomerDebtLockCard(customer: user, debts: _debts, cardColor: cardColor, textColor: textColor, subColor: subColor),
                  const SizedBox(height: 16),
                  CustomerLimitSummaryCard(customer: user, debts: _debts, cardColor: cardColor, textColor: textColor, subColor: subColor),
                  const SizedBox(height: 16),
                  CustomerDebtSettleAllCard(debts: _debts, cardColor: cardColor, textColor: textColor, subColor: subColor, onSaved: _loadProfile),
                  const SizedBox(height: 16),
                  _CustomerMoneySummaryCard(debts: _debts, debtLimit: debtLimit, cardColor: cardColor, textColor: textColor, subColor: subColor),
                  const SizedBox(height: 16),
                  _CustomerDebtHistoryCard(debts: _debts, cardColor: cardColor, textColor: textColor, subColor: subColor),
                ],
                if (canManageEmployeeAccess) ...[
                  const SizedBox(height: 16),
                  EmployeeAccessSettingsCard(employee: user, cardColor: cardColor, textColor: textColor, subColor: subColor, onSaved: _loadProfile),
                ],
                if (isOwnProfile) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirm = await AppHelpers.showConfirmDialog(context, title: AppStrings.logout, message: 'دڵنیایت لە چوونەدەرەوە؟');
                        if (confirm && context.mounted) await context.read<AuthProvider>().logout();
                      },
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text(AppStrings.logout),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  final String name;
  final String role;

  const _ProfileHero({required this.name, required this.role});

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
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(18)),
            child: Center(child: Text(name.isNotEmpty ? name[0] : 'ز', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(role == 'customer' ? 'پڕۆفایلی کڕیار' : 'هەژمار', style: TextStyle(color: Colors.white.withOpacity(0.78), fontSize: 14)),
            const SizedBox(height: 4),
            Text(name.isEmpty ? 'بەکارهێنەر' : name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            if (role.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(AppHelpers.roleName(role), style: TextStyle(color: Colors.white.withOpacity(0.76))),
            ],
          ])),
        ]),
      ),
    );
  }
}

class _CustomerMoneySummaryCard extends StatelessWidget {
  final List<RecordModel> debts;
  final double debtLimit;
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const _CustomerMoneySummaryCard({required this.debts, required this.debtLimit, required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    final visibleDebts = DebtBalance.visible(debts).toList();
    final totalDebt = visibleDebts.fold<double>(0, (sum, d) => sum + DebtBalance.amount(d));
    final totalRemaining = DebtBalance.totalRemaining(visibleDebts);
    final paid = (totalDebt - totalRemaining).clamp(0, double.infinity).toDouble();
    final activeCount = DebtBalance.activeCount(visibleDebts);
    final remainingLimit = debtLimit <= 0 ? 0 : (debtLimit - totalRemaining).clamp(0, double.infinity).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.account_balance_wallet_rounded, color: AppColors.primary), const SizedBox(width: 8), Text('کورتەی قەرزی کڕیار', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16))]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _MoneyTile(label: 'قەرزی ماوە', value: AppHelpers.formatCurrency(totalRemaining), color: AppColors.danger, textColor: textColor, subColor: subColor)),
          const SizedBox(width: 10),
          Expanded(child: _MoneyTile(label: 'پارەی دراو', value: AppHelpers.formatCurrency(paid), color: AppColors.secondary, textColor: textColor, subColor: subColor)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _MoneyTile(label: 'قەرزی چالاک', value: '$activeCount', color: AppColors.warning, textColor: textColor, subColor: subColor)),
          const SizedBox(width: 10),
          Expanded(child: _MoneyTile(label: 'سنووری ماوە', value: debtLimit <= 0 ? 'بێ سنوور' : AppHelpers.formatCurrency(remainingLimit), color: AppColors.primary, textColor: textColor, subColor: subColor)),
        ]),
      ]),
    );
  }
}

class _CustomerDebtHistoryCard extends StatelessWidget {
  final List<RecordModel> debts;
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const _CustomerDebtHistoryCard({required this.debts, required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    final shown = DebtBalance.visible(debts).take(6).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.receipt_long_rounded, color: AppColors.primary), const SizedBox(width: 8), Text('مێژووی قەرز و وەصڵ', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16))]),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          Text('هێشتا قەرزێک بۆ ئەم کڕیارە تۆمار نەکراوە.', style: TextStyle(color: subColor, height: 1.6))
        else
          ...shown.map((debt) => _DebtHistoryTile(debt: debt, textColor: textColor, subColor: subColor)),
      ]),
    );
  }
}

class _DebtHistoryTile extends StatelessWidget {
  final RecordModel debt;
  final Color textColor;
  final Color subColor;

  const _DebtHistoryTile({required this.debt, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    final remaining = DebtBalance.remaining(debt);
    final paid = DebtBalance.isPaid(debt);
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DebtDetailScreenClean(debtId: debt.id))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Icon(paid ? Icons.check_circle_rounded : Icons.schedule_rounded, color: paid ? AppColors.secondary : AppColors.warning, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(DebtBalance.statusLabel(debt), style: TextStyle(color: textColor, fontWeight: FontWeight.w700))),
          Text(AppHelpers.formatCurrency(remaining), style: TextStyle(color: paid ? AppColors.secondary : AppColors.danger, fontWeight: FontWeight.bold), textDirection: TextDirection.ltr),
        ]),
      ),
    );
  }
}

class _MoneyTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color textColor;
  final Color subColor;

  const _MoneyTile({required this.label, required this.value, required this.color, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.12))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: subColor, fontSize: 11)),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13), textDirection: TextDirection.ltr),
      ]),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final Color cardColor;
  final Color textColor;
  final List<Widget> children;

  const _InfoCard({required this.title, required this.cardColor, required this.textColor, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        ...children,
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color subColor;
  final bool ltr;

  const _InfoRow({required this.label, required this.value, required this.subColor, this.ltr = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Text(label, style: TextStyle(color: subColor, fontSize: 13)),
        const Spacer(),
        Flexible(child: Text(value, textAlign: TextAlign.left, textDirection: ltr ? TextDirection.ltr : TextDirection.rtl, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}
