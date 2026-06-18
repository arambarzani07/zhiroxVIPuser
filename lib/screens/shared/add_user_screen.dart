import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class AddUserDialog extends StatefulWidget {
  final String role;

  const AddUserDialog({super.key, required this.role});

  @override
  State<AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<AddUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _debtLimitController = TextEditingController(text: '0');

  bool _isLoading = false;
  bool _canAddCustomers = false;
  bool _canSetDebtLimit = false;
  bool _canSetDueDate = false;
  bool _canEditDebts = false;
  bool _canSendNotifications = false;

  bool get _isCustomer => widget.role == 'customer';

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _debtLimitController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    if (_isCustomer && !auth.isManager && !auth.canAddCustomers) {
      AppHelpers.showSnackBar(context, AppUserMessages.needsManagerApproval, isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final debtLimit = double.tryParse(_debtLimitController.text.trim().replaceAll(',', '')) ?? 0;
      final adminId = auth.isManager ? auth.userId : auth.adminId;

      await PBService.createUser(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text.trim(),
        role: widget.role,
        createdBy: auth.userId,
        adminId: adminId,
        canAddCustomers: _canAddCustomers,
        canSetDebtLimit: _canSetDebtLimit,
        canSetDueDate: _canSetDueDate,
        canEditDebts: _canEditDebts,
        canSendNotifications: _canSendNotifications,
        debtLimit: debtLimit,
      );

      if (!mounted) return;
      AppHelpers.showSnackBar(context, _isCustomer ? 'کڕیار زیادکرا ✅' : 'کارمەند زیادکرا ✅');
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        AppHelpers.showSnackBar(context, 'تکایە ژمارەی مۆبایل بە دروستی بنووسە', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isCustomer ? 'زیادکردنی کڕیار' : 'زیادکردنی کارمەند';
    final auth = context.read<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: isDark ? AppDarkColors.card : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Icon(_isCustomer ? Icons.person_add_alt_1_rounded : Icons.badge_rounded, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildTextField(
                          controller: _nameController,
                          label: _isCustomer ? 'ناوی کڕیار' : 'ناوی کارمەند',
                          hint: 'ناوی تەواو',
                          icon: Icons.person_outline,
                          validator: (v) => v == null || v.trim().isEmpty ? (_isCustomer ? 'تکایە ناوی کڕیار بنووسە' : 'تکایە ناوی کارمەند بنووسە') : null,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _phoneController,
                          label: 'ژمارەی مۆبایل',
                          hint: '07xxxxxxxxx',
                          icon: Icons.phone_android,
                          isPhone: true,
                          validator: (v) => v == null || v.trim().length < 7 ? 'تکایە ژمارەی مۆبایل بە دروستی بنووسە' : null,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _passwordController,
                          label: 'وشەی نهێنی',
                          hint: 'وشەی نهێنی',
                          icon: Icons.lock_outline,
                          isObscure: true,
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'تکایە وشەی نهێنی بنووسە';
                            if (v.length < 6) return 'وشەی نهێنی دەبێت کەمتر نەبێت لە ٦ پیت';
                            return null;
                          },
                        ),
                        if (!_isCustomer && auth.isManager) ...[
                          const SizedBox(height: 22),
                          _PermissionBox(
                            canAddCustomers: _canAddCustomers,
                            canSetDebtLimit: _canSetDebtLimit,
                            canSetDueDate: _canSetDueDate,
                            canEditDebts: _canEditDebts,
                            canSendNotifications: _canSendNotifications,
                            onAddCustomers: (v) => setState(() => _canAddCustomers = v),
                            onSetDebtLimit: (v) => setState(() => _canSetDebtLimit = v),
                            onSetDueDate: (v) => setState(() => _canSetDueDate = v),
                            onEditDebts: (v) => setState(() => _canEditDebts = v),
                            onSendNotifications: (v) => setState(() => _canSendNotifications = v),
                          ),
                        ],
                        if (_isCustomer && (auth.isManager || auth.canSetDebtLimit)) ...[
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _debtLimitController,
                            label: 'سنووری قەرز',
                            hint: '0',
                            icon: Icons.account_balance_wallet_rounded,
                            isPhone: true,
                            validator: (_) => null,
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          _isCustomer ? 'کڕیار دواتر دەتوانێت قەرز و وەصڵەکانی خۆی ببینێت.' : 'کارمەند تەنها بە پێی دەسەڵاتی بەڕێوەبەر کار دەکات.',
                          style: TextStyle(color: isDark ? AppDarkColors.textSecondary : AppColors.textSecondary, height: 1.5, fontSize: 12),
                          textAlign: TextAlign.start,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('پاشگەزبوونەوە'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _save,
                        child: _isLoading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('زیادکردن', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    bool isPhone = false,
    bool isObscure = false,
    String? Function(String?)? validator,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      obscureText: isObscure,
      keyboardType: isPhone ? TextInputType.number : TextInputType.text,
      textDirection: isPhone ? TextDirection.ltr : TextDirection.rtl,
      textAlign: isPhone ? TextAlign.center : TextAlign.start,
      style: TextStyle(color: isDark ? AppDarkColors.textPrimary : null),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.primary),
      ),
    );
  }
}

class _PermissionBox extends StatelessWidget {
  final bool canAddCustomers;
  final bool canSetDebtLimit;
  final bool canSetDueDate;
  final bool canEditDebts;
  final bool canSendNotifications;
  final ValueChanged<bool> onAddCustomers;
  final ValueChanged<bool> onSetDebtLimit;
  final ValueChanged<bool> onSetDueDate;
  final ValueChanged<bool> onEditDebts;
  final ValueChanged<bool> onSendNotifications;

  const _PermissionBox({
    required this.canAddCustomers,
    required this.canSetDebtLimit,
    required this.canSetDueDate,
    required this.canEditDebts,
    required this.canSendNotifications,
    required this.onAddCustomers,
    required this.onSetDebtLimit,
    required this.onSetDueDate,
    required this.onEditDebts,
    required this.onSendNotifications,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.06), borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          _switch('کڕیار زیادکردن', canAddCustomers, onAddCustomers),
          _switch('سنووری قەرز', canSetDebtLimit, onSetDebtLimit),
          _switch('بەرواری دانەوە', canSetDueDate, onSetDueDate),
          _switch('دەستکاری قەرز', canEditDebts, onEditDebts),
          _switch('ناردنی ئاگاداری', canSendNotifications, onSendNotifications),
        ],
      ),
    );
  }

  Widget _switch(String title, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      value: value,
      onChanged: onChanged,
      dense: true,
      activeThumbColor: AppColors.primary,
    );
  }
}
