import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/market_action_queue.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class AddPaymentScreenClean extends StatefulWidget {
  final String? debtId;

  const AddPaymentScreenClean({super.key, this.debtId});

  @override
  State<AddPaymentScreenClean> createState() => _AddPaymentScreenCleanState();
}

class _AddPaymentScreenCleanState extends State<AddPaymentScreenClean> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  List<RecordModel> _debts = [];
  String? _selectedDebtId;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedDebtId = widget.debtId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDebts());
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadDebts() async {
    final auth = context.read<AuthProvider>();
    final adminId = auth.adminId.isNotEmpty ? auth.adminId : auth.userId;
    try {
      final allDebts = await PBService.getDebts(adminId: adminId, perPage: 500);
      final openDebts = allDebts.where((debt) => debt.getDoubleValue('remaining') > 0).toList();
      if (mounted) _debts = openDebts;
    } catch (_) {
      // Keep the screen calm and preserve visible state.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  RecordModel? _selectedDebt() {
    final id = _selectedDebtId;
    if (id == null) return null;
    for (final debt in _debts) {
      if (debt.id == id) return debt;
    }
    return null;
  }

  String _customerName(RecordModel debt) {
    final customer = debt.expand['customer']?.isNotEmpty == true ? debt.expand['customer']!.first : null;
    final name = customer?.getStringValue('name') ?? '';
    return name.isEmpty ? 'کڕیار' : name;
  }

  double _amount() {
    return double.tryParse(_amountController.text.replaceAll(',', '').trim()) ?? 0;
  }

  Future<void> _savePayment() async {
    if (_isSaving) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isManager && !auth.canReceivePayment) {
      AppHelpers.showSnackBar(context, AppUserMessages.needsManagerApproval, isError: true);
      return;
    }

    final debt = _selectedDebt();
    if (debt == null) {
      AppHelpers.showSnackBar(context, 'تکایە قەرزێک هەڵبژێرە', isError: true);
      return;
    }

    final remaining = debt.getDoubleValue('remaining');
    final amount = _amount();
    if (amount <= 0) {
      AppHelpers.showSnackBar(context, 'بڕی پارە دەبێت لە سفر زیاتر بێت', isError: true);
      return;
    }
    if (amount > remaining) {
      AppHelpers.showSnackBar(context, 'بڕی پارە نابێت زیاتر بێت لە قەرزی ماوە', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    final note = _noteController.text.trim();
    try {
      await PBService.createPayment(
        debtId: debt.id,
        amount: amount,
        note: note.isEmpty ? null : note,
        createdBy: auth.userId,
        createdByName: auth.userName,
        adminId: auth.adminId.isNotEmpty ? auth.adminId : auth.userId,
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'پارە وەرگیرا ✅');
      Navigator.pop(context, true);
    } catch (_) {
      await MarketActionQueue.instance.savePaymentAction(
        debtId: debt.id,
        amount: amount,
        note: note.isEmpty ? null : note,
        createdBy: auth.userId,
        createdByName: auth.userName,
        adminId: auth.adminId.isNotEmpty ? auth.adminId : auth.userId,
      );
      if (!mounted) return;
      AppHelpers.showSnackBar(context, AppUserMessages.protectedOffline);
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppDarkColors.card : Colors.white;
    final textColor = isDark ? AppDarkColors.textPrimary : AppColors.textPrimary;
    final subColor = isDark ? AppDarkColors.textSecondary : AppColors.textSecondary;
    final debt = _selectedDebt();
    final remaining = debt?.getDoubleValue('remaining') ?? 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
        appBar: AppBar(title: const Text('پارە وەرگرتنەوە')),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('قەرز هەڵبژێرە', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedDebtId,
                        decoration: const InputDecoration(labelText: 'قەرزێک هەڵبژێرە'),
                        items: _debts.map((debt) {
                          final name = _customerName(debt);
                          final remaining = debt.getDoubleValue('remaining');
                          return DropdownMenuItem(value: debt.id, child: Text('$name — ${AppHelpers.formatCurrency(remaining)}'));
                        }).toList(),
                        onChanged: (value) => setState(() => _selectedDebtId = value),
                      ),
                      if (debt != null) ...[
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: Text('قەرزی ماوە', style: TextStyle(color: subColor))),
                          Text(AppHelpers.formatCurrency(remaining), textDirection: TextDirection.ltr, style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
                        ]),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('بڕی پارە', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _amountController,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(labelText: 'بڕی پارە', prefixIcon: Icon(Icons.payments_rounded), suffixText: 'د.ع'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _noteController,
                        minLines: 2,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: 'تێبینی', prefixIcon: Icon(Icons.edit_note_rounded)),
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
                      Expanded(child: Text('پێش وەرگرتنی پارە، بڕەکە پشکنرێت کە زیاتر نەبێت لە قەرزی ماوە.', style: TextStyle(color: subColor, height: 1.6))),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _savePayment,
                      icon: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_rounded),
                      label: Text(_isSaving ? 'تۆمارکردن...' : 'پارە وەرگرە'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
