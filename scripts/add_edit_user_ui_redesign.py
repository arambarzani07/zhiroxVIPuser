from pathlib import Path
import re

add_path = Path('lib/screens/shared/add_user_screen.dart')
profile_path = Path('lib/screens/shared/user_profile_screen.dart')

text = add_path.read_text()

# Add a local section selector for employee creation.
text = text.replace(
    "  bool _isLoading = false;\n",
    "  bool _isLoading = false;\n  int _employeeSection = 0;\n",
    1,
)

# Do not expose raw backend errors to end users.
text = text.replace(
    "AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);",
    "AppHelpers.showSnackBar(context, 'نەتوانرا هەژمارەکە زیاد بکرێت. دووبارە هەوڵ بدە.', isError: true);",
    1,
)

# Replace the dialog body with a compact, sectioned form while preserving save logic.
start = text.index('  @override\n  Widget build(BuildContext context) {')
end = text.index('\n  Widget _buildSwitch(', start)
new_build = r'''  @override
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
'''
text = text[:start] + new_build + text[end:]

# Make switch rows compact and aligned with the app's current visual language.
text = text.replace(
    "contentPadding: const EdgeInsets.symmetric(horizontal: 12),\n          dense: true,",
    "contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),\n          dense: true,",
    1,
)

# Slightly tighter fields.
text = text.replace(
    "horizontal: 16,\n          vertical: 14,",
    "horizontal: 14,\n          vertical: 12,",
    1,
)
add_path.write_text(text)

# ── Edit form polish ─────────────────────────────────────────────────────────
p = profile_path.read_text()
# Neutral bordered editor card rather than another shadow-heavy panel.
p = p.replace(
    "borderRadius: BorderRadius.circular(16),\n            boxShadow: isDark\n                ? []\n                : [\n                    BoxShadow(\n                      color: Colors.black.withOpacity(0.04),\n                      blurRadius: 10,\n                      offset: const Offset(0, 3),\n                    ),\n                  ],",
    "borderRadius: BorderRadius.circular(14),\n            border: Border.all(\n              color: isDark\n                  ? Colors.white.withValues(alpha: 0.06)\n                  : const Color(0xFFE4E7EC),\n            ),",
    1,
)
p = p.replace("padding: const EdgeInsets.all(20),", "padding: const EdgeInsets.all(14),", 1)
p = p.replace(
    "'گۆڕانکاری لە زانیارییەکان'",
    "'زانیاری هەژمار'",
    1,
)
p = p.replace("fontSize: 17,\n                        fontWeight: FontWeight.bold,", "fontSize: 15,\n                        fontWeight: FontWeight.w800,", 1)
p = p.replace("const SizedBox(height: 20),", "const SizedBox(height: 14),", 1)
# First three field gaps in editor.
for _ in range(3):
    p = p.replace("const SizedBox(height: 14),", "const SizedBox(height: 12),", 1)
p = p.replace("height: 50,", "height: 46,", 1)
p = p.replace("borderRadius: BorderRadius.circular(14),", "borderRadius: BorderRadius.circular(12),", 1)
profile_path.write_text(p)
