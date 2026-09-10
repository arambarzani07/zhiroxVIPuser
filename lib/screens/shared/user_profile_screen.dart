import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/shared/add_debt_screen.dart';

import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/services/pdf_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:zhirox/providers/theme_provider.dart';
import 'package:zhirox/services/connectivity_service.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;

  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _ProfileTimelineItem {
  final String kind;
  final RecordModel record;
  final RecordModel? relatedDebt;
  final DateTime date;

  const _ProfileTimelineItem({
    required this.kind,
    required this.record,
    required this.date,
    this.relatedDebt,
  });

  bool get isPayment => kind == 'payment';
}


class _UserProfileScreenState extends State<UserProfileScreen> {
  RecordModel? _user;
  List<RecordModel> _debts = [];
  List<RecordModel> _payments = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _loadInFlight = false;
  int _customerSection = 0;
  int _employeeSection = 0;
  String? _loadError;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  Map<String, double> _employeeStats = {};
  final _debtLimitController = TextEditingController();

  // Employee Permissions (Editable by Admin)
  bool _canAddCustomers = false;
  bool _canSetDebtLimit = false;
  bool _canSetDueDate = false;
  bool _canEditDebts = false;
  bool _canSendNotifications = false;
  StreamSubscription<bool>? _connectivitySub;

  bool get _isCustomer => _user?.getStringValue('role') == 'customer';
  bool get _isEmployee => _user?.getStringValue('role') == 'employee';
  bool get _isActive => _user?.getBoolValue('active') ?? true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _connectivitySub = ConnectivityService.instance.statusStream.listen((online) {
      if (online && mounted) _loadData();
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _debtLimitController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted || _loadInFlight) return;
    _loadInFlight = true;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final user = await PBService.getUser(widget.userId);
      final role = user.getStringValue('role');

      List<RecordModel> debts = [];
      List<RecordModel> payments = [];
      Map<String, double> employeeStats = {};

      if (role == 'customer') {
        final customerData = await Future.wait<List<RecordModel>>([
          PBService.getDebts(customerId: widget.userId),
          PBService.getPayments(customerId: widget.userId),
        ]);
        debts = customerData[0];
        payments = customerData[1];
      } else if (role == 'employee') {
        employeeStats = await PBService.getEmployeeStats(widget.userId);
      }

      if (!mounted) return;
      setState(() {
        _user = user;
        _debts = debts;
        _payments = payments;
        _employeeStats = employeeStats;
        _nameController.text = user.getStringValue('name');
        _phoneController.text = user.getStringValue('phone');

        if (role == 'employee') {
          _canAddCustomers = user.getBoolValue('can_add_customers');
          _canSetDebtLimit = user.getBoolValue('can_set_debt_limit');
          _canSetDueDate = user.getBoolValue('can_set_due_date');
          _canEditDebts = user.getBoolValue('can_edit_debts');
          _canSendNotifications = user.getBoolValue('can_send_notifications');
        }

        _isLoading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _user = null;
        _debts = [];
        _payments = [];
        _employeeStats = {};
        _isLoading = false;
        _loadError =
            'نەتوانرا زانیارییەکانی پروفایل باربکرێن. پەیوەندی ئینتەرنێت بپشکنە.';
      });
    } finally {
      _loadInFlight = false;
    }
  }

  Future<void> _toggleActive() async {
    final newActive = !_isActive;
    final confirm = await AppHelpers.showConfirmDialog(
      context,
      title: newActive ? 'چالاککردن' : 'ناچالاککردن',
      message: newActive
          ? 'ئایا دڵنیایت لە چالاککردنی ئەم کارمەندە؟'
          : 'ئایا دڵنیایت لە ناچالاککردنی ئەم کارمەندە؟\nکارمەند ناتوانێت داخڵ ببێت.',
    );
    if (!confirm) return;

    try {
      await PBService.updateUser(widget.userId, {'active': newActive});
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          newActive ? 'کارمەند چالاک کرا' : 'کارمەند ناچالاک کرا',
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(context, AppHelpers.backendErrorMessage(e), isError: true);
      }
    }
  }

  Future<void> _saveProfileChanges() async {
    if (_nameController.text.trim().isEmpty) {
      AppHelpers.showSnackBar(context, 'ناو بنووسە', isError: true);
      return;
    }
    if (_phoneController.text.trim().isEmpty) {
      AppHelpers.showSnackBar(context, 'ژمارە مۆبایل بنووسە', isError: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final data = <String, dynamic>{
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
      };

      await PBService.updateUser(widget.userId, data);
      if (mounted) {
        AppHelpers.showSnackBar(context, 'بە سەرکەوتوویی نوێکرایەوە');
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(context, AppHelpers.backendErrorMessage(e), isError: true);
      }
    }
    if (mounted) setState(() => _isSaving = false);
  }

  Color get _accentColor =>
      _isEmployee ? const Color(0xFF4A6CF7) : AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark
            ? AppDarkColors.background
            : const Color(0xFFF5F7FA),
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        backgroundColor: isDark
            ? AppDarkColors.background
            : const Color(0xFFF5F7FA),
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 42, color: Colors.orange),
                const SizedBox(height: 12),
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    height: 1.6,
                    color: isDark
                        ? AppDarkColors.textPrimary
                        : const Color(0xFF344054),
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('دووبارە هەوڵ بدە'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_user == null) {
      return Scaffold(
        backgroundColor: isDark
            ? AppDarkColors.background
            : const Color(0xFFF5F7FA),
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(child: Text('بەکارهێنەر نەدۆزرایەوە')),
      );
    }

    final name = _user!.getStringValue('name');
    final phone = _user!.getStringValue('phone');

    return Scaffold(
      backgroundColor: isDark
          ? AppDarkColors.background
          : const Color(0xFFF5F7FA),
      body: CustomScrollView(
        slivers: [
          // ───── Gradient Header ─────
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.88)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    // Nav Row
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          if (Navigator.canPop(context))
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back_ios,
                                color: Colors.white,
                                size: 22,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _isEmployee ? 'کارمەند' : 'کڕیار',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if ((_isCustomer &&
                                  auth.userId != widget.userId &&
                                  auth.canSendNotifications) ||
                              (auth.userId == widget.userId && _isEmployee) ||
                              auth.userId == widget.userId ||
                              (auth.userRole == 'admin' &&
                                  auth.userId != widget.userId)) ...[
                            const SizedBox(width: 6),
                            PopupMenuButton<String>(
                              tooltip: 'کردارەکان',
                              color: isDark ? AppDarkColors.card : Colors.white,
                              surfaceTintColor: Colors.transparent,
                              elevation: 6,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              icon: Container(
                                width: 36,
                                height: 36,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(11),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.14),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.more_horiz_rounded,
                                  color: Colors.white,
                                  size: 21,
                                ),
                              ),
                              onSelected: (value) async {
                                if (value == 'notify') {
                                  _showNotificationDialog();
                                  return;
                                }
                                if (value == 'theme') {
                                  context.read<ThemeProvider>().toggleTheme();
                                  return;
                                }
                                if (value == 'logout') {
                                  final confirm = await AppHelpers.showConfirmDialog(
                                    context,
                                    title: AppStrings.logout,
                                    message: 'دڵنیایت لە چوونەدەرەوە؟',
                                  );
                                  if (confirm && mounted) await auth.logout();
                                  return;
                                }
                                if (value == 'delete') {
                                  _confirmDelete();
                                }
                              },
                              itemBuilder: (_) => [
                                if (_isCustomer &&
                                    auth.userId != widget.userId &&
                                    auth.canSendNotifications)
                                  const PopupMenuItem<String>(
                                    value: 'notify',
                                    child: Row(
                                      children: [
                                        Icon(Icons.notifications_none_rounded, size: 19),
                                        SizedBox(width: 10),
                                        Text('ناردنی ئاگادارکردنەوە'),
                                      ],
                                    ),
                                  ),
                                if (auth.userId == widget.userId && _isEmployee)
                                  PopupMenuItem<String>(
                                    value: 'theme',
                                    child: Row(
                                      children: [
                                        Icon(
                                          isDark
                                              ? Icons.light_mode_outlined
                                              : Icons.dark_mode_outlined,
                                          size: 19,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(isDark ? 'ڕووناکی' : 'دۆخی تاریک'),
                                      ],
                                    ),
                                  ),
                                if (auth.userId == widget.userId)
                                  const PopupMenuItem<String>(
                                    value: 'logout',
                                    child: Row(
                                      children: [
                                        Icon(Icons.logout_rounded, size: 19),
                                        SizedBox(width: 10),
                                        Text('چوونەدەرەوە'),
                                      ],
                                    ),
                                  ),
                                if (auth.userRole == 'admin' &&
                                    auth.userId != widget.userId)
                                  const PopupMenuItem<String>(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline_rounded,
                                            size: 19, color: Colors.red),
                                        SizedBox(width: 10),
                                        Text('سڕینەوە',
                                            style: TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Avatar + Name
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 2, 20, 20),
                      child: Column(
                        children: [
                          // Avatar
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.phone_android,
                                size: 14,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                phone,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 14,
                                ),
                                textDirection: TextDirection.ltr,
                              ),
                            ],
                          ),
                          if (_isEmployee) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _isActive
                                    ? Colors.green.withValues(alpha: 0.3)
                                    : Colors.red.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isActive
                                        ? Icons.check_circle
                                        : Icons.block,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _isActive ? 'چالاک' : 'ناچالاک',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ───── Body ─────
          if (_isCustomer) ..._buildCustomerBody(),
          if (_isEmployee) ..._buildEmployeeBody(),

          const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // ── Customer Body ──
  // ═══════════════════════════════════════════

  List<Widget> _buildCustomerBody() {
    final totalDebt = _debts.fold(
      0.0,
      (sum, d) => sum + d.getDoubleValue('amount'),
    );
    final totalRemaining = _debts.fold(
      0.0,
      (sum, d) => sum + d.getDoubleValue('remaining'),
    );
    final totalPaid = totalDebt - totalRemaining;
    final auth = context.read<AuthProvider>();

    final overview = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Row(
            children: [
              _buildStatChip(
                Icons.monetization_on_outlined,
                'کۆی قەرز',
                AppHelpers.formatCurrency(totalDebt),
                Colors.orange,
              ),
              const SizedBox(width: 10),
              _buildStatChip(
                Icons.pending_outlined,
                'ماوە',
                AppHelpers.formatCurrency(totalRemaining),
                Colors.red,
              ),
            ],
          ),
        ),
      ),
      if (auth.userRole == 'admin')
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: OutlinedButton.icon(
              onPressed: () => _generateAccountStatement(
                totalDebt: totalDebt,
                totalRemaining: totalRemaining,
                totalPaid: totalPaid,
              ),
              icon: const Icon(Icons.receipt_long_rounded, size: 19),
              label: const Text('کەشف حیساب'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: _accentColor,
                side: BorderSide(color: _accentColor.withValues(alpha: 0.25)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
      _buildDebtLimitCard(),
    ];

    final transactions = <Widget>[
      _buildCustomerChatTimelineCard(
        totalDebt: totalDebt,
        totalRemaining: totalRemaining,
        totalPaid: totalPaid,
      ),
    ];

    final edit = <Widget>[
      _buildProfileEditor(),
    ];

    return [
      _buildCustomerSectionTabs(),
      ...switch (_customerSection) {
        1 => transactions,
        2 => edit,
        _ => overview,
      },
    ];
  }

  Widget _buildCustomerSectionTabs() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const labels = ['پوختە', 'مامەڵەکان', 'دەستکاری'];
    const icons = [
      Icons.space_dashboard_outlined,
      Icons.swap_horiz_rounded,
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
              final selected = _customerSection == index;
              return Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (_customerSection == index) return;
                      setState(() => _customerSection = index);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? (isDark ? AppDarkColors.surface : Colors.white)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: selected && !isDark
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icons[index],
                            size: 17,
                            color: selected
                                ? _accentColor
                                : (isDark
                                    ? AppDarkColors.textSecondary
                                    : Colors.grey[600]),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              labels[index],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected
                                    ? _accentColor
                                    : (isDark
                                        ? AppDarkColors.textSecondary
                                        : Colors.grey[700]),
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

  // ═══════════════════════════════════════════
  // ── Customer Chat Timeline ──
  // ═══════════════════════════════════════════

  DateTime _timelineDate(RecordModel record) {
    final customDate = record.getStringValue('custom_date');
    final created = record.getStringValue('created').isNotEmpty
        ? record.getStringValue('created')
        : record.created;
    for (final candidate in [customDate, created]) {
      if (candidate.isEmpty) continue;
      try {
        return DateTime.parse(candidate).toLocal();
      } catch (_) {}
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<_ProfileTimelineItem> _buildTimelineItems() {
    final debtsById = {for (final debt in _debts) debt.id: debt};
    final items = <_ProfileTimelineItem>[
      for (final debt in _debts)
        _ProfileTimelineItem(
          kind: 'debt',
          record: debt,
          date: _timelineDate(debt),
        ),
      for (final payment in _payments)
        _ProfileTimelineItem(
          kind: 'payment',
          record: payment,
          relatedDebt: debtsById[payment.getStringValue('debt')],
          date: _timelineDate(payment),
        ),
    ];

    // Oldest first gives a natural chat/timeline flow.
    items.sort((a, b) => a.date.compareTo(b.date));
    return items;
  }

  Widget _buildCustomerChatTimelineCard({
    required double totalDebt,
    required double totalRemaining,
    required double totalPaid,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timelineItems = _buildTimelineItems();
    final health = _debtHealth(totalRemaining, totalDebt);

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.receipt_long_outlined,
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
                        'مامەڵەکان',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? AppDarkColors.textPrimary
                              : const Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${timelineItems.length} تۆمار',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark
                              ? AppDarkColors.textSecondary
                              : const Color(0xFF98A2B3),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDebtHealthStrip(
              label: health.$1,
              color: health.$2,
              totalRemaining: totalRemaining,
              totalPaid: totalPaid,
            ),
            const SizedBox(height: 10),
            if (timelineItems.isEmpty)
              _buildEmptyTimelineState(isDark)
            else
              ...timelineItems.asMap().entries.map(
                    (entry) => _buildTimelineBubble(entry.value, entry.key),
                  ),
          ],
        ),
      ),
    );
  }

  (String, Color) _debtHealth(double totalRemaining, double totalDebt) {
    final debtLimit = _user?.getDoubleValue('debt_limit') ?? 0;
    if (totalRemaining <= 0) return ('باش — هیچ قەرزێکی ماوە نییە', Colors.green);
    if (debtLimit > 0 && totalRemaining > debtLimit) {
      return ('مەترسیدار — سنووری قەرز تێپەڕیوە', Colors.red);
    }
    final ratio = totalDebt <= 0 ? 0.0 : totalRemaining / totalDebt;
    if (ratio >= 0.75) return ('ئاگاداری — پارەدانەوە کەمە', Colors.orange);
    if (ratio >= 0.35) return ('مامناوەند — پێویستی بە چاودێرییە', Colors.blue);
    return ('باش — پارەدانەوە ڕێکوپێکە', Colors.green);
  }

  Widget _buildDebtHealthStrip({
    required String label,
    required Color color,
    required double totalRemaining,
    required double totalPaid,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'ماوە ${AppHelpers.formatCurrency(totalRemaining)}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppDarkColors.textSecondary
                  : const Color(0xFF667085),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTimelineState(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 26),
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
        children: [
          Icon(
            Icons.receipt_long_outlined,
            color: isDark ? AppDarkColors.textSecondary : Colors.grey[400],
            size: 30,
          ),
          const SizedBox(height: 8),
          Text(
            'هێشتا هیچ مامەڵەیەک نییە',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isDark ? AppDarkColors.textPrimary : const Color(0xFF344054),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineBubble(_ProfileTimelineItem item, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPayment = item.isPayment;
    final record = item.record;
    final relatedDebt = item.relatedDebt;
    final amount = record.getDoubleValue('amount');
    final currency = isPayment
        ? (relatedDebt?.getStringValue('currency').isNotEmpty == true
            ? relatedDebt!.getStringValue('currency')
            : 'IQD')
        : record.getStringValue('currency').isNotEmpty
            ? record.getStringValue('currency')
            : 'IQD';
    final dollarRate = isPayment
        ? (relatedDebt?.getDoubleValue('dollar_rate') ?? 0)
        : record.getDoubleValue('dollar_rate');
    final description = isPayment
        ? record.getStringValue('note')
        : record.getStringValue('description');
    final status = isPayment ? '' : record.getStringValue('status');
    final title = isPayment ? 'پارەدانەوە' : 'قەرز';
    final color = isPayment ? Colors.green : Colors.orange;
    final icon = isPayment
        ? Icons.south_west_rounded
        : Icons.north_east_rounded;
    final formattedAmount = AppHelpers.formatCurrencyWithType(
      amount,
      currency,
      dollarRate: dollarRate,
      showConversion: currency == 'USD',
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 180 + (index * 20).clamp(0, 220)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - value)),
          child: child,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
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
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? AppDarkColors.textPrimary
                              : const Color(0xFF1D2939),
                        ),
                      ),
                      if (!isPayment && status.isNotEmpty) ...[
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            AppHelpers.statusName(status),
                            style: TextStyle(
                              color: color,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    AppHelpers.formatDateTime(item.date.toIso8601String()),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark
                          ? AppDarkColors.textSecondary
                          : const Color(0xFF98A2B3),
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppDarkColors.textSecondary
                            : const Color(0xFF667085),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 122),
              child: Text(
                formattedAmount,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: color,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                ),
                textDirection: TextDirection.ltr,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateAccountStatement({
    required double totalDebt,
    required double totalRemaining,
    required double totalPaid,
  }) async {
    final auth = context.read<AuthProvider>();
    final customerName = _user?.getStringValue('name') ?? '';

    try {
      await PdfService.generateCustomerStatement(
        activeDebts: _debts,
        customerName: customerName,
        marketName: auth.marketName,
        adminName: auth.userName,
        adminPhone: auth.user?.getStringValue('phone') ?? '',
        totalDebt: totalDebt,
        totalRemaining: totalRemaining,
        totalPaid: totalPaid,
      );
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(context, AppHelpers.backendErrorMessage(e), isError: true);
      }
    }
  }

  // ═══════════════════════════════════════════
  // ── Employee Body ──
  // ═══════════════════════════════════════════

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
  // ── Secure Password Management ──
  // ═══════════════════════════════════════════

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
    final totalRemaining = _debts.fold(
      0.0,
      (sum, d) => sum + d.getDoubleValue('remaining'),
    );
    final remainingLimit = hasLimit ? limit - totalRemaining : 0.0;
    final isOverLimit = hasLimit && remainingLimit < 0;
    final usagePercent = hasLimit
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
                            'سنوری قەرز',
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
                              AppHelpers.formatCurrency(remainingLimit.abs()),
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
              'سنوری قەرز',
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
                  if (mounted) {
                    Navigator.pop(dialogContext);
                    AppHelpers.showSnackBar(context, 'سنوری قەرز لابرا');
                    _loadData();
                  }
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
                if (mounted) {
                  Navigator.pop(dialogContext);
                  AppHelpers.showSnackBar(
                    context,
                    newLimit > 0
                        ? 'سنوری قەرز دانرا: ${AppHelpers.formatCurrency(newLimit)}'
                        : 'سنوری قەرز لابرا',
                  );
                  _loadData();
                }
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

  Widget _buildStatChip(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppDarkColors.card : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: color.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppDarkColors.textSecondary
                          : Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isDark
                          ? AppDarkColors.textPrimary
                          : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    TextDirection? textDirection,
    bool readOnly = false,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? (readOnly ? AppDarkColors.surface : AppDarkColors.background)
            : (readOnly ? Colors.grey[100] : Colors.grey[50]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppDarkColors.cardBorder : Colors.grey[200]!,
        ),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textDirection: textDirection,
        readOnly: readOnly,
        obscureText: obscureText,
        style: TextStyle(
          color: isDark ? AppDarkColors.textPrimary : Colors.black87,
        ),
        textAlign: textDirection == TextDirection.ltr
            ? TextAlign.center
            : TextAlign.start,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: isDark ? AppDarkColors.textSecondary : Colors.grey[500],
            fontSize: 14,
          ),
          prefixIcon: Icon(
            icon,
            color: readOnly ? Colors.grey : _accentColor,
            size: 20,
          ),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  // ───── Actions ─────

  void _confirmDelete() async {
    // If customer, check balance first — block deletion if balance > 0
    if (_isCustomer) {
      try {
        final balance = await PBService.getCustomerBalance(widget.userId);
        if (balance > 0) {
          if (mounted) {
            AppHelpers.showSnackBar(
              context,
              'ناتوانرێت ئەم کڕیارە بسڕیتەوە، قەرزی ماوەی هەیە',
              isError: true,
            );
          }
          return;
        }
      } catch (_) {
        if (mounted) {
          AppHelpers.showSnackBar(
            context,
            'نەتوانرا باڵانسی کڕیار پشتڕاست بکرێتەوە. کڕیار ناسڕدرێتەوە تا پەیوەندی سێرڤەر دروست بێت.',
            isError: true,
          );
        }
        return;
      }
    }

    final confirm = await AppHelpers.showConfirmDialog(
      context,
      title: _isCustomer ? 'سڕینەوەی کڕیار' : 'سڕینەوەی کارمەند',
      message: _isCustomer
          ? 'دڵنیایت لە سڕینەوەی ئەم کڕیارە؟'
          : 'دڵنیایت لە سڕینەوەی ئەم کارمەندە؟',
    );
    if (confirm) {
      try {
        await PBService.deleteUser(widget.userId);
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) {
          AppHelpers.showSnackBar(context, AppHelpers.backendErrorMessage(e), isError: true);
        }
      }
    }
  }

  void _showNotificationDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ناردنی ئاگادارکردنەوە'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'پەیام',
            hintText: 'پەیامەکەت بنووسە...',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('پاشگەزبوونەوە'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              try {
                // Remove await to not block UI, or keep it if we want to show snackbar after success
                // Using await for better UX feedback
                await PBService.createNotification(
                  customerId: widget.userId,
                  message: controller.text.trim(),
                  senderId: context.read<AuthProvider>().userId,
                );
                if (mounted) {
                  Navigator.pop(context);
                  AppHelpers.showSnackBar(context, 'ئاگادارکردنەوە نێردرا');
                }
              } catch (e) {
                if (mounted) {
                  AppHelpers.showSnackBar(context, AppHelpers.backendErrorMessage(e), isError: true);
                }
              }
            },
            child: const Text('ناردن'),
          ),
        ],
      ),
    );
  }
}
