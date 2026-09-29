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

    final permissions = <({IconData icon, String title, bool value, ValueChanged<bool> onChanged})>[
      (icon: Icons.visibility_outlined, title: 'بینینی کڕیارەکان', value: _canViewCustomers, onChanged: (v) => _setProfileState(() => _canViewCustomers = v)),
      (icon: Icons.person_add_alt_1_outlined, title: 'زیادکردنی کڕیار', value: _canAddCustomers, onChanged: (v) => _setProfileState(() => _canAddCustomers = v)),
      (icon: Icons.edit_outlined, title: 'دەستکاریکردنی کڕیار', value: _canEditCustomers, onChanged: (v) => _setProfileState(() => _canEditCustomers = v)),
      (icon: Icons.delete_outline_rounded, title: 'سڕینەوەی کڕیار', value: _canDeleteCustomers, onChanged: (v) => _setProfileState(() => _canDeleteCustomers = v)),
      (icon: Icons.receipt_long_outlined, title: 'بینینی قەرزەکان', value: _canViewDebts, onChanged: (v) => _setProfileState(() => _canViewDebts = v)),
      (icon: Icons.add_card_outlined, title: 'زیادکردنی قەرز', value: _canAddDebts, onChanged: (v) => _setProfileState(() => _canAddDebts = v)),
      (icon: Icons.edit_note_outlined, title: 'دەستکاریکردنی قەرز', value: _canEditDebts, onChanged: (v) => _setProfileState(() => _canEditDebts = v)),
      (icon: Icons.delete_sweep_outlined, title: 'سڕینەوەی قەرز', value: _canDeleteDebts, onChanged: (v) => _setProfileState(() => _canDeleteDebts = v)),
      (icon: Icons.payments_outlined, title: 'تۆمارکردنی پارەدانەوە', value: _canRecordPayments, onChanged: (v) => _setProfileState(() => _canRecordPayments = v)),
      (icon: Icons.account_balance_wallet_outlined, title: 'دانانی سنووری قەرز', value: _canSetDebtLimit, onChanged: (v) => _setProfileState(() => _canSetDebtLimit = v)),
      (icon: Icons.event_available_outlined, title: 'دانانی بەرواری دانەوە', value: _canSetDueDate, onChanged: (v) => _setProfileState(() => _canSetDueDate = v)),
      (icon: Icons.analytics_outlined, title: 'بینینی ڕاپۆرتی دارایی', value: _canViewFinancialReports, onChanged: (v) => _setProfileState(() => _canViewFinancialReports = v)),
      (icon: Icons.file_upload_outlined, title: 'هەناردەکردنی داتا', value: _canExportData, onChanged: (v) => _setProfileState(() => _canExportData = v)),
      (icon: Icons.file_download_outlined, title: 'هاوردەکردنی داتا', value: _canImportData, onChanged: (v) => _setProfileState(() => _canImportData = v)),
      (icon: Icons.notifications_active_outlined, title: 'ناردنی ئاگادارکردنەوە', value: _canSendNotifications, onChanged: (v) => _setProfileState(() => _canSendNotifications = v)),
      (icon: Icons.undo_rounded, title: 'گەڕاندنەوەی پارەدانەوە', value: _canRefundPayments, onChanged: (v) => _setProfileState(() => _canRefundPayments = v)),
      (icon: Icons.restore_from_trash_outlined, title: 'گەڕاندنەوەی قەرزی سڕاوە', value: _canRestoreDebts, onChanged: (v) => _setProfileState(() => _canRestoreDebts = v)),
      (icon: Icons.receipt_outlined, title: 'بەڕێوەبردنی پسووڵە', value: _canManageReceipts, onChanged: (v) => _setProfileState(() => _canManageReceipts = v)),
      (icon: Icons.notifications_outlined, title: 'بەڕێوەبردنی ئاگادارکردنەوە', value: _canManageNotifications, onChanged: (v) => _setProfileState(() => _canManageNotifications = v)),
      (icon: Icons.how_to_reg_outlined, title: 'پەسەندکردنی کڕیار', value: _canApproveCustomers, onChanged: (v) => _setProfileState(() => _canApproveCustomers = v)),
      (icon: Icons.badge_outlined, title: 'بەڕێوەبردنی کارمەندان', value: _canManageEmployees, onChanged: (v) => _setProfileState(() => _canManageEmployees = v)),
      (icon: Icons.fact_check_outlined, title: 'بینینی Audit Log', value: _canViewAuditLog, onChanged: (v) => _setProfileState(() => _canViewAuditLog = v)),
      (icon: Icons.backup_outlined, title: 'بەڕێوەبردنی Backup', value: _canManageBackup, onChanged: (v) => _setProfileState(() => _canManageBackup = v)),
      (icon: Icons.sync_rounded, title: 'بەڕێوەبردنی Daftar Sync', value: _canManageDaftarSync, onChanged: (v) => _setProfileState(() => _canManageDaftarSync = v)),
      (icon: Icons.workspace_premium_outlined, title: 'بەڕێوەبردنی بەشداری', value: _canManageSubscription, onChanged: (v) => _setProfileState(() => _canManageSubscription = v)),
      (icon: Icons.dashboard_outlined, title: 'بینینی داشبۆرد', value: _canViewDashboard, onChanged: (v) => _setProfileState(() => _canViewDashboard = v)),
      (icon: Icons.history_rounded, title: 'بینینی چالاکییە نوێکان', value: _canViewRecentActivity, onChanged: (v) => _setProfileState(() => _canViewRecentActivity = v)),
      (icon: Icons.swap_horiz_rounded, title: 'بینینی مێژووی مامەڵەکان', value: _canViewTransactions, onChanged: (v) => _setProfileState(() => _canViewTransactions = v)),
      (icon: Icons.edit_note_rounded, title: 'دەستکاریکردنی پارەدانەوە', value: _canEditPayments, onChanged: (v) => _setProfileState(() => _canEditPayments = v)),
      (icon: Icons.delete_forever_outlined, title: 'سڕینەوەی پارەدانەوە', value: _canDeletePayments, onChanged: (v) => _setProfileState(() => _canDeletePayments = v)),
      (icon: Icons.description_outlined, title: 'دروستکردنی کەشف و بەڵگەنامە', value: _canCreateStatements, onChanged: (v) => _setProfileState(() => _canCreateStatements = v)),
      (icon: Icons.link_rounded, title: 'بەڕێوەبردنی لینکی کڕیار', value: _canManageCustomerLinks, onChanged: (v) => _setProfileState(() => _canManageCustomerLinks = v)),
      (icon: Icons.push_pin_outlined, title: 'Pin کردنی کڕیار', value: _canPinCustomers, onChanged: (v) => _setProfileState(() => _canPinCustomers = v)),
      (icon: Icons.workspace_premium_outlined, title: 'بەڕێوەبردنی VIP', value: _canManageVipCustomers, onChanged: (v) => _setProfileState(() => _canManageVipCustomers = v)),
      (icon: Icons.merge_type_rounded, title: 'یەکخستنی ناسنامەی دووبارە', value: _canMergeCustomerIdentities, onChanged: (v) => _setProfileState(() => _canMergeCustomerIdentities = v)),
      (icon: Icons.currency_exchange_rounded, title: 'بینینی نرخی بازاڕ', value: _canViewMarketRates, onChanged: (v) => _setProfileState(() => _canViewMarketRates = v)),
      (icon: Icons.auto_graph_rounded, title: 'بینینی ناوەندی زیرەکی', value: _canViewIntelligence, onChanged: (v) => _setProfileState(() => _canViewIntelligence = v)),
      (icon: Icons.event_repeat_rounded, title: 'بەڕێوەبردنی بەدواداچوونی قەرز', value: _canManageCollections, onChanged: (v) => _setProfileState(() => _canManageCollections = v)),
      (icon: Icons.inventory_2_outlined, title: 'بینینی کاڵای بەسەرچوو', value: _canViewExpiry, onChanged: (v) => _setProfileState(() => _canViewExpiry = v)),
      (icon: Icons.inventory_2_rounded, title: 'بەڕێوەبردنی کاڵای بەسەرچوو', value: _canManageExpiry, onChanged: (v) => _setProfileState(() => _canManageExpiry = v)),
      (icon: Icons.settings_outlined, title: 'بەڕێوەبردنی ڕێکخستنەکان', value: _canManageSettings, onChanged: (v) => _setProfileState(() => _canManageSettings = v)),
    ];

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
              ...List.generate(permissions.length, (index) {
                final item = permissions[index];
                return _permissionTile(
                  icon: item.icon,
                  title: item.title,
                  value: item.value,
                  enabled: canEdit,
                  onChanged: item.onChanged,
                  showDivider: index != permissions.length - 1,
                );
              }),
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
        'can_view_customers': _canViewCustomers,
        'can_edit_customers': _canEditCustomers,
        'can_delete_customers': _canDeleteCustomers,
        'can_view_debts': _canViewDebts,
        'can_add_debts': _canAddDebts,
        'can_delete_debts': _canDeleteDebts,
        'can_record_payments': _canRecordPayments,
        'can_view_financial_reports': _canViewFinancialReports,
        'can_export_data': _canExportData,
        'can_import_data': _canImportData,
        'can_refund_payments': _canRefundPayments,
        'can_restore_debts': _canRestoreDebts,
        'can_manage_receipts': _canManageReceipts,
        'can_manage_notifications': _canManageNotifications,
        'can_approve_customers': _canApproveCustomers,
        'can_manage_employees': _canManageEmployees,
        'can_view_audit_log': _canViewAuditLog,
        'can_manage_backup': _canManageBackup,
        'can_manage_daftar_sync': _canManageDaftarSync,
        'can_manage_subscription': _canManageSubscription,
        'can_view_dashboard': _canViewDashboard,
        'can_view_recent_activity': _canViewRecentActivity,
        'can_view_transactions': _canViewTransactions,
        'can_edit_payments': _canEditPayments,
        'can_delete_payments': _canDeletePayments,
        'can_create_statements': _canCreateStatements,
        'can_manage_customer_links': _canManageCustomerLinks,
        'can_pin_customers': _canPinCustomers,
        'can_manage_vip_customers': _canManageVipCustomers,
        'can_merge_customer_identities': _canMergeCustomerIdentities,
        'can_view_market_rates': _canViewMarketRates,
        'can_view_intelligence': _canViewIntelligence,
        'can_manage_collections': _canManageCollections,
        'can_view_expiry': _canViewExpiry,
        'can_manage_expiry': _canManageExpiry,
        'can_manage_settings': _canManageSettings,
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