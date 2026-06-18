import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class EmployeeAccessSettingsCard extends StatefulWidget {
  final RecordModel employee;
  final Color cardColor;
  final Color textColor;
  final Color subColor;
  final Future<void> Function()? onSaved;

  const EmployeeAccessSettingsCard({
    super.key,
    required this.employee,
    required this.cardColor,
    required this.textColor,
    required this.subColor,
    this.onSaved,
  });

  @override
  State<EmployeeAccessSettingsCard> createState() => _EmployeeAccessSettingsCardState();
}

class _EmployeeAccessSettingsCardState extends State<EmployeeAccessSettingsCard> {
  bool _saving = false;

  Future<void> _setAccess(String field, bool value) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await PBService.updateUser(widget.employee.id, {field: value});
      if (widget.onSaved != null) await widget.onSaved!();
      if (mounted) AppHelpers.showSnackBar(context, 'دەسەڵاتی کارمەند نوێکرایەوە ✅');
    } catch (_) {
      // Keep internal details invisible in market UI.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      _AccessItem('قەرز پێدان', 'can_add_debts', widget.employee.getBoolValue('can_add_debts')),
      _AccessItem('پارە وەرگرتنەوە', 'can_receive_payments', widget.employee.getBoolValue('can_receive_payments')),
      _AccessItem('کڕیار زیادکردن', 'can_add_customers', widget.employee.getBoolValue('can_add_customers')),
      _AccessItem('کەشف حساب', 'can_create_statements', widget.employee.getBoolValue('can_create_statements')),
      _AccessItem('ناردنی ئاگاداری', 'can_send_notifications', widget.employee.getBoolValue('can_send_notifications')),
      _AccessItem('بینینی ڕاپۆرت', 'can_view_reports', widget.employee.getBoolValue('can_view_reports')),
      _AccessItem('دەستکاری قەرز', 'can_edit_debts', widget.employee.getBoolValue('can_edit_debts')),
      _AccessItem('سنووری قەرز', 'can_set_debt_limit', widget.employee.getBoolValue('can_set_debt_limit')),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: widget.cardColor, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('ڕێکخستنی دەسەڵاتی کارمەند', style: TextStyle(color: widget.textColor, fontWeight: FontWeight.bold, fontSize: 16))),
              if (_saving) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 8),
          Text('بەڕێوەبەر دەتوانێت کاری ڕۆژانە و کردارە گرنگەکانی کارمەند چالاک یان ناچالاک بکات.', style: TextStyle(color: widget.subColor, height: 1.55, fontSize: 12)),
          const SizedBox(height: 12),
          ...items.map((item) => _AccessSwitch(item: item, subColor: widget.subColor, disabled: _saving, onChanged: _setAccess)),
        ],
      ),
    );
  }
}

class _AccessItem {
  final String label;
  final String field;
  final bool value;

  const _AccessItem(this.label, this.field, this.value);
}

class _AccessSwitch extends StatelessWidget {
  final _AccessItem item;
  final Color subColor;
  final bool disabled;
  final Future<void> Function(String field, bool value) onChanged;

  const _AccessSwitch({required this.item, required this.subColor, required this.disabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(item.value ? Icons.check_circle_rounded : Icons.lock_clock_rounded, color: item.value ? AppColors.secondary : AppColors.warning, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(item.value ? 'چالاکە' : 'بە ڕێگەپێدانی بەڕێوەبەر', style: TextStyle(color: subColor, fontSize: 11)),
              ],
            ),
          ),
          Switch(value: item.value, onChanged: disabled ? null : (value) => onChanged(item.field, value)),
        ],
      ),
    );
  }
}
