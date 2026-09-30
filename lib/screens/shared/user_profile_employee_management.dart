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
                  AppHelpers.formatCurrency(
                    _employeeStats['totalDebtsCreated'] ?? 0,
                  ),
                  Colors.orange,
                ),
                const SizedBox(width: 10),
                _buildStatChip(
                  Icons.payments_outlined,
                  'پارەی وەرگیراو',
                  AppHelpers.formatCurrency(
                    _employeeStats['totalPaymentsCollected'] ?? 0,
                  ),
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
                                : (isDark
                                    ? AppDarkColors.textSecondary
                                    : const Color(0xFF98A2B3)),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              labels[index],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected
                                    ? AppColors.primary
                                    : (isDark
                                        ? AppDarkColors.textSecondary
                                        : const Color(0xFF667085)),
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
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFE9EDF3),
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
                  _isActive
                      ? Icons.check_circle_outline_rounded
                      : Icons.block_rounded,
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
                        color: isDark
                            ? AppDarkColors.textPrimary
                            : const Color(0xFF344054),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isActive
                          ? 'دەتوانێت بچێتە ژوورەوە'
                          : 'ناتوانێت بچێتە ژوورەوە',
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
    final user = _user;
    if (user == null) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: _EmployeePermissionsEditor(
          user: user,
          canEdit: context.read<AuthProvider>().userRole == 'admin',
          onSaved: _loadData,
        ),
      ),
    );
  }
}

class _EmployeePermissionSpec {
  const _EmployeePermissionSpec({
    required this.key,
    required this.title,
    required this.group,
    required this.icon,
  });

  final String key;
  final String title;
  final String group;
  final IconData icon;
}

final _employeePermissionSpecs = <_EmployeePermissionSpec>[
  _EmployeePermissionSpec(key: 'can_view_customers', title: 'بینینی کڕیارەکان', group: 'کڕیار', icon: Icons.visibility_outlined),
  _EmployeePermissionSpec(key: 'can_add_customers', title: 'زیادکردنی کڕیار', group: 'کڕیار', icon: Icons.person_add_alt_1_outlined),
  _EmployeePermissionSpec(key: 'can_edit_customers', title: 'دەستکاریکردنی کڕیار', group: 'کڕیار', icon: Icons.edit_outlined),
  _EmployeePermissionSpec(key: 'can_delete_customers', title: 'سڕینەوەی کڕیار', group: 'کڕیار', icon: Icons.delete_outline_rounded),
  _EmployeePermissionSpec(key: 'can_approve_customers', title: 'پەسەندکردنی کڕیار', group: 'کڕیار', icon: Icons.how_to_reg_outlined),
  _EmployeePermissionSpec(key: 'can_manage_customer_links', title: 'بەڕێوەبردنی لینکی کڕیار', group: 'کڕیار', icon: Icons.link_rounded),
  _EmployeePermissionSpec(key: 'can_pin_customers', title: 'Pin کردنی کڕیار', group: 'کڕیار', icon: Icons.push_pin_outlined),
  _EmployeePermissionSpec(key: 'can_manage_vip_customers', title: 'بەڕێوەبردنی VIP', group: 'کڕیار', icon: Icons.workspace_premium_outlined),
  _EmployeePermissionSpec(key: 'can_merge_customer_identities', title: 'یەکخستنی ناسنامەی دووبارە', group: 'کڕیار', icon: Icons.merge_type_rounded),
  _EmployeePermissionSpec(key: 'can_view_customer_phone', title: 'بینینی ژمارەی مۆبایلی کڕیار', group: 'کڕیار', icon: Icons.phone_outlined),
  _EmployeePermissionSpec(key: 'can_view_customer_notes', title: 'بینینی تێبینییەکانی کڕیار', group: 'کڕیار', icon: Icons.sticky_note_2_outlined),
  _EmployeePermissionSpec(key: 'can_edit_customer_notes', title: 'دەستکاریکردنی تێبینییەکانی کڕیار', group: 'کڕیار', icon: Icons.edit_note_outlined),
  _EmployeePermissionSpec(key: 'can_view_customer_balances', title: 'بینینی باڵانسی کڕیار', group: 'کڕیار', icon: Icons.account_balance_wallet_outlined),

  _EmployeePermissionSpec(key: 'can_view_debts', title: 'بینینی قەرزەکان', group: 'قەرز و پارە', icon: Icons.receipt_long_outlined),
  _EmployeePermissionSpec(key: 'can_add_debts', title: 'زیادکردنی قەرز', group: 'قەرز و پارە', icon: Icons.add_card_outlined),
  _EmployeePermissionSpec(key: 'can_edit_debts', title: 'دەستکاریکردنی قەرز', group: 'قەرز و پارە', icon: Icons.edit_note_outlined),
  _EmployeePermissionSpec(key: 'can_delete_debts', title: 'سڕینەوەی قەرز', group: 'قەرز و پارە', icon: Icons.delete_sweep_outlined),
  _EmployeePermissionSpec(key: 'can_record_payments', title: 'تۆمارکردنی پارەدانەوە', group: 'قەرز و پارە', icon: Icons.payments_outlined),
  _EmployeePermissionSpec(key: 'can_set_debt_limit', title: 'دانانی سنووری قەرز', group: 'قەرز و پارە', icon: Icons.account_balance_wallet_outlined),
  _EmployeePermissionSpec(key: 'can_set_due_date', title: 'دانانی بەرواری دانەوە', group: 'قەرز و پارە', icon: Icons.event_available_outlined),
  _EmployeePermissionSpec(key: 'can_refund_payments', title: 'گەڕاندنەوەی پارەدانەوە', group: 'قەرز و پارە', icon: Icons.undo_rounded),
  _EmployeePermissionSpec(key: 'can_restore_debts', title: 'گەڕاندنەوەی قەرزی سڕاوە', group: 'قەرز و پارە', icon: Icons.restore_from_trash_outlined),
  _EmployeePermissionSpec(key: 'can_view_transactions', title: 'بینینی مێژووی مامەڵەکان', group: 'قەرز و پارە', icon: Icons.swap_horiz_rounded),
  _EmployeePermissionSpec(key: 'can_edit_payments', title: 'دەستکاریکردنی پارەدانەوە', group: 'قەرز و پارە', icon: Icons.edit_note_rounded),
  _EmployeePermissionSpec(key: 'can_delete_payments', title: 'سڕینەوەی پارەدانەوە', group: 'قەرز و پارە', icon: Icons.delete_forever_outlined),
  _EmployeePermissionSpec(key: 'can_view_payment_history', title: 'بینینی مێژووی پارەدانەوە', group: 'قەرز و پارە', icon: Icons.history_outlined),
  _EmployeePermissionSpec(key: 'can_manage_collections', title: 'بەڕێوەبردنی بەدواداچوونی قەرز', group: 'قەرز و پارە', icon: Icons.event_repeat_rounded),

  _EmployeePermissionSpec(key: 'can_view_financial_reports', title: 'بینینی ڕاپۆرتی دارایی', group: 'پسووڵە و ڕاپۆرت', icon: Icons.analytics_outlined),
  _EmployeePermissionSpec(key: 'can_export_data', title: 'هەناردەکردنی داتا', group: 'پسووڵە و ڕاپۆرت', icon: Icons.file_upload_outlined),
  _EmployeePermissionSpec(key: 'can_import_data', title: 'هاوردەکردنی داتا', group: 'پسووڵە و ڕاپۆرت', icon: Icons.file_download_outlined),
  _EmployeePermissionSpec(key: 'can_manage_receipts', title: 'بەڕێوەبردنی پسووڵە', group: 'پسووڵە و ڕاپۆرت', icon: Icons.receipt_outlined),
  _EmployeePermissionSpec(key: 'can_create_statements', title: 'دروستکردنی کەشف و بەڵگەنامە', group: 'پسووڵە و ڕاپۆرت', icon: Icons.description_outlined),
  _EmployeePermissionSpec(key: 'can_create_receipts', title: 'دروستکردنی پسووڵە', group: 'پسووڵە و ڕاپۆرت', icon: Icons.note_add_outlined),
  _EmployeePermissionSpec(key: 'can_edit_receipts', title: 'دەستکاریکردنی پسووڵە', group: 'پسووڵە و ڕاپۆرت', icon: Icons.edit_document),
  _EmployeePermissionSpec(key: 'can_delete_receipts', title: 'سڕینەوەی پسووڵە', group: 'پسووڵە و ڕاپۆرت', icon: Icons.delete_outline_rounded),
  _EmployeePermissionSpec(key: 'can_export_receipts', title: 'هەناردەکردنی پسووڵە', group: 'پسووڵە و ڕاپۆرت', icon: Icons.ios_share_outlined),
  _EmployeePermissionSpec(key: 'can_view_report_summary', title: 'بینینی پوختەی ڕاپۆرت', group: 'پسووڵە و ڕاپۆرت', icon: Icons.summarize_outlined),
  _EmployeePermissionSpec(key: 'can_export_reports', title: 'هەناردەکردنی ڕاپۆرت', group: 'پسووڵە و ڕاپۆرت', icon: Icons.download_outlined),

  _EmployeePermissionSpec(key: 'can_send_notifications', title: 'ناردنی ئاگادارکردنەوە', group: 'کارمەند و ئاگادارکردنەوە', icon: Icons.notifications_active_outlined),
  _EmployeePermissionSpec(key: 'can_manage_notifications', title: 'بەڕێوەبردنی ئاگادارکردنەوە', group: 'کارمەند و ئاگادارکردنەوە', icon: Icons.notifications_outlined),
  _EmployeePermissionSpec(key: 'can_manage_notification_templates', title: 'بەڕێوەبردنی قاڵبی ئاگادارکردنەوە', group: 'کارمەند و ئاگادارکردنەوە', icon: Icons.dynamic_feed_outlined),
  _EmployeePermissionSpec(key: 'can_send_bulk_notifications', title: 'ناردنی ئاگادارکردنەوەی بەکۆمەڵ', group: 'کارمەند و ئاگادارکردنەوە', icon: Icons.campaign_outlined),
  _EmployeePermissionSpec(key: 'can_manage_employees', title: 'بەڕێوەبردنی کارمەندان', group: 'کارمەند و ئاگادارکردنەوە', icon: Icons.badge_outlined),
  _EmployeePermissionSpec(key: 'can_view_audit_log', title: 'بینینی Audit Log', group: 'کارمەند و ئاگادارکردنەوە', icon: Icons.fact_check_outlined),

  _EmployeePermissionSpec(key: 'can_manage_backup', title: 'بەڕێوەبردنی Backup', group: 'سیستەم و ئاسایش', icon: Icons.backup_outlined),
  _EmployeePermissionSpec(key: 'can_run_manual_backup', title: 'Backup ـی دەستی', group: 'سیستەم و ئاسایش', icon: Icons.cloud_upload_outlined),
  _EmployeePermissionSpec(key: 'can_restore_backup', title: 'گەڕاندنەوەی Backup', group: 'سیستەم و ئاسایش', icon: Icons.restore_page_outlined),
  _EmployeePermissionSpec(key: 'can_manage_daftar_sync', title: 'بەڕێوەبردنی Daftar Sync', group: 'سیستەم و ئاسایش', icon: Icons.sync_rounded),
  _EmployeePermissionSpec(key: 'can_view_sync_logs', title: 'بینینی Sync Logs', group: 'سیستەم و ئاسایش', icon: Icons.list_alt_outlined),
  _EmployeePermissionSpec(key: 'can_retry_failed_sync', title: 'دووبارە هەوڵدانی Sync شکستخواردوو', group: 'سیستەم و ئاسایش', icon: Icons.sync_problem_outlined),
  _EmployeePermissionSpec(key: 'can_manage_subscription', title: 'بەڕێوەبردنی بەشداری', group: 'سیستەم و ئاسایش', icon: Icons.workspace_premium_outlined),
  _EmployeePermissionSpec(key: 'can_view_dashboard', title: 'بینینی داشبۆرد', group: 'سیستەم و ئاسایش', icon: Icons.dashboard_outlined),
  _EmployeePermissionSpec(key: 'can_view_recent_activity', title: 'بینینی چالاکییە نوێکان', group: 'سیستەم و ئاسایش', icon: Icons.history_rounded),
  _EmployeePermissionSpec(key: 'can_view_market_rates', title: 'بینینی نرخی بازاڕ', group: 'سیستەم و ئاسایش', icon: Icons.currency_exchange_rounded),
  _EmployeePermissionSpec(key: 'can_manage_market_rate_refresh', title: 'نوێکردنەوەی نرخی بازاڕ', group: 'سیستەم و ئاسایش', icon: Icons.refresh_rounded),
  _EmployeePermissionSpec(key: 'can_view_intelligence', title: 'بینینی ناوەندی زیرەکی', group: 'سیستەم و ئاسایش', icon: Icons.auto_graph_rounded),
  _EmployeePermissionSpec(key: 'can_view_expiry', title: 'بینینی کاڵای بەسەرچوو', group: 'سیستەم و ئاسایش', icon: Icons.inventory_2_outlined),
  _EmployeePermissionSpec(key: 'can_manage_expiry', title: 'بەڕێوەبردنی کاڵای بەسەرچوو', group: 'سیستەم و ئاسایش', icon: Icons.inventory_2_rounded),
  _EmployeePermissionSpec(key: 'can_manage_settings', title: 'بەڕێوەبردنی ڕێکخستنەکان', group: 'سیستەم و ئاسایش', icon: Icons.settings_outlined),
  _EmployeePermissionSpec(key: 'can_manage_security_settings', title: 'بەڕێوەبردنی ڕێکخستنەکانی ئاسایش', group: 'سیستەم و ئاسایش', icon: Icons.security_outlined),

  ...additionalEmployeePermissionSpecs.map(
    (spec) => _EmployeePermissionSpec(
      key: spec.key,
      title: spec.title,
      group: spec.group,
      icon: spec.icon,
    ),
  ),

];

class _EmployeePermissionsEditor extends StatefulWidget {
  const _EmployeePermissionsEditor({
    required this.user,
    required this.canEdit,
    required this.onSaved,
  });

  final RecordModel user;
  final bool canEdit;
  final Future<void> Function() onSaved;

  @override
  State<_EmployeePermissionsEditor> createState() =>
      _EmployeePermissionsEditorState();
}

class _EmployeePermissionsEditorState
    extends State<_EmployeePermissionsEditor> {
  late Map<String, bool> _draft;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _resetDraft();
  }

  @override
  void didUpdateWidget(covariant _EmployeePermissionsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user != widget.user && !_dirty && !_saving) {
      _resetDraft();
    }
  }

  void _resetDraft() {
    _draft = {
      for (final spec in _employeePermissionSpecs)
        spec.key: widget.user.getBoolValue(spec.key),
    };
    _dirty = false;
  }

  Future<void> _save() async {
    if (_saving || !_dirty || !widget.canEdit) return;
    setState(() => _saving = true);
    try {
      await PBService.updateUser(widget.user.id, Map<String, dynamic>.from(_draft));
      if (!mounted) return;
      setState(() => _dirty = false);
      AppHelpers.showSnackBar(context, 'هەموو ١٨٠ دەسەڵاتەکە نوێکرانەوە');
      await widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا دەسەڵاتەکان پاشەکەوت بکرێن',
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabledCount = _draft.values.where((value) => value).length;
    final groups = <String, List<_EmployeePermissionSpec>>{};
    for (final spec in _employeePermissionSpecs) {
      groups.putIfAbsent(spec.group, () => []).add(spec);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE9EDF3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'دەسەڵاتەکانی کارمەند',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppDarkColors.textPrimary
                            : const Color(0xFF344054),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$enabledCount لە ١٨٠ دەسەڵات چالاکە',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? AppDarkColors.textSecondary
                            : const Color(0xFF667085),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.canEdit)
                PopupMenuButton<String>(
                  tooltip: 'کرداری خێرا',
                  onSelected: (value) {
                    setState(() {
                      final newValue = value == 'all';
                      for (final spec in _employeePermissionSpecs) {
                        _draft[spec.key] = newValue;
                      }
                      _dirty = true;
                    });
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'all', child: Text('هەمووی چالاک بکە')),
                    PopupMenuItem(value: 'none', child: Text('هەمووی ناچالاک بکە')),
                  ],
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ...groups.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  ...List.generate(entry.value.length, (index) {
                    final spec = entry.value[index];
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
                                child: Icon(
                                  spec.icon,
                                  size: 17,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  spec.title,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? AppDarkColors.textPrimary
                                        : const Color(0xFF344054),
                                  ),
                                ),
                              ),
                              Switch.adaptive(
                                value: _draft[spec.key] ?? false,
                                onChanged: widget.canEdit && !_saving
                                    ? (value) {
                                        setState(() {
                                          _draft[spec.key] = value;
                                          _dirty = true;
                                        });
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        if (index != entry.value.length - 1)
                          Divider(
                            height: 1,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : const Color(0xFFF0F2F5),
                          ),
                      ],
                    );
                  }),
                ],
              ),
            );
          }),
          if (widget.canEdit)
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _saving || !_dirty ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  _saving
                      ? 'پاشەکەوت دەکرێت...'
                      : 'پاشەکەوتکردنی ١٨٠ دەسەڵات',
                ),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
