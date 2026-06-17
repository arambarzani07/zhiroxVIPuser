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
  State<CustomerMoneyProfileScreen> createState() =>
      _CustomerMoneyProfileScreenState();
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

  double get _totalDebt => _debts.fold(0.0, (sum, d) => sum + d.getDoubleValue('amount'));
  double get _totalRemaining => _debts.fold(0.0, (sum, d) => sum + d.getDoubleValue('remaining'));
  double get _totalPaid => _totalDebt - _totalRemaining;
  double get _debtLimit => _customer?.getDoubleValue('debt_limit') ?? 0;
  double get _availableLimit => _debtLimit > 0 ? _debtLimit - _totalRemaining : 0;
  List<RecordModel> get _openDebts => _debts.where((d) => d.getDoubleValue('remaining') > 0).toList();
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
                        _CustomerInfoCard(
                          name: _customerName,
                          phone: _customerPhone,
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
                        _MoneyChatCard(debts: _debts, payments: _payments),
                        _ProfileToolsCard(
                          onEditInfo: _showEditCustomerInfoSheet,
                          onChangeLimit: _showDebtLimitSheet,
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
      if (mounted) AppHelpers.showSnackBar(context, 'هەڵە لە دروستکردنی کەشف حساب: $e', isError: true);
    }
  }

  Future<void> _showEditCustomerInfoSheet() async {
    final nameController = TextEditingController(text: _customerName);
    final phoneController = TextEditingController(text: _customerPhone);
    bool isSaving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'دەستکاری زانیاری کڕیار',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'ناوی کڕیار',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                        labelText: 'ژمارەی مۆبایل',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isSaving
                            ? null
                            : () async {
                                final name = nameController.text.trim();
                                final phone = phoneController.text.trim();
                                if (name.isEmpty) {
                                  AppHelpers.showSnackBar(context, 'ناوی کڕیار بنووسە', isError: true);
                                  return;
                                }
                                setSheetState(() => isSaving = true);
                                var saved = false;
                                try {
                                  await PBService.pb.collection('users').update(
                                    widget.userId,
                                    body: {
                                      'name': name,
                                      'phone': phone,
                                    },
                                  );
                                  saved = true;
                                } catch (e) {
                                  if (mounted) {
                                    AppHelpers.showSnackBar(context, 'هەڵە لە نوێکردنەوە: $e', isError: true);
                                  }
                                }
                                if (!mounted) return;
                                if (saved) {
                                  Navigator.pop(sheetContext);
                                  AppHelpers.showSnackBar(context, 'زانیاری کڕیار نوێ کرایەوە ✅');
                                  await _loadData();
                                  return;
                                }
                                setSheetState(() => isSaving = false);
                              },
                        icon: isSaving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.save_rounded),
                        label: const Text('پاشەکەوتکردن'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    phoneController.dispose();
  }

  Future<void> _showDebtLimitSheet() async {
    final limitController = TextEditingController(
      text: _debtLimit > 0 ? _debtLimit.toStringAsFixed(0) : '',
    );
    bool isSaving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ڕێکخستنی سنووری قەرز',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'سنووری قەرز بۆ ئەوەیە کڕیار زیاتر لە ڕێژەی دیاریکراو قەرز وەرنەگرێت.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: limitController,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                        labelText: 'سنووری قەرز',
                        hintText: 'نموونە: 100000',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'قەرزی ئێستا: ${AppHelpers.formatCurrency(_totalRemaining)}',
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isSaving
                            ? null
                            : () async {
                                final raw = limitController.text.trim().replaceAll(',', '');
                                final limit = raw.isEmpty ? 0.0 : double.tryParse(raw);
                                if (limit == null || limit < 0) {
                                  AppHelpers.showSnackBar(context, 'سنووری قەرز بە دروستی بنووسە', isError: true);
                                  return;
                                }
                                setSheetState(() => isSaving = true);
                                var saved = false;
                                try {
                                  await PBService.pb.collection('users').update(
                                    widget.userId,
                                    body: {'debt_limit': limit},
                                  );
                                  saved = true;
                                } catch (e) {
                                  if (mounted) {
                                    AppHelpers.showSnackBar(context, 'هەڵە لە نوێکردنەوەی سنوور: $e', isError: true);
                                  }
                                }
                                if (!mounted) return;
                                if (saved) {
                                  Navigator.pop(sheetContext);
                                  AppHelpers.showSnackBar(context, 'سنووری قەرز نوێ کرایەوە ✅');
                                  await _loadData();
                                  return;
                                }
                                setSheetState(() => isSaving = false);
                              },
                        icon: isSaving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.save_rounded),
                        label: const Text('پاشەکەوتکردن'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    limitController.dispose();
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
                title: const Text('پارەدانەوە'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<RecordModel>(
                        value: selectedDebt,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'قەرزی ماوە هەڵبژێرە',
                          border: OutlineInputBorder(),
                        ),
                        items: openDebts.map((debt) {
                          final title = debt.getStringValue('description').isEmpty ? 'قەرز' : debt.getStringValue('description');
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
                        decoration: const InputDecoration(labelText: 'تێبینی', border: OutlineInputBorder()),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: _isSavingPayment ? null : () => Navigator.pop(dialogContext), child: const Text('پاشگەزبوونەوە')),
                  ElevatedButton(
                    onPressed: _isSavingPayment
                        ? null
                        : () async {
                            final amount = double.tryParse(amountController.text.trim().replaceAll(',', ''));
                            if (amount == null || amount <= 0) {
                              AppHelpers.showSnackBar(context, 'بڕی دروست بنووسە', isError: true);
                              return;
                            }
                            if (amount > selectedDebt.getDoubleValue('remaining')) {
                              AppHelpers.showSnackBar(context, 'بڕی پارەدانەوە زیاترە لە ماوەی قەرز', isError: true);
                              return;
                            }
                            setDialogState(() => _isSavingPayment = true);
                            await _savePayment(debt: selectedDebt, amount: amount, note: noteController.text.trim());
                            if (mounted && Navigator.canPop(dialogContext)) Navigator.pop(dialogContext);
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

  Future<void> _savePayment({required RecordModel debt, required double amount, required String note}) async {
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
      if (mounted) AppHelpers.showSnackBar(context, 'هەڵە لە تۆمارکردنی پارەدانەوە: $e', isError: true);
    }
  }
}

class _CustomerInfoCard extends StatelessWidget {
  final String name;
  final String phone;
  final double totalDebt;
  final double totalRemaining;
  final double totalPaid;
  final double debtLimit;
  final double availableLimit;

  const _CustomerInfoCard({required this.name, required this.phone, required this.totalDebt, required this.totalRemaining, required this.totalPaid, required this.debtLimit, required this.availableLimit});

  @override
  Widget build(BuildContext context) {
    final avatarLetter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final hasDebt = totalRemaining > 0;
    final statusColor = hasDebt ? Colors.orange : Colors.green;

    return Card(
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 28, backgroundColor: AppColors.primary.withOpacity(0.12), child: Text(avatarLetter, style: TextStyle(color: AppColors.primary, fontSize: 23, fontWeight: FontWeight.bold))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('زانیاری کڕیار', style: TextStyle(fontSize: 12, color: Colors.grey)),
              Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text(phone.isEmpty ? 'ژمارەی مۆبایل نەدراوە' : phone, textDirection: TextDirection.ltr, style: TextStyle(color: Colors.grey.shade600)),
            ])),
          ]),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.08), borderRadius: BorderRadius.circular(16)),
            child: Text(hasDebt ? 'ئەم کڕیارە قەرزی ماوە هەیە' : 'هیچ قەرزێکی ماوە نییە ✅', style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
          ),
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
        ]),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 8),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 3),
        Text(AppHelpers.formatCurrency(value), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14), textDirection: TextDirection.ltr),
      ]),
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
        child: Row(children: [
          Expanded(child: ElevatedButton.icon(onPressed: onAddDebt, icon: const Icon(Icons.add), label: const Text('قەرزی نوێ'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: hasOpenDebt ? onAddPayment : null, icon: const Icon(Icons.payments_rounded), label: const Text('پارەدانەوە'))),
          IconButton(onPressed: onStatement, icon: const Icon(Icons.print_rounded), tooltip: 'کەشف حساب'),
        ]),
      ),
    );
  }
}

class _MoneyChatCard extends StatelessWidget {
  final List<RecordModel> debts;
  final List<RecordModel> payments;

  const _MoneyChatCard({required this.debts, required this.payments});

  List<_ChatItem> _items() {
    final items = <_ChatItem>[];
    for (final debt in debts) {
      items.add(_ChatItem.debt(debt));
    }
    for (final payment in payments) {
      items.add(_ChatItem.payment(payment));
    }
    items.sort((a, b) => b.created.compareTo(a.created));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.chat_bubble_outline_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('چاتی قەرز و پارەدانەوە', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 4),
          Text('زانیاری دارایی بە شێوەی چات و بە ڕیزبەندی کات.', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          if (items.isEmpty) const _EmptyLine(text: 'هێشتا هیچ مامەڵەیەک نییە.') else ...items.map((item) => _ChatBubble(item: item)),
        ]),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final _ChatItem item;

  const _ChatBubble({required this.item});

  @override
  Widget build(BuildContext context) {
    final isDebt = item.isDebt;
    final color = isDebt ? Colors.orange : Colors.green;
    return Align(
      alignment: isDebt ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withOpacity(0.09), borderRadius: BorderRadius.circular(18), border: Border.all(color: color.withOpacity(0.18))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isDebt ? 'قەرز زیادکرا' : 'پارەدانەوە تۆمارکرا', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(AppHelpers.formatCurrency(item.amount), textDirection: TextDirection.ltr, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
          if (item.description.isNotEmpty) ...[const SizedBox(height: 5), Text(item.description, style: Theme.of(context).textTheme.bodySmall)],
          if (isDebt) ...[const SizedBox(height: 5), Text('ماوە: ${AppHelpers.formatCurrency(item.remaining)}', textDirection: TextDirection.ltr, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold))],
          const SizedBox(height: 6),
          Text(AppHelpers.formatDateTime(item.created), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
        ]),
      ),
    );
  }
}

class _ChatItem {
  final bool isDebt;
  final double amount;
  final double remaining;
  final String description;
  final String created;

  const _ChatItem({required this.isDebt, required this.amount, required this.remaining, required this.description, required this.created});

  factory _ChatItem.debt(RecordModel debt) {
    final description = debt.getStringValue('description');
    return _ChatItem(isDebt: true, amount: debt.getDoubleValue('amount'), remaining: debt.getDoubleValue('remaining'), description: description.isEmpty ? 'قەرز' : description, created: debt.created);
  }

  factory _ChatItem.payment(RecordModel payment) {
    return _ChatItem(isDebt: false, amount: payment.getDoubleValue('amount'), remaining: 0, description: payment.getStringValue('note'), created: payment.created);
  }
}

class _ProfileToolsCard extends StatelessWidget {
  final VoidCallback onEditInfo;
  final VoidCallback onChangeLimit;

  const _ProfileToolsCard({required this.onEditInfo, required this.onChangeLimit});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ExpansionTile(
        leading: Icon(Icons.settings_rounded, color: AppColors.primary),
        title: const Text('ڕێکخستنەکانی کڕیار'),
        subtitle: const Text('زانیاری و سنووری قەرز لە بەشی جیا دەستکاری دەکرێن.'),
        children: [
          ListTile(leading: const Icon(Icons.person_outline), title: const Text('دەستکاری زانیاری کڕیار'), trailing: const Icon(Icons.chevron_left), onTap: onEditInfo),
          ListTile(leading: const Icon(Icons.verified_user_outlined), title: const Text('ڕێکخستنی سنووری قەرز'), trailing: const Icon(Icons.chevron_left), onTap: onChangeLimit),
        ],
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  final String text;

  const _EmptyLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(text, textAlign: TextAlign.center));
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(child: ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('دووبارە هەوڵ بدەوە')));
  }
}
