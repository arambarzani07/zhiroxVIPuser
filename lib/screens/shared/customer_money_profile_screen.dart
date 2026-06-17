import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/shared/add_debt_screen.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/services/pdf_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class CustomerMoneyProfileScreen extends StatefulWidget {
  final String userId;

  const CustomerMoneyProfileScreen({super.key, required this.userId});

  @override
  State<CustomerMoneyProfileScreen> createState() => _CustomerMoneyProfileScreenState();
}

class _CustomerMoneyProfileScreenState extends State<CustomerMoneyProfileScreen> {
  RecordModel? _customer;
  List<RecordModel> _debts = [];
  List<RecordModel> _payments = [];
  bool _isLoading = true;
  bool _isSavingPayment = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final customer = await PBService.getUser(widget.userId);
      final debts = await PBService.getDebts(customerId: widget.userId);
      final payments = await PBService.getPayments(customerId: widget.userId);
      if (!mounted) return;
      setState(() {
        _customer = customer;
        _debts = debts;
        _payments = payments;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppHelpers.showSnackBar(context, 'هەڵە لە هێنانی زانیاری کڕیار: $e', isError: true);
    }
  }

  double get _totalDebt => _debts.fold(0.0, (sum, debt) => sum + debt.getDoubleValue('amount'));
  double get _totalRemaining => _debts.fold(0.0, (sum, debt) => sum + debt.getDoubleValue('remaining'));
  double get _totalPaid => _totalDebt - _totalRemaining;
  double get _debtLimit => _customer?.getDoubleValue('debt_limit') ?? 0;
  double get _availableLimit => _debtLimit > 0 ? _debtLimit - _totalRemaining : 0;

  List<RecordModel> get _openDebts => _debts.where((debt) => debt.getDoubleValue('remaining') > 0).toList();

  String get _customerName => _customer?.getStringValue('name') ?? 'کڕیار';
  String get _customerPhone => _customer?.getStringValue('phone') ?? '';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: const Text('پڕۆفایلی کڕیار'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'نوێکردنەوە',
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _customer == null
                ? _ErrorState(onRetry: _loadData)
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 28),
                      children: [
                        _CustomerHeaderCard(
                          name: _customerName,
                          phone: _customerPhone,
                          totalRemaining: _totalRemaining,
                          debtLimit: _debtLimit,
                        ),
                        _FinancialSummaryCard(
                          totalDebt: _totalDebt,
                          totalRemaining: _totalRemaining,
                          totalPaid: _totalPaid,
                          debtLimit: _debtLimit,
                          availableLimit: _availableLimit,
                        ),
                        _MainActionsCard(
                          onAddDebt: _openAddDebt,
                          onAddPayment: _showPaymentDialog,
                          onStatement: _generateStatement,
                          hasOpenDebt: _openDebts.isNotEmpty,
                        ),
                        _DebtSection(debts: _debts),
                        _PaymentSection(payments: _payments),
                        _ProfileToolsCard(
                          onEditInfo: _showComingSoon,
                          onChangeLimit: _showComingSoon,
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Future<void> _openAddDebt() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddDebtScreen(customerId: widget.userId)),
    );
    if (mounted) await _loadData();
  }

  Future<void> _generateStatement() async {
    final auth = context.read<AuthProvider>();
    try {
      await PdfService.generateCustomerStatement(
        activeDebts: _debts,
        customerName: _customerName,
        marketName: auth.marketName,
        adminName: auth.userName,
        adminPhone: auth.user?.getStringValue('phone') ?? '',
        totalDebt: _totalDebt,
        totalRemaining: _totalRemaining,
        totalPaid: _totalPaid,
      );
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(context, 'هەڵە لە دروستکردنی کەشف حساب: $e', isError: true);
      }
    }
  }

  void _showComingSoon() {
    AppHelpers.showSnackBar(context, 'ئەم بەشە لە هەنگاوی داهاتوودا ڕێک دەخرێت.');
  }

  Future<void> _showPaymentDialog() async {
    final openDebts = _openDebts;
    if (openDebts.isEmpty) {
      AppHelpers.showSnackBar(context, 'ئەم کڕیارە هیچ قەرزێکی ماوەی نییە ✅');
      return;
    }

    RecordModel selectedDebt = openDebts.first;
    final amountController = TextEditingController();
    final noteController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final remaining = selectedDebt.getDoubleValue('remaining');
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text('تۆمارکردنی پارەدانەوە'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<RecordModel>(
                        value: selectedDebt,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'قەرز هەڵبژێرە',
                          border: OutlineInputBorder(),
                        ),
                        items: openDebts.map((debt) {
                          final title = debt.getStringValue('description').isEmpty
                              ? 'قەرز'
                              : debt.getStringValue('description');
                          final rem = AppHelpers.formatCurrency(debt.getDoubleValue('remaining'));
                          return DropdownMenuItem<RecordModel>(value: debt, child: Text('$title — ماوە: $rem'));
                        }).toList(),
                        onChanged: (debt) {
                          if (debt != null) setDialogState(() => selectedDebt = debt);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: amountController,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: 'بڕی پارەدانەوە',
                          helperText: 'ماوەی ئەم قەرزە: ${AppHelpers.formatCurrency(remaining)}',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: noteController,
                        decoration: const InputDecoration(
                          labelText: 'تێبینی — ئارەزوومەندانە',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: _isSavingPayment ? null : () => Navigator.pop(dialogContext),
                    child: const Text('پاشگەزبوونەوە'),
                  ),
                  ElevatedButton(
                    onPressed: _isSavingPayment
                        ? null
                        : () async {
                            final rawAmount = amountController.text.trim().replaceAll(',', '');
                            final amount = double.tryParse(rawAmount);
                            if (amount == null || amount <= 0) {
                              AppHelpers.showSnackBar(context, 'بڕی دروست بنووسە', isError: true);
                              return;
                            }
                            if (amount > selectedDebt.getDoubleValue('remaining')) {
                              AppHelpers.showSnackBar(context, 'بڕی پارەدانەوە زیاترە لە ماوەی قەرز', isError: true);
                              return;
                            }
                            setDialogState(() => _isSavingPayment = true);
                            await _savePayment(
                              debt: selectedDebt,
                              amount: amount,
                              note: noteController.text.trim(),
                            );
                            if (mounted && Navigator.canPop(dialogContext)) {
                              Navigator.pop(dialogContext);
                            }
                          },
                    child: _isSavingPayment
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('تۆمارکردن'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    amountController.dispose();
    noteController.dispose();
    if (mounted) setState(() => _isSavingPayment = false);
  }

  Future<void> _savePayment({
    required RecordModel debt,
    required double amount,
    required String note,
  }) async {
    final auth = context.read<AuthProvider>();
    try {
      await PBService.createPayment(
        debtId: debt.id,
        amount: amount,
        note: note,
        createdBy: auth.userId,
        createdByName: auth.userName,
        adminId: auth.adminId.isNotEmpty ? auth.adminId : auth.userId,
      );
      if (mounted) {
        AppHelpers.showSnackBar(context, 'پارەدانەوە تۆمار کرا ✅');
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(context, 'هەڵە لە تۆمارکردنی پارەدانەوە: $e', isError: true);
      }
    }
  }
}

class _CustomerHeaderCard extends StatelessWidget {
  final String name;
  final String phone;
  final double totalRemaining;
  final double debtLimit;

  const _CustomerHeaderCard({
    required this.name,
    required this.phone,
    required this.totalRemaining,
    required this.debtLimit,
  });

  @override
  Widget build(BuildContext context) {
    final isGood = totalRemaining <= 0;
    final isOverLimit = debtLimit > 0 && totalRemaining > debtLimit;
    final statusColor = isGood ? Colors.green : (isOverLimit ? Colors.red : Colors.orange);
    final statusText = isGood
        ? 'باش — هیچ قەرزێکی ماوە نییە'
        : isOverLimit
            ? 'مەترسیدار — سنووری قەرز تێپەڕیوە'
            : 'ئاگاداری — قەرزی ماوە هەیە';
    final avatarLetter = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withOpacity(0.72)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.white.withOpacity(0.18),
                child: Text(
                  avatarLetter,
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(phone.isEmpty ? 'ژمارەی مۆبایل نەدراوە' : phone, style: TextStyle(color: Colors.white.withOpacity(0.82)), textDirection: TextDirection.ltr),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                Icon(Icons.health_and_safety_rounded, color: statusColor, size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text(statusText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FinancialSummaryCard extends StatelessWidget {
  final double totalDebt;
  final double totalRemaining;
  final double totalPaid;
  final double debtLimit;
  final double availableLimit;

  const _FinancialSummaryCard({
    required this.totalDebt,
    required this.totalRemaining,
    required this.totalPaid,
    required this.debtLimit,
    required this.availableLimit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('دۆخی دارایی', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _MoneyTile(label: 'کۆی قەرز', value: totalDebt, icon: Icons.receipt_long_rounded, color: Colors.orange)),
              const SizedBox(width: 8),
              Expanded(child: _MoneyTile(label: 'ماوە', value: totalRemaining, icon: Icons.pending_actions_rounded, color: Colors.red)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _MoneyTile(label: 'دراوە', value: totalPaid, icon: Icons.payments_rounded, color: Colors.green)),
              const SizedBox(width: 8),
              Expanded(child: _MoneyTile(label: debtLimit > 0 ? 'بەردەستە' : 'سنوور نییە', value: debtLimit > 0 ? availableLimit : 0, icon: Icons.verified_user_rounded, color: Colors.blue)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _MoneyTile extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  final Color color;

  const _MoneyTile({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 3),
          Text(AppHelpers.formatCurrency(value), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14), textDirection: TextDirection.ltr),
        ],
      ),
    );
  }
}

class _MainActionsCard extends StatelessWidget {
  final VoidCallback onAddDebt;
  final VoidCallback onAddPayment;
  final VoidCallback onStatement;
  final bool hasOpenDebt;

  const _MainActionsCard({required this.onAddDebt, required this.onAddPayment, required this.onStatement, required this.hasOpenDebt});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(child: ElevatedButton.icon(onPressed: onAddDebt, icon: const Icon(Icons.add), label: const Text('قەرزی نوێ'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: hasOpenDebt ? onAddPayment : null, icon: const Icon(Icons.payments_rounded), label: const Text('پارەدانەوە'))),
            IconButton(onPressed: onStatement, icon: const Icon(Icons.print_rounded), tooltip: 'کەشف حساب'),
          ],
        ),
      ),
    );
  }
}

class _DebtSection extends StatelessWidget {
  final List<RecordModel> debts;

  const _DebtSection({required this.debts});

  @override
  Widget build(BuildContext context) {
    final openDebts = debts.where((d) => d.getDoubleValue('remaining') > 0).toList();
    return _SectionCard(
      title: 'قەرزەکان',
      subtitle: openDebts.isEmpty ? 'هیچ قەرزێکی ماوە نییە' : '${openDebts.length} قەرزی ماوە هەیە',
      icon: Icons.receipt_long_rounded,
      children: openDebts.isEmpty
          ? [const _EmptyLine(text: 'هەموو قەرزەکان تەواو دراون یان قەرز نییە ✅')]
          : openDebts.map((debt) => _DebtItem(debt: debt)).toList(),
    );
  }
}

class _DebtItem extends StatelessWidget {
  final RecordModel debt;

  const _DebtItem({required this.debt});

  @override
  Widget build(BuildContext context) {
    final amount = debt.getDoubleValue('amount');
    final remaining = debt.getDoubleValue('remaining');
    final paid = amount - remaining;
    final progress = amount <= 0 ? 0.0 : (paid / amount).clamp(0.0, 1.0);
    final description = debt.getStringValue('description').isEmpty ? 'قەرز' : debt.getStringValue('description');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.orange.withOpacity(0.06), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(description, style: const TextStyle(fontWeight: FontWeight.bold))),
            Text(AppHelpers.statusName(debt.getStringValue('status')), style: const TextStyle(fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text('قەرز: ${AppHelpers.formatCurrency(amount)}', textDirection: TextDirection.ltr)),
            Expanded(child: Text('ماوە: ${AppHelpers.formatCurrency(remaining)}', textDirection: TextDirection.ltr)),
          ]),
        ],
      ),
    );
  }
}

class _PaymentSection extends StatelessWidget {
  final List<RecordModel> payments;

  const _PaymentSection({required this.payments});

  @override
  Widget build(BuildContext context) {
    final sorted = [...payments]..sort((a, b) => b.created.compareTo(a.created));
    return _SectionCard(
      title: 'پارەدانەوەکان',
      subtitle: sorted.isEmpty ? 'هێشتا پارەدانەوە نییە' : '${sorted.length} پارەدانەوە تۆمارکراوە',
      icon: Icons.payments_rounded,
      children: sorted.isEmpty
          ? [const _EmptyLine(text: 'کاتێک پارەدانەوە تۆمار بکرێت، لێرە دەردەکەوێت.')]
          : sorted.map((payment) => _PaymentItem(payment: payment)).toList(),
    );
  }
}

class _PaymentItem extends StatelessWidget {
  final RecordModel payment;

  const _PaymentItem({required this.payment});

  @override
  Widget build(BuildContext context) {
    final amount = payment.getDoubleValue('amount');
    final note = payment.getStringValue('note');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(child: Icon(Icons.south_west_rounded)),
      title: Text(AppHelpers.formatCurrency(amount), textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(note.isEmpty ? AppHelpers.formatDateTime(payment.created) : '$note\n${AppHelpers.formatDateTime(payment.created)}'),
    );
  }
}

class _ProfileToolsCard extends StatelessWidget {
  final VoidCallback onEditInfo;
  final VoidCallback onChangeLimit;

  const _ProfileToolsCard({required this.onEditInfo, required this.onChangeLimit});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'ڕێکخستنەکانی کڕیار',
      subtitle: 'دەستکاری زانیاری و سنووری قەرز لە هەنگاوی داهاتوودا لێرە پاکتر دەکرێت.',
      icon: Icons.settings_rounded,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline),
          title: const Text('دەستکاری زانیاری کڕیار'),
          trailing: const Icon(Icons.chevron_left),
          onTap: onEditInfo,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.verified_user_outlined),
          title: const Text('ڕێکخستنی سنووری قەرز'),
          trailing: const Icon(Icons.chevron_left),
          onTap: onChangeLimit,
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.subtitle, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  final String text;

  const _EmptyLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(text, textAlign: TextAlign.center),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('دووبارە هەوڵ بدەوە')),
    );
  }
}
