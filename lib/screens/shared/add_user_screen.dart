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
        AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.role == 'customer'
        ? AppStrings.addCustomer
        : AppStrings.addEmployee;
    final auth = context.read<AuthProvider>();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: isDark ? AppDarkColors.card : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with Gradient
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.primary.withOpacity(0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_add, color: Colors.white),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Form Content - Scrollable
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
                        label: AppStrings.name,
                        hint: 'ناوی سێ بەش',
                        icon: Icons.person_outline,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _phoneController,
                        label: AppStrings.phone,
                        hint: '07xxxxxxxxx',
                        icon: Icons.phone_android,
                        isPhone: true,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _passwordController,
                        label: AppStrings.password,
                        hint: 'وشەی نهێنی',
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

                      // Permissions Group
                      if (widget.role == 'employee' &&
                          auth.userRole == 'admin') ...[
                        const SizedBox(height: 24),
                        Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppDarkColors.surface
                                : const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? AppDarkColors.cardBorder
                                  : Colors.grey[200]!,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  8,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.admin_panel_settings_outlined,
                                      size: 18,
                                      color: isDark
                                          ? AppDarkColors.textSecondary
                                          : Colors.grey[700],
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'دەسەڵاتەکان',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? AppDarkColors.textPrimary
                                            : Colors.grey[800],
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
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
                                (v) =>
                                    setState(() => _canSendNotifications = v),
                                isLast: true,
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Debt Limit
                      if (widget.role == 'customer' &&
                          (auth.userRole == 'admin' ||
                              auth.canSetDebtLimit)) ...[
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _debtLimitController,
                          label: 'سنوری قەرز (0 = بێ سنور)',
                          hint: '0',
                          icon: Icons.money_off,
                          isPhone: true,
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),

            // Footer Actions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? AppDarkColors.cardBorder
                        : Colors.grey[100]!,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey[600],
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('پاشگەزبوونەوە'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              AppStrings.save,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
