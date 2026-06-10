import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  Map<String, double> _employeeStats = {};
  final _debtLimitController = TextEditingController();

  // Employee Permissions (Editable by Admin)
  bool _canAddCustomers = false;
  bool _canSetDebtLimit = false;
  bool _canSetDueDate = false;
  bool _canEditDebts = false;
  bool _canSendNotifications = false;
  bool _obscurePassword = true;
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
    _passwordController.dispose();
    _debtLimitController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final cacheKeyUser = 'cached_profile_user_${widget.userId}';
    final cacheKeyDebts = 'cached_profile_debts_${widget.userId}';
    final cacheKeyPayments = 'cached_profile_payments_${widget.userId}';
    final cacheKeyStats = 'cached_profile_stats_${widget.userId}';

    try {
      _user = await PBService.getUser(widget.userId);

      // Cache User
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKeyUser, jsonEncode(_user!.toJson()));

      // Populate controllers for all users (if viewing self or editable)
      _nameController.text = _user!.getStringValue('name');
      _phoneController.text = _user!.getStringValue('phone');
      _passwordController.text = _user!.getStringValue('password_text');

      if (_isCustomer) {
        _debts = await PBService.getDebts(customerId: widget.userId);
        _payments = await PBService.getPayments(customerId: widget.userId);
        // Cache Debts + Payments for offline profile review
        final debtsJson = _debts.map((d) => d.toJson()).toList();
        final paymentsJson = _payments.map((p) => p.toJson()).toList();
        await prefs.setString(cacheKeyDebts, jsonEncode(debtsJson));
        await prefs.setString(cacheKeyPayments, jsonEncode(paymentsJson));
      }
      if (_isEmployee) {
        _employeeStats = await PBService.getEmployeeStats(widget.userId);
        // Cache Stats
        await prefs.setString(cacheKeyStats, jsonEncode(_employeeStats));

        _canAddCustomers = _user!.getBoolValue('can_add_customers');
        _canSetDebtLimit = _user!.getBoolValue('can_set_debt_limit');
        _canSetDueDate = _user!.getBoolValue('can_set_due_date');
        _canEditDebts = _user!.getBoolValue('can_edit_debts');
        _canSendNotifications = _user!.getBoolValue('can_send_notifications');
      }
    } catch (e) {
      // Offline fallback
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedUserString = prefs.getString(cacheKeyUser);

        if (cachedUserString != null) {
          final userData = jsonDecode(cachedUserString);
          _user = RecordModel.fromJson(userData);

          _nameController.text = _user!.getStringValue('name');
          _phoneController.text = _user!.getStringValue('phone');
          _passwordController.text = _user!.getStringValue('password_text');

          if (_isCustomer) {
            final cachedDebts = prefs.getString(cacheKeyDebts);
            if (cachedDebts != null) {
              final List<dynamic> decoded = jsonDecode(cachedDebts);
              _debts = decoded
                  .map((item) => RecordModel.fromJson(item))
                  .toList();
            }
            final cachedPayments = prefs.getString(cacheKeyPayments);
            if (cachedPayments != null) {
              final List<dynamic> decoded = jsonDecode(cachedPayments);
              _payments = decoded
                  .map((item) => RecordModel.fromJson(item))
                  .toList();
            }
          }
          if (_isEmployee) {
            final cachedStats = prefs.getString(cacheKeyStats);
            if (cachedStats != null) {
              _employeeStats = Map<String, double>.from(
                jsonDecode(cachedStats),
              );
            }
            _canAddCustomers = _user!.getBoolValue('can_add_customers');
            _canSetDebtLimit = _user!.getBoolValue('can_set_debt_limit');
            _canSetDueDate = _user!.getBoolValue('can_set_due_date');
            _canEditDebts = _user!.getBoolValue('can_edit_debts');
            _canSendNotifications = _user!.getBoolValue(
              'can_send_notifications',
            );
          }
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _isLoading = false);
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
        AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);
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
    if (_passwordController.text.length < 8) {
      AppHelpers.showSnackBar(
        context,
        'وشەی نهێنی لانیکەم ٨ پیت بێت',
        isError: true,
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final data = <String, dynamic>{
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
      };

      // Update password_text if password field is not empty
      if (_passwordController.text.isNotEmpty) {
        data['password_text'] = _passwordController.text;
      }

      // Update permissions if admin editing employee
      if (_isEmployee && context.read<AuthProvider>().userRole == 'admin') {
        data['can_add_customers'] = _canAddCustomers;
        data['can_set_debt_limit'] = _canSetDebtLimit;
        data['can_set_due_date'] = _canSetDueDate;
        data['can_edit_debts'] = _canEditDebts;
        data['can_send_notifications'] = _canSendNotifications;
      }

      await PBService.updateUser(widget.userId, data);
      if (mounted) {
        AppHelpers.showSnackBar(context, 'بە سەرکەوتوویی نوێکرایەوە');
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);
      }
    }
    setState(() => _isSaving = false);
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
                  colors: _isEmployee
                      ? [const Color(0xFF4A6CF7), const Color(0xFF6B8CFF)]
                      : [
                          AppColors.primary,
                          AppColors.primary.withOpacity(0.85),
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
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
                              color: Colors.white.withOpacity(0.2),
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

                          if (_isCustomer &&
                              auth.userId != widget.userId &&
                              auth.canSendNotifications) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(
                                Icons.notifications_active_outlined,
                                color: Colors.white.withOpacity(0.8),
                                size: 22,
                              ),
                              onPressed: _showNotificationDialog,
                            ),
                          ],

                          // Theme toggle (own profile, employees only)
                          if (auth.userId == widget.userId && _isEmployee) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  isDark
                                      ? Icons.light_mode_rounded
                                      : Icons.dark_mode_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                              onPressed: () {
                                context.read<ThemeProvider>().toggleTheme();
                              },
                            ),
                          ],

                          // Logout button (own profile)
                          if (auth.userId == widget.userId) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(
                                Icons.logout,
                                color: Colors.white.withOpacity(0.8),
                                size: 22,
                              ),
                              onPressed: () {
                                AppHelpers.showConfirmDialog(
                                  context,
                                  title: AppStrings.logout,
                                  message: 'دڵنیایت لە چوونەدەرەوە؟',
                                ).then((confirm) async {
                                  if (confirm && mounted) {
                                    await auth.logout();
                                  }
                                });
                              },
                            ),
                          ]
                          // Delete button (admin only, viewing other profiles)
                          else if (auth.userRole == 'admin') ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: Colors.white.withOpacity(0.8),
                                size: 22,
                              ),
                              onPressed: _confirmDelete,
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Avatar + Name
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
                      child: Column(
                        children: [
                          // Avatar
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.phone_android,
                                size: 14,
                                color: Colors.white.withOpacity(0.7),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                phone,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
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
                                    ? Colors.green.withOpacity(0.3)
                                    : Colors.red.withOpacity(0.3),
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

    return [
      // Stats
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
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

      // Account Statement Button
      if (auth.userRole == 'admin')
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _generateAccountStatement(
                  totalDebt: totalDebt,
                  totalRemaining: totalRemaining,
                  totalPaid: totalPaid,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.indigo.shade600, Colors.indigo.shade400],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.indigo.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.receipt_long_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'کەشف حیساب',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.print_rounded,
                        color: Colors.white.withOpacity(0.7),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

      // Chat-style customer transaction timeline
      _buildCustomerChatTimelineCard(
        totalDebt: totalDebt,
        totalRemaining: totalRemaining,
        totalPaid: totalPaid,
      ),

      // Debt Limit Card
      _buildDebtLimitCard(),

      // Edit Profile Form
      _buildProfileEditor(),
    ];
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
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? AppDarkColors.card : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: isDark
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'پڕۆفایلی مامەڵەکان بە شێوەی چات',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppDarkColors.textPrimary
                                  : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'قەرز پێدان لای ڕاست، پارەدانەوە لای چەپ',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppDarkColors.textSecondary
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildDebtHealthStrip(
                  label: health.$1,
                  color: health.$2,
                  totalRemaining: totalRemaining,
                  totalPaid: totalPaid,
                ),
                const SizedBox(height: 14),
                if (timelineItems.isEmpty)
                  _buildEmptyTimelineState(isDark)
                else
                  ...timelineItems.asMap().entries.map(
                        (entry) => _buildTimelineBubble(entry.value, entry.key),
                      ),
              ],
            ),
          ),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.health_and_safety_outlined, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'ماوە: ${AppHelpers.formatCurrency(totalRemaining)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppDarkColors.textSecondary : Colors.grey[700],
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'دراوە: ${AppHelpers.formatCurrency(totalPaid)}',
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppDarkColors.textSecondary : Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTimelineState(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.background : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            Icons.forum_outlined,
            color: isDark ? AppDarkColors.textSecondary : Colors.grey[500],
            size: 34,
          ),
          const SizedBox(height: 8),
          Text(
            'هێشتا هیچ مامەڵەیەک نییە',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? AppDarkColors.textPrimary : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'کاتێک قەرز یان پارەدانەوە زیاد بکرێت، لێرە وەک چات دەردەکەوێت.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppDarkColors.textSecondary : Colors.grey[600],
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
    final title = isPayment ? 'پارە وەرگرتنەوە' : 'قەرز پێدان';
    final color = isPayment ? Colors.green : Colors.orange;
    final icon = isPayment ? Icons.south_west_rounded : Icons.north_east_rounded;
    final align = isPayment ? Alignment.centerLeft : Alignment.centerRight;
    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isPayment ? 6 : 18),
      bottomRight: Radius.circular(isPayment ? 18 : 6),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + (index * 35).clamp(0, 420)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Align(
        alignment: align,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.74,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isPayment
                  ? [Colors.green.shade600, Colors.green.shade400]
                  : [Colors.orange.shade700, Colors.orange.shade500],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: bubbleRadius,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(isDark ? 0.10 : 0.22),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    AppHelpers.formatDateTime(item.date.toIso8601String()),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.78),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                AppHelpers.formatCurrencyWithType(
                  amount,
                  currency,
                  dollarRate: dollarRate,
                  showConversion: currency == 'USD',
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
                textDirection: TextDirection.ltr,
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
              if (!isPayment && status.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    AppHelpers.statusName(status),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
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
        AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);
      }
    }
  }

  // ═══════════════════════════════════════════
  // ── Employee Body ──
  // ═══════════════════════════════════════════

  List<Widget> _buildEmployeeBody() {
    return [
      // Stats
      if (_employeeStats.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Row(
              children: [
                _buildAnimatedStatChip(
                  Icons.receipt_long_outlined,
                  'قەرزی تۆمارکراو',
                  _employeeStats['totalDebtsCreated'] ?? 0,
                  Colors.orange,
                ),
                const SizedBox(width: 10),
                _buildAnimatedStatChip(
                  Icons.payments_outlined,
                  'پارەی وەرگیراو',
                  _employeeStats['totalPaymentsCollected'] ?? 0,
                  Colors.green,
                ),
              ],
            ),
          ),
        ),

      // Active toggle (Only Admin can see/change this)
      if (context.read<AuthProvider>().userRole == 'admin')
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppDarkColors.card
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: Theme.of(context).brightness == Brightness.dark
                    ? []
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (_isActive ? Colors.green : Colors.red)
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _isActive ? Icons.check_circle : Icons.block,
                        color: _isActive ? Colors.green : Colors.red,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isActive ? 'چالاک' : 'ناچالاک',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _isActive ? Colors.green : Colors.red,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            _isActive
                                ? 'کارمەند دەتوانێت داخڵ ببێت'
                                : 'کارمەند ناتوانێت داخڵ ببێت',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isActive,
                      activeThumbColor: Colors.green,
                      onChanged: (_) => _toggleActive(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

      // Edit Form
      _buildProfileEditor(),
    ];
  }

  // ═══════════════════════════════════════════
  // ── Shared Profile Editor ──
  // ═══════════════════════════════════════════

  Widget _buildProfileEditor() {
    final auth = context.read<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Employee can only edit Password.
    // Customer can only edit Password (Task 21 - Updated).
    // Admin can edit everything.
    final bool isEmployeeView = auth.userRole == 'employee';
    final bool isCustomerView = auth.userRole == 'customer';
    // Only admins can edit name/phone
    final bool canEditInfo = !isEmployeeView && !isCustomerView;

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
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 20, color: _accentColor),
                    const SizedBox(width: 8),
                    Text(
                      'گۆڕانکاری لە زانیارییەکان',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppDarkColors.textPrimary
                            : Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildTextField(
                  controller: _nameController,
                  label: AppStrings.name,
                  icon: Icons.person_outline,
                  readOnly: !canEditInfo,
                ),
                const SizedBox(height: 14),
                _buildTextField(
                  controller: _phoneController,
                  label: AppStrings.phone,
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  readOnly: !canEditInfo,
                ),
                // Password field: hide from employees viewing other users' profiles
                if (!isEmployeeView || auth.userId == widget.userId) ...[
                  const SizedBox(height: 14),
                  _buildTextField(
                    controller: _passwordController,
                    label: AppStrings.password,
                    icon: Icons.lock_outline,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        size: 20,
                        color: isDark ? AppDarkColors.textSecondary : Colors.grey,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ],
                // Permissions (Only Admin viewing Employee)
                if (_isEmployee &&
                    context.read<AuthProvider>().userRole == 'admin') ...[
                  const SizedBox(height: 24),
                  Text(
                    'دەسەڵاتەکان',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppDarkColors.textPrimary
                          : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('زیادکردنی کڕیار'),
                    value: _canAddCustomers,
                    onChanged: (v) => setState(() => _canAddCustomers = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    title: const Text('دانانی سنوری قەرز'),
                    value: _canSetDebtLimit,
                    onChanged: (v) => setState(() => _canSetDebtLimit = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    title: const Text('دانانی بەرواری دانەوە'),
                    value: _canSetDueDate,
                    onChanged: (v) => setState(() => _canSetDueDate = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    title: const Text('دەستکاریکردنی قەرز'),
                    value: _canEditDebts,
                    onChanged: (v) => setState(() => _canEditDebts = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    title: const Text('ناردنی ئاگادارکردنەوە کان'),
                    value: _canSendNotifications,
                    onChanged: (v) => setState(() => _canSendNotifications = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 50,
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
                      color: Colors.black.withOpacity(0.04),
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
                                .withOpacity(0.1),
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
                            color: AppColors.primary.withOpacity(0.1),
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
                color: AppColors.primary.withOpacity(0.1),
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
                    AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);
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
                  AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);
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
                    color: color.withOpacity(0.08),
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
                color: color.withOpacity(0.1),
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

  Widget _buildAnimatedStatChip(
    IconData icon,
    String label,
    double value,
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
                    color: color.withOpacity(0.08),
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
                color: color.withOpacity(0.1),
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
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: value),
                    duration: const Duration(seconds: 2),
                    curve: Curves.easeOut,
                    builder: (context, val, _) {
                      return Text(
                        AppHelpers.formatCurrency(val),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: color,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                      );
                    },
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
      } catch (e) {
        if (mounted) {
          AppHelpers.showSnackBar(
            context,
            'هەڵە لە پشکنینی باڵانس: $e',
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
          AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);
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
                  AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);
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
