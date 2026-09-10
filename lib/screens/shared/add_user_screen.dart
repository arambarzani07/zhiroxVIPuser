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
  int _employeeSection = 0;
  bool _canAddCustomers = false;
  bool _canSetDebtLimit = false;
  bool _canSetDueDate = false;
  bool _canEditDebts = false;

  bool _canSendNotifications = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _debtLimitController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    if (name.isEmpty || phone.isEmpty || password.length < 8) {
      if (widget.role == 'employee' && _employeeSection != 0 && mounted) {
        setState(() => _employeeSection = 0);
      }
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          password.isNotEmpty && password.length < 8
              ? 'وشەی نهێنی نابێت لە ٨ پیت کەمتر بێت'
              : 'تکایە زانیاری بنەڕەتی تەواو بکە',
          isError: true,
        );
      }
      return;
    }
    if (!(_formKey.currentState?.validate() ?? true)) return;

    setState(() => _isLoading = true);

    try {
      final auth = context.read<AuthProvider>();
      final debtLimit = double.tryParse(_debtLimitController.text.trim()) ?? 0;

      await PBService.createUser(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text,
        role: widget.role,
        createdBy: auth.userId,
        adminId: auth.adminId,
        canAddCustomers: _canAddCustomers,
        canSetDebtLimit: _canSetDebtLimit,
        canSetDueDate: _canSetDueDate,
        canEditDebts: _canEditDebts,
        canSendNotifications: _canSendNotifications,
        debtLimit: debtLimit,
      );

      if (mounted) {
        AppHelpers.showSnackBar(context, 'بە سەرکەوتوویی زیادکرا');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(context, 'نەتوانرا هەژمارەکە زیاد بکرێت. دووبارە هەوڵ بدە.', isError: true);
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isEmployee = widget.role == 'employee';
    final title = widget.role == 'customer'
        ? AppStrings.addCustomer
        : AppStrings.addEmployee;
    final auth = context.read<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showEmployeePermissions = isEmployee && auth.userRole == 'admin';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      backgroundColor: isDark ? AppDarkColors.card : Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      isEmployee
                          ? Icons.badge_outlined
                          : Icons.person_add_alt_1_outlined,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? AppDarkColors.textPrimary
                                : const Color(0xFF1D2939),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isEmployee
                              ? 'زانیاری هەژمار و دەسەڵاتەکان'
                              : 'زانیاری سەرەکی کڕیار',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppDarkColors.textSecondary
                                : const Color(0xFF98A2B3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'داخستن',
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 21),
                  ),
                ],
              ),
            ),
            if (showEmployeePermissions)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppDarkColors.surface
                        : const Color(0xFFF1F4F8),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      _buildSectionTab(
                        label: 'زانیاری',
                        icon: Icons.person_outline_rounded,
                        index: 0,
                        isDark: isDark,
                      ),
                      _buildSectionTab(
                        label: 'دەسەڵاتەکان',
                        icon: Icons.admin_panel_settings_outlined,
                        index: 1,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
              ),
            Divider(
              height: 1,
              color: isDark
                  ? AppDarkColors.cardBorder
                  : const Color(0xFFEAECF0),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Form(
                  key: _formKey,
                  child: showEmployeePermissions && _employeeSection == 1
                      ? _buildPermissionSection(isDark)
                      : _buildIdentitySection(
                          isDark: isDark,
                          auth: auth,
                          isEmployee: isEmployee,
                        ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? AppDarkColors.cardBorder
                        : const Color(0xFFEAECF0),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        foregroundColor: isDark
                            ? AppDarkColors.textSecondary
                            : const Color(0xFF667085),
                        side: BorderSide(
                          color: isDark
                              ? AppDarkColors.cardBorder
                              : const Color(0xFFD0D5DD),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('پاشگەزبوونەوە'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _save,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 19),
                      label: Text(
                        _isLoading ? 'چاوەڕوان بە...' : AppStrings.save,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTab({
    required String label,
    required IconData icon,
    required int index,
    required bool isDark,
  }) {
    final selected = _employeeSection == index;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          if (_employeeSection != index) {
            setState(() => _employeeSection = index);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? AppDarkColors.card : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected
                    ? AppColors.primary
                    : (isDark
                        ? AppDarkColors.textSecondary
                        : const Color(0xFF667085)),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? AppColors.primary
                      : (isDark
                          ? AppDarkColors.textSecondary
                          : const Color(0xFF667085)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdentitySection({
    required bool isDark,
    required AuthProvider auth,
    required bool isEmployee,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('زانیاری بنەڕەتی', Icons.person_outline_rounded, isDark),
        const SizedBox(height: 10),
        _buildTextField(
          controller: _nameController,
          label: AppStrings.name,
          hint: 'ناوی تەواو',
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 12),
        _buildTextField(
          controller: _phoneController,
          label: AppStrings.phone,
          hint: '07xxxxxxxxx',
          icon: Icons.phone_android,
          isPhone: true,
        ),
        const SizedBox(height: 12),
        _buildTextField(
          controller: _passwordController,
          label: AppStrings.password,
          hint: 'لانیکەم ٨ پیت',
          icon: Icons.lock_outline,
          isObscure: true,
          validator: (v) {
            if (v == null || v.isEmpty) {
              return 'تکایە وشەی نهێنی بنووسە';
            }
            if (v.length < 8) return 'نابێت لە ٨ پیت کەمتر بێت';
            return null;
          },
        ),
        if (!isEmployee &&
            (auth.userRole == 'admin' || auth.canSetDebtLimit)) ...[
          const SizedBox(height: 18),
          _sectionLabel(
            'ڕێکخستنی قەرز — ئارەزوومەندانە',
            Icons.account_balance_wallet_outlined,
            isDark,
          ),
          const SizedBox(height: 10),
          _buildTextField(
            controller: _debtLimitController,
            label: 'سنوری قەرز',
            hint: '0 = بێ سنور',
            icon: Icons.account_balance_wallet_outlined,
            isPhone: true,
          ),
        ],
      ],
    );
  }

  Widget _buildPermissionSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(
          'دەسەڵاتەکانی کارمەند',
          Icons.admin_panel_settings_outlined,
          isDark,
        ),
        const SizedBox(height: 6),
        Text(
          'تەنها ئەو کارانە چالاک بکە کە پێویستی پێیان هەیە.',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.5,
            color: isDark
                ? AppDarkColors.textSecondary
                : const Color(0xFF667085),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppDarkColors.surface : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? AppDarkColors.cardBorder
                  : const Color(0xFFE4E7EC),
            ),
          ),
          child: Column(
            children: [
              _buildSwitch(
                'زیادکردنی کڕیار',
                _canAddCustomers,
                (v) => setState(() => _canAddCustomers = v),
              ),
              _buildSwitch(
                'دانانی سنوری قەرز',
                _canSetDebtLimit,
                (v) => setState(() => _canSetDebtLimit = v),
              ),
              _buildSwitch(
                'دانانی بەرواری دانەوە',
                _canSetDueDate,
                (v) => setState(() => _canSetDueDate = v),
              ),
              _buildSwitch(
                'دەستکاریکردنی قەرز',
                _canEditDebts,
                (v) => setState(() => _canEditDebts = v),
              ),
              _buildSwitch(
                'ناردنی ئاگادارکردنەوە',
                _canSendNotifications,
                (v) => setState(() => _canSendNotifications = v),
                isLast: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String label, IconData icon, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 17, color: AppColors.primary),
        const SizedBox(width: 7),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isDark
                ? AppDarkColors.textPrimary
                : const Color(0xFF344054),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitch(
    String title,
    bool value,
    Function(bool) onChanged, {
    bool isLast = false,
  }) {
    return Column(
      children: [
        SwitchListTile(
          title: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppDarkColors.textPrimary
                  : null,
            ),
          ),
          value: value,
          onChanged: onChanged,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
          dense: true,
          activeThumbColor: AppColors.primary,
          visualDensity: VisualDensity.compact,
        ),
        if (!isLast)
          Divider(
            height: 1,
            indent: 12,
            endIndent: 12,
            color: Colors.grey[100],
          ),
      ],
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
      validator:
          validator ??
          (v) => v?.isEmpty == true ? 'تکایە ئەم بەشە پڕبکەرەوە' : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: isDark ? AppDarkColors.textSecondary : null,
        ),
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? AppDarkColors.textSecondary : Colors.grey[400],
        ),
        prefixIcon: Icon(icon, color: AppColors.primary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppDarkColors.cardBorder : Colors.grey[300]!,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppDarkColors.cardBorder : Colors.grey[300]!,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        filled: true,
        fillColor: isDark ? AppDarkColors.inputFill : Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }
}
