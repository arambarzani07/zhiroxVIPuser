from pathlib import Path
import re

list_path = Path('lib/screens/shared/user_list_screen.dart')
profile_path = Path('lib/screens/shared/user_profile_screen.dart')

# ── Employee / customer list cleanup ─────────────────────────────────────────
text = list_path.read_text()
text = text.replace("import 'dart:convert';\n", '')
text = text.replace("import 'package:shared_preferences/shared_preferences.dart';\n", '')
text = text.replace(
    "  bool _isLoading = true;\n",
    "  bool _isLoading = true;\n  String? _loadError;\n",
    1,
)

load_pattern = re.compile(
    r"  Future<void> _loadUsers\(\{String\? search\}\) async \{.*?\n  \}\n\n  /// Load all customer balances",
    re.S,
)
load_replacement = '''  Future<void> _loadUsers({String? search}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final adminId = _adminId;
      final users = await PBService.getUsers(
        role: widget.role,
        search: search,
        adminId: adminId.isNotEmpty ? adminId : null,
      );
      if (!mounted) return;
      setState(() {
        _users = users;
        _isLoading = false;
      });

      if (widget.role == 'customer' && users.isNotEmpty) {
        unawaited(_loadBalancesInBackground());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _users = [];
        _isLoading = false;
        _loadError = 'نەتوانرا لیستەکە باربکرێت. پەیوەندی ئینتەرنێت بپشکنە.';
      });
    }
  }

  /// Load all customer balances'''
text, count = load_pattern.subn(load_replacement, text, count=1)
if count != 1:
    raise SystemExit('user list load block not found')

# One visual language for employee/customer lists.
text = re.sub(
    r"colors: _isEmployee\n\s*\? \[const Color\(0xFF4A6CF7\), const Color\(0xFF6B8CFF\)\]\n\s*: \[\n\s*AppColors\.primary,\n\s*AppColors\.primary\.withOpacity\(0\.85\),\n\s*\],",
    "colors: [AppColors.primary, AppColors.primary.withOpacity(0.88)],",
    text,
    count=1,
)
text = text.replace("bottomLeft: Radius.circular(28),\n                  bottomRight: Radius.circular(28),", "bottomLeft: Radius.circular(20),\n                  bottomRight: Radius.circular(20),", 1)
text = text.replace("padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),", "padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),", 1)
text = text.replace("color: Colors.white,\n                            size: 26,", "color: Colors.white,\n                            size: 22,", 1)
text = text.replace("fontSize: 24,\n                              fontWeight: FontWeight.bold,", "fontSize: 20,\n                              fontWeight: FontWeight.w800,", 1)
text = text.replace("const SizedBox(height: 18),\n\n                      // Search Bar", "const SizedBox(height: 12),\n\n                      // Search Bar", 1)
text = text.replace(
    "final accentColor = _isEmployee\n        ? const Color(0xFF4A6CF7)\n        : AppColors.primary;",
    "final accentColor = AppColors.primary;",
    1,
)

# Search icon should not change color by role.
text = text.replace(
    "color: _isEmployee\n                                  ? const Color(0xFF4A6CF7)\n                                  : AppColors.primary,",
    "color: AppColors.primary,",
    1,
)

# Show useful employee identity metadata instead of an otherwise empty second line.
needle = """                      if (!_isEmployee) ...[
                        const SizedBox(height: 5),"""
insert = """                      if (_isEmployee) ...[
                        const SizedBox(height: 4),
                        Text(
                          user.getStringValue('phone').isEmpty
                              ? 'ژمارە مۆبایل نەدراوە'
                              : user.getStringValue('phone'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            color: isDark
                                ? AppDarkColors.textSecondary
                                : const Color(0xFF98A2B3),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                      if (!_isEmployee) ...[
                        const SizedBox(height: 5),"""
if needle not in text:
    raise SystemExit('employee subtitle anchor not found')
text = text.replace(needle, insert, 1)

# Add online-only error state.
old_state = """          _isLoading
              ? const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              : _users.isEmpty
              ? SliverFillRemaining(child: _buildEmptyState())"""
new_state = """          _isLoading
              ? const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              : _loadError != null
              ? SliverFillRemaining(child: _buildLoadErrorState())
              : _users.isEmpty
              ? SliverFillRemaining(child: _buildEmptyState())"""
if old_state not in text:
    raise SystemExit('list state anchor not found')
text = text.replace(old_state, new_state, 1)

empty_anchor = "  Widget _buildEmptyState() {"
error_widget = '''  Widget _buildLoadErrorState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 40, color: Colors.orange[400]),
            const SizedBox(height: 12),
            Text(
              _loadError ?? 'نەتوانرا زانیاری باربکرێت',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: isDark ? AppDarkColors.textSecondary : const Color(0xFF667085),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => _loadUsers(search: _searchController.text.trim()),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('دووبارە هەوڵ بدە'),
            ),
          ],
        ),
      ),
    );
  }

'''
if empty_anchor not in text:
    raise SystemExit('empty state anchor not found')
text = text.replace(empty_anchor, error_widget + empty_anchor, 1)
list_path.write_text(text)

# ── Employee profile information architecture ────────────────────────────────
text = profile_path.read_text()
text = text.replace("import 'dart:convert';\n", '')
text = text.replace("import 'package:shared_preferences/shared_preferences.dart';\n", '')
text = text.replace(
    "  int _customerSection = 0;\n",
    "  int _customerSection = 0;\n  int _employeeSection = 0;\n  String? _loadError;\n",
    1,
)

load_profile_pattern = re.compile(
    r"  Future<void> _loadData\(\) async \{.*?\n  \}\n\n  Future<void> _toggleActive",
    re.S,
)
load_profile_replacement = '''  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final user = await PBService.getUser(widget.userId);
      if (!mounted) return;
      _user = user;
      _nameController.text = user.getStringValue('name');
      _phoneController.text = user.getStringValue('phone');
      _passwordController.text = user.getStringValue('password_text');

      if (_isCustomer) {
        _debts = await PBService.getDebts(customerId: widget.userId);
        _payments = await PBService.getPayments(customerId: widget.userId);
      } else {
        _debts = [];
        _payments = [];
      }

      if (_isEmployee) {
        _employeeStats = await PBService.getEmployeeStats(widget.userId);
        _canAddCustomers = user.getBoolValue('can_add_customers');
        _canSetDebtLimit = user.getBoolValue('can_set_debt_limit');
        _canSetDueDate = user.getBoolValue('can_set_due_date');
        _canEditDebts = user.getBoolValue('can_edit_debts');
        _canSendNotifications = user.getBoolValue('can_send_notifications');
      } else {
        _employeeStats = {};
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'نەتوانرا زانیارییەکانی پروفایل باربکرێن. پەیوەندی ئینتەرنێت بپشکنە.';
      });
    }
  }

  Future<void> _toggleActive'''
text, count = load_profile_pattern.subn(load_profile_replacement, text, count=1)
if count != 1:
    raise SystemExit('profile load block not found')

# Permission changes are now saved from their own section.
text = re.sub(
    r"\n      // Update permissions if admin editing employee\n      if \(_isEmployee && context\.read<AuthProvider>\(\)\.userRole == 'admin'\) \{.*?\n      \}",
    "",
    text,
    count=1,
    flags=re.S,
)
text = text.replace("    setState(() => _isSaving = false);\n  }", "    if (mounted) setState(() => _isSaving = false);\n  }", 1)

# Replace old employee body with tabbed information architecture.
employee_pattern = re.compile(
    r"  List<Widget> _buildEmployeeBody\(\) \{.*?\n  \}\n\n  // ═+\n  // ── Shared Profile Editor ──",
    re.S,
)
employee_replacement = '''  List<Widget> _buildEmployeeBody() {
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
                      setState(() => _employeeSection = index);
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
                onChanged: (v) => setState(() => _canAddCustomers = v),
              ),
              _permissionTile(
                icon: Icons.account_balance_wallet_outlined,
                title: 'دانانی سنوری قەرز',
                value: _canSetDebtLimit,
                enabled: canEdit,
                onChanged: (v) => setState(() => _canSetDebtLimit = v),
              ),
              _permissionTile(
                icon: Icons.event_available_outlined,
                title: 'دانانی بەرواری دانەوە',
                value: _canSetDueDate,
                enabled: canEdit,
                onChanged: (v) => setState(() => _canSetDueDate = v),
              ),
              _permissionTile(
                icon: Icons.edit_note_outlined,
                title: 'دەستکاریکردنی قەرز',
                value: _canEditDebts,
                enabled: canEdit,
                onChanged: (v) => setState(() => _canEditDebts = v),
              ),
              _permissionTile(
                icon: Icons.notifications_active_outlined,
                title: 'ناردنی ئاگادارکردنەوە',
                value: _canSendNotifications,
                enabled: canEdit,
                onChanged: (v) => setState(() => _canSendNotifications = v),
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
    setState(() => _isSaving = true);
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
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ═══════════════════════════════════════════
  // ── Shared Profile Editor ──'''
text, count = employee_pattern.subn(employee_replacement, text, count=1)
if count != 1:
    raise SystemExit('employee body block not found')

# Permissions no longer belong inside the edit form.
permissions_pattern = re.compile(
    r"\n                // Permissions \(Only Admin viewing Employee\).*?\n                \],\n                SizedBox\(",
    re.S,
)
text, count = permissions_pattern.subn("\n                SizedBox(", text, count=1)
if count != 1:
    raise SystemExit('editor permissions block not found')

profile_path.write_text(text)
