import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/market_action_queue.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class AddDebtScreenClean extends StatefulWidget {
  final String? customerId;

  const AddDebtScreenClean({super.key, this.customerId});

  @override
  State<AddDebtScreenClean> createState() => _AddDebtScreenCleanState();
}

class _AddDebtScreenCleanState extends State<AddDebtScreenClean> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  List<RecordModel> _customers = [];
  String? _selectedCustomerId;
  DateTime? _dueDate;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedCustomerId = widget.customerId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCustomers());
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    final auth = context.read<AuthProvider>();
    final adminId = auth.adminId.isNotEmpty ? auth.adminId : auth.userId;
    try {
      final customers = await PBService.getUsers(role: 'customer', adminId: adminId, approved: true);
      if (mounted) _customers = customers;
    } catch (_) {
      // Keep screen calm and preserve visible state.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double _amount() {
    return double.tryParse(_amountController.text.replaceAll(',', '').trim()) ?? 0;
  }

  RecordModel? _selectedCustomer() {
    final id = _selectedCustomerId;
    if (id == null) return null;
    for (final customer in _customers) {
      if (customer.id == id) return customer;
    }
    return null;
  }

  Future<bool> _confirmLimitIfNeeded(double amount) async {
    final customer = _selectedCustomer();
    if (customer == null) return false;
    final limit = customer.getDoubleValue('debt_limit');
    if (limit <= 0) return true;

    double currentBalance = 0;
    try {
      currentBalance = await PBService.getCustomerBalance(customer.id);
    } catch (_) {
      currentBalance = 0;
    }

    if (currentBalance + amount <= limit) return true;
    if (!mounted) return false;

    final auth = context.read<AuthProvider>();
    if (!auth.isManager && !auth.canSetDebtLimit) {
      AppHelpers.showSnackBar(context, AppUserMessages.debtLimitExceeded, isError: true);
      return false;
    }

    final confirm = await AppHelpers.showConfirmDialog(
      context,
      title: 'سنووری قەرزی کڕیار تێپەڕێنرا',
      message: 'ئەم بڕە سنووری قەرزی کڕیار تێدەپەڕێنێت. دەتەوێت بە بڕیاری بەڕێوەبەر بەردەوام بیت؟',
    );
    return confirm;
  }

  Future<void> _saveDebt() async {
    if (_isSaving) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isManager && !auth.canGiveDebt) {
      AppHelpers.showSnackBar(context, AppUserMessages.needsManagerApproval, isError: true);
      return;
    }

    final customerId = _selectedCustomerId;
    if (customerId == null || customerId.isEmpty) {
      AppHelpers.showSnackBar(context, 'تکایە کڕیارێک هەڵبژێرە', isError: true);
      return;
    }

    final amount = _amount();
    if (amount <= 0) {
      AppHelpers.showSnackBar(context, 'بڕی قەرز دەبێت لە سفر زیاتر بێت', isError: true);
      return;
    }

    final canContinue = await _confirmLimitIfNeeded(amount);
    if (!canContinue) return;

    setState(() => _isSaving = true);
    final dueDateText = _dueDate == null ? '' : DateFormat('yyyy-MM-dd').format(_dueDate!);
    final note = _noteController.text.trim();
    final description = note.isEmpty ? 'قەرزی نوێ' : note;

    try {
      await PBService.createDebt(
        customerId: customerId,
        description: description,
        amount: amount,
        dueDate: dueDateText,
        createdBy: auth.userId,
        adminId: auth.adminId.isNotEmpty ? auth.adminId : auth.userId,
        currency: 'IQD',
        dollarRate: 0,
        amountUsd: 0,
        items: [
          {'name': description, 'price': amount, 'qty': 1, 'currency': 'IQD'},
        ],
        createdByName: auth.userName,
        marketName: auth.marketName,
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'قەرز تۆمارکرا ✅');
      Navigator.pop(context, true);
    } catch (_) {
      await MarketActionQueue.instance.saveDebtAction(
        customerId: customerId,
        description: description,
        amount: amount,
        dueDate: dueDateText,
        createdBy: auth.userId,
        adminId: auth.adminId.isNotEmpty ? auth.adminId : auth.userId,
        currency: 'IQD',
        items: [
          {'name': description, 'price': amount, 'qty': 1, 'currency': 'IQD'},
        ],
        createdByName: auth.userName,
        marketName: auth.marketName,
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(context, AppUserMessages.protectedOffline);
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null && mounted) setState(() => _dueDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppDarkColors.card : Colors.white;
    final textColor = isDark ? AppDarkColors.textPrimary : AppColors.textPrimary;
    final subColor = isDark ? AppDarkColors.textSecondary : AppColors.textSecondary;
    final customer = _selectedCustomer();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
        appBar: AppBar(title: const Text('قەرز پێدان')),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('کڕیار', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedCustomerId,
                        decoration: const InputDecoration(labelText: 'کڕیارێک هەڵبژێرە'),
                        items: _customers.map((customer) => DropdownMenuItem(value: customer.id, child: Text(customer.getStringValue('name').isEmpty ? 'کڕیار' : customer.getStringValue('name')))).toList(),
                        onChanged: (value) => setState(() => _selectedCustomerId = value),
                      ),
                      if (customer != null) ...[
                        const SizedBox(height: 8),
                        Text(customer.getStringValue('phone'), textDirection: TextDirection.ltr, style: TextStyle(color: subColor)),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('بڕی قەرز', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _amountController,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(labelText: 'بڕی قەرز', prefixIcon: Icon(Icons.payments_rounded), suffixText: 'د.ع'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _noteController,
                        minLines: 2,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: 'تێبینی یان ناوی کاڵا', prefixIcon: Icon(Icons.edit_note_rounded)),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _pickDueDate,
                        icon: const Icon(Icons.event_rounded),
                        label: Text(_dueDate == null ? 'بەرواری دانەوە هەڵبژێرە' : DateFormat('yyyy/MM/dd').format(_dueDate!)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
                    child: Row(children: [
                      const Icon(Icons.shield_rounded, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Expanded(child: Text('پێش تۆمارکردن، سنووری قەرزی کڕیار و دەسەڵاتی کارمەند پشکنرێت.', style: TextStyle(color: subColor, height: 1.6))),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _saveDebt,
                      icon: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_rounded),
                      label: Text(_isSaving ? 'تۆمارکردن...' : 'قەرز تۆمار بکە'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
