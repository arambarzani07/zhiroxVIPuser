part of 'user_profile_screen.dart';

extension _UserProfileEmployeeManagement on _UserProfileScreenState {
  List<Widget> _buildEmployeeBody() {
    final overview = <Widget>[
      if (_employeeStats.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                _buildStatChip(
                  Icons.receipt_long_outlined,
                  'قەرزی تۆمارکراو',
                  AppHelpers.formatCurrency(_employeeStats['totalDebtsCreated'] ?? 0),
                  Colors.orange,
                ),
                const SizedBox(width: 10),
                _buildStatChip(
                  Icons.payments_outlined,
                  'پارەی وەرگیراو',
                  AppHelpers.formatCurrency(_employeeStats['totalPaymentsCollected'] ?? 0),
                  Colors.green,
                ),
              ],
            ),
          ),
        ),
      _buildEmployeeStatusCard(),
    ];

    final permissions = <Widget>[
      _buildEmployeePermissionsCard(),
    ];

    final edit = <Widget>[
      _buildProfileEditor(),
    ];

    return [
      _buildEmployeeSectionTabs(),
      ...switch (_employeeSection) {
        1 => permissions,
        2 => edit,
        _ => overview,
      },
    ];
  }

  Widget _buildEmployeeSectionTabs() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const labels = ['پوختە', 'دەسەڵاتەکان', 'دەستکاری'];
    const icons = [
      Icons.space_dashboard_outlined,
      Icons.admin_panel_settings_outlined,
      Icons.edit_outlined,
    ];
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? AppDarkColors.card : const Color(0xFFEFF3F8),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: List.generate(labels.length, (index) {
              final selected = _employeeSection == index;
              return Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (_employeeSection == index) return;
                      _setProfileState(() => _employeeSection = index);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? (isDark ? AppDarkColors.surface : Colors.white)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icons[index],
                            size: 16,
                            color: selected
                                ? AppColors.primary
                                : (isDark ? AppDarkColors.textSecondary : const Color(0xFF98A2B3)),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              labels[index],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                color: selected
                                    ? AppColors.primary
                                    : (isDark ? AppDarkColors.textSecondary : const Color(0xFF667085)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeStatusCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canManage = context.read<AuthProvider>().userRole == 'admin';
    final accent = _isActive ? Colors.green : Colors.red;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? AppDarkColors.card : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE9EDF3),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  _isActive ? Icons.check_circle_outline_rounded : Icons.block_rounded,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isActive ? 'کارمەند چالاکە' : 'کارمەند ناچالاکە',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppDarkColors.textPrimary : const Color(0xFF344054),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isActive ? 'دەتوانێت بچێتە ژوورەوە' : 'ناتوانێت بچێتە ژوورەوە',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppDarkColors.textSecondary : const Color(0xFF98A2B3),
                      ),
                    ),
                  ],
                ),
              ),
              if (canManage)
                Switch.adaptive(
                  value: _isActive,
                  onChanged: (_) => _toggleActive(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeePermissionsCard() {
    final auth = context.read<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canEdit = auth.userRole == 'admin';
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppDarkColors.card : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE9EDF3),
            ),
          ),
          child: Column(
            children: [
              _permissionTile(
                icon: Icons.person_add_alt_1_outlined,
                title: 'زیادکردنی کڕیار',
                value: _canAddCustomers,
                enabled: canEdit,
                onChanged: (v) => _setProfileState(() => _canAddCustomers = v),
              ),
              _permissionTile(
                icon: Icons.account_balance_wallet_outlined,
                title: 'دانانی سنووری قەرز',
                value: _canSetDebtLimit,
                enabled: canEdit,
                onChanged: (v) => _setProfileState(() => _canSetDebtLimit = v),
              ),
              _permissionTile(
                icon: Icons.event_available_outlined,
                title: 'دانانی بەرواری دانەوە',
                value: _canSetDueDate,
                enabled: canEdit,
                onChanged: (v) => _setProfileState(() => _canSetDueDate = v),
              ),
              _permissionTile(
                icon: Icons.edit_note_outlined,
                title: 'دەستکاریکردنی قەرز',
                value: _canEditDebts,
                enabled: canEdit,
                onChanged: (v) => _setProfileState(() => _canEditDebts = v),
              ),
              _permissionTile(
                icon: Icons.notifications_active_outlined,
                title: 'ناردنی ئاگادارکردنەوە',
                value: _canSendNotifications,
                enabled: canEdit,
                onChanged: (v) => _setProfileState(() => _canSendNotifications = v),
                showDivider: false,
              ),
              if (canEdit) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveEmployeePermissions,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('پاشەکەوتکردنی دەسەڵاتەکان'),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _permissionTile({
    required IconData icon,
    required String title,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
    bool showDivider = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppDarkColors.textPrimary : const Color(0xFF344054),
                  ),
                ),
              ),
              Switch.adaptive(
                value: value,
                onChanged: enabled ? onChanged : null,
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF0F2F5),
          ),
      ],
    );
  }

  Future<void> _saveEmployeePermissions() async {
    if (_isSaving) return;
    _setProfileState(() => _isSaving = true);
    try {
      await PBService.updateUser(widget.userId, {
        'can_add_customers': _canAddCustomers,
        'can_set_debt_limit': _canSetDebtLimit,
        'can_set_due_date': _canSetDueDate,
        'can_edit_debts': _canEditDebts,
        'can_send_notifications': _canSendNotifications,
      });
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'دەسەڵاتەکان نوێکرانەوە');
      await _loadData();
    } catch (_) {
      if (mounted) {
        AppHelpers.showSnackBar(context, 'نەتوانرا دەسەڵاتەکان پاشەکەوت بکرێن', isError: true);
      }
    } finally {
      if (mounted) _setProfileState(() => _isSaving = false);
    }
  }

  // ═══════════════════════════════════════════
  // ── Secure Password Management ──
  // ═══════════════════════════════════════════
}