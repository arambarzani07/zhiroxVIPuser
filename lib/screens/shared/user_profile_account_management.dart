part of 'user_profile_screen.dart';

extension _UserProfileAccountManagement on _UserProfileScreenState {
  String _friendlyPasswordError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('network') ||
        raw.contains('socketexception') ||
        raw.contains('clientexception') ||
        raw.contains('connection')) {
      return 'پەیوەندی بە سێرڤەر نەکرا. ئینتەرنێتەکەت بپشکنە.';
    }
    if (raw.contains('old') || raw.contains('کۆن')) {
      return 'وشەی نهێنیی کۆن هەڵەیە.';
    }
    if (raw.contains('forbidden') ||
        raw.contains('permission') ||
        raw.contains('دەسەڵات')) {
      return 'دەسەڵاتی گۆڕینی ئەم وشەی نهێنییەت نییە.';
    }
    return 'نەتوانرا وشەی نهێنی بگۆڕدرێت. دووبارە هەوڵ بدە.';
  }

  Future<void> _showChangeOwnPasswordDialog() async {
    final oldController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var loading = false;
    var obscureOld = true;
    var obscureNew = true;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('گۆڕینی وشەی نهێنی'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: oldController,
                      obscureText: obscureOld,
                      decoration: InputDecoration(
                        labelText: 'وشەی نهێنیی کۆن',
                        prefixIcon: const Icon(Icons.lock_clock_outlined),
                        suffixIcon: IconButton(
                          onPressed: () => setDialogState(
                            () => obscureOld = !obscureOld,
                          ),
                          icon: Icon(
                            obscureOld ? Icons.visibility_off : Icons.visibility,
                          ),
                        ),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'وشەی نهێنیی کۆن بنووسە'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: newController,
                      obscureText: obscureNew,
                      decoration: InputDecoration(
                        labelText: 'وشەی نهێنیی نوێ',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setDialogState(
                            () => obscureNew = !obscureNew,
                          ),
                          icon: Icon(
                            obscureNew ? Icons.visibility_off : Icons.visibility,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'وشەی نهێنیی نوێ بنووسە';
                        }
                        if (value.length < 8) {
                          return 'وشەی نهێنی لانیکەم ٨ پیت بێت';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmController,
                      obscureText: obscureNew,
                      decoration: const InputDecoration(
                        labelText: 'دووبارەکردنەوەی وشەی نهێنی',
                        prefixIcon: Icon(Icons.lock_reset_rounded),
                      ),
                      validator: (value) => value != newController.text
                          ? 'وشەی نهێنی یەکناگرنەوە'
                          : null,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: loading ? null : () => Navigator.pop(dialogContext),
                  child: const Text('پاشگەزبوونەوە'),
                ),
                ElevatedButton(
                  onPressed: loading
                      ? null
                      : () async {
                          final form = formKey.currentState;
                          if (form == null || !form.validate()) return;
                          setDialogState(() => loading = true);
                          try {
                            await PBService.changePassword(
                              userId: widget.userId,
                              oldPassword: oldController.text,
                              newPassword: newController.text,
                            );
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            if (mounted) {
                              AppHelpers.showSnackBar(
                                context,
                                'وشەی نهێنی بە سەرکەوتوویی گۆڕدرا',
                              );
                            }
                          } catch (e) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() => loading = false);
                            if (mounted) {
                              AppHelpers.showSnackBar(
                                context,
                                _friendlyPasswordError(e),
                                isError: true,
                              );
                            }
                          }
                        },
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('گۆڕین'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      oldController.dispose();
      newController.dispose();
      confirmController.dispose();
    }
  }

  Future<void> _showAdminResetPasswordDialog() async {
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var loading = false;
    var obscure = true;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('ڕێکخستنەوەی وشەی نهێنی'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: newController,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: 'وشەی نهێنیی نوێ',
                        prefixIcon: const Icon(Icons.lock_reset_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setDialogState(() => obscure = !obscure),
                          icon: Icon(
                            obscure ? Icons.visibility_off : Icons.visibility,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'وشەی نهێنیی نوێ بنووسە';
                        }
                        if (value.length < 8) {
                          return 'وشەی نهێنی لانیکەم ٨ پیت بێت';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmController,
                      obscureText: obscure,
                      decoration: const InputDecoration(
                        labelText: 'دووبارەکردنەوەی وشەی نهێنی',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                      ),
                      validator: (value) => value != newController.text
                          ? 'وشەی نهێنی یەکناگرنەوە'
                          : null,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: loading ? null : () => Navigator.pop(dialogContext),
                  child: const Text('پاشگەزبوونەوە'),
                ),
                ElevatedButton(
                  onPressed: loading
                      ? null
                      : () async {
                          final form = formKey.currentState;
                          if (form == null || !form.validate()) return;
                          setDialogState(() => loading = true);
                          try {
                            await PBService.resetUserPassword(
                              userId: widget.userId,
                              newPassword: newController.text,
                            );
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            if (mounted) {
                              AppHelpers.showSnackBar(
                                context,
                                'وشەی نهێنیی هەژمارەکە ڕێکخرایەوە',
                              );
                            }
                          } catch (e) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() => loading = false);
                            if (mounted) {
                              AppHelpers.showSnackBar(
                                context,
                                _friendlyPasswordError(e),
                                isError: true,
                              );
                            }
                          }
                        },
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('ڕێکخستنەوە'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      newController.dispose();
      confirmController.dispose();
    }
  }

  // ═══════════════════════════════════════════
  // ── Shared Profile Editor ──
  // ═══════════════════════════════════════════

  Widget _buildProfileEditor() {
    final auth = context.read<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool canEditInfo = auth.userRole == 'admin';
    final bool isSelf = auth.userId == widget.userId;
    final bool canAdminResetPassword =
        auth.userRole == 'admin' && !isSelf && (_isCustomer || _isEmployee);
    final bool canManagePassword = isSelf || canAdminResetPassword;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? AppDarkColors.card : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFE4E7EC),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 20, color: _accentColor),
                    const SizedBox(width: 8),
                    Text(
                      'زانیاری هەژمار',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppDarkColors.textPrimary
                            : Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _nameController,
                  label: AppStrings.name,
                  icon: Icons.person_outline,
                  readOnly: !canEditInfo,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _phoneController,
                  label: AppStrings.phone,
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  readOnly: !canEditInfo,
                ),
                if (canManagePassword) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: isSelf
                          ? _showChangeOwnPasswordDialog
                          : _showAdminResetPasswordDialog,
                      icon: const Icon(Icons.lock_reset_rounded, size: 19),
                      label: Text(
                        isSelf
                            ? 'گۆڕینی وشەی نهێنی'
                            : 'ڕێکخستنەوەی وشەی نهێنی',
                      ),
                    ),
                  ),
                ],
                if (canEditInfo) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfileChanges,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.save_outlined, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'پاشەکەوتکردن',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // ── Debt Limit Card ──
  // ═══════════════════════════════════════════

  Widget _buildDebtLimitCard() {
    final auth = context.read<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final limit = _user!.getDoubleValue('debt_limit');
    final hasLimit = limit > 0;
    final canEdit = auth.canSetDebtLimit;
    final totalRemaining = _financeTotalRemainingIqd;
    final totalsComplete = _financeSummaryComplete;
    final remainingLimit =
        hasLimit && totalsComplete ? limit - totalRemaining : 0.0;
    final isOverLimit = hasLimit && totalsComplete && remainingLimit < 0;
    final usagePercent = hasLimit && totalsComplete
        ? (totalRemaining / limit).clamp(0.0, 1.0)
        : 0.0;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? AppDarkColors.card : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: isDark
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            (hasLimit
                                    ? (isOverLimit ? Colors.red : Colors.teal)
                                    : Colors.grey)
                                .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        hasLimit
                            ? Icons.account_balance_wallet
                            : Icons.money_off_csred_outlined,
                        color: hasLimit
                            ? (isOverLimit ? Colors.red : Colors.teal)
                            : Colors.grey,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'سنووری قەرز',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppDarkColors.textPrimary
                                  : Colors.black87,
                            ),
                          ),
                          Text(
                            hasLimit
                                ? AppHelpers.formatCurrency(limit)
                                : 'سنور دانەنراوە',
                            style: TextStyle(
                              fontSize: 13,
                              color: hasLimit
                                  ? (isDark
                                        ? AppDarkColors.textSecondary
                                        : Colors.black54)
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (canEdit)
                      InkWell(
                        onTap: () => _showDebtLimitDialog(limit),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                hasLimit ? Icons.edit : Icons.add,
                                size: 16,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                hasLimit ? 'دەستکاری' : 'دانان',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),

                // Progress bar & details (only if limit is set)
                if (hasLimit) ...[
                  const SizedBox(height: 14),
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: usagePercent,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isOverLimit
                            ? Colors.red
                            : usagePercent > 0.8
                            ? Colors.orange
                            : Colors.teal,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Stats row
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'قەرزی ئێستا',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            Text(
                              AppHelpers.formatCurrency(totalRemaining),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isOverLimit
                                    ? Colors.red
                                    : (isDark
                                          ? AppDarkColors.textPrimary
                                          : Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              isOverLimit ? 'زیادبوو' : 'بەردەستە',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            Text(
                              totalsComplete ? AppHelpers.formatCurrency(remainingLimit.abs()) : '—',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isOverLimit ? Colors.red : Colors.teal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDebtLimitDialog(double currentLimit) {
    final formatter = NumberFormat('#,###', 'en');
    _debtLimitController.text = currentLimit > 0
        ? formatter.format(currentLimit)
        : '';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.account_balance_wallet,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'سنووری قەرز',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (currentLimit > 0)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'سنوری ئێستا: ${AppHelpers.formatCurrency(currentLimit)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            TextFormField(
              controller: _debtLimitController,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppDarkColors.textPrimary
                    : null,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                ThousandsSeparatorInputFormatter(),
              ],
              decoration: InputDecoration(
                labelText: 'بڕی سنور (د.ع)',
                hintText: '500,000',
                prefixIcon: const Icon(Icons.attach_money),
                suffixText: 'د.ع',
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? AppDarkColors.inputFill
                    : Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'ئەگەر بەتاڵ بهێڵیتەوە، سنور لابردراوە',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('پاشگەزبوونەوە'),
          ),
          if (currentLimit > 0)
            TextButton(
              onPressed: () async {
                // Remove limit
                try {
                  await PBService.updateUser(widget.userId, {'debt_limit': 0});
                  if (!mounted || !dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  AppHelpers.showSnackBar(context, 'سنووری قەرز لابرا');
                  _loadData();
                } catch (e) {
                  if (mounted) {
                    AppHelpers.showSnackBar(context, AppHelpers.backendErrorMessage(e), isError: true);
                  }
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('لابردن'),
            ),
          ElevatedButton(
            onPressed: () async {
              final rawText = _debtLimitController.text
                  .replaceAll(',', '')
                  .trim();
              final newLimit = double.tryParse(rawText) ?? 0;

              try {
                await PBService.updateUser(widget.userId, {
                  'debt_limit': newLimit,
                });
                if (!mounted || !dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                AppHelpers.showSnackBar(
                  context,
                  newLimit > 0
                      ? 'سنووری قەرز دانرا: ${AppHelpers.formatCurrency(newLimit)}'
                      : 'سنووری قەرز لابرا',
                );
                _loadData();
              } catch (e) {
                if (mounted) {
                  AppHelpers.showSnackBar(context, AppHelpers.backendErrorMessage(e), isError: true);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('پاشەکەوتکردن'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // ── Shared Widgets ──
  // ═══════════════════════════════════════════
}
