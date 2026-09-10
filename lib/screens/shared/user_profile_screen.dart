import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/shared/add_debt_screen.dart';
import 'package:zhirox/screens/shared/debt_detail_screen.dart';

import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/services/pdf_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:zhirox/providers/theme_provider.dart';
import 'package:zhirox/services/connectivity_service.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  final bool openFinancialChat;

  const UserProfileScreen({
    super.key,
    required this.userId,
    this.openFinancialChat = false,
  });

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
  bool get isSystem => kind == 'system';
}


class _UserProfileScreenState extends State<UserProfileScreen> {
  RecordModel? _user;
  List<RecordModel> _debts = [];
  List<RecordModel> _payments = [];
  List<RecordModel> _financialEvents = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _loadInFlight = false;
  bool _financialRefreshInFlight = false;
  bool _financialRefreshPending = false;
  bool _financialAutoJumpPending = false;
  late int _customerSection;
  int _employeeSection = 0;
  String? _loadError;
  bool _hasNewFinancialActivity = false;
  final _financialSearchController = TextEditingController();
  DateTimeRange? _financialDateRange;
  String _financialTypeFilter = 'all';

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
  final ScrollController _profileScrollController = ScrollController();
  RealtimeChannel? _financialRealtimeChannel;
  Timer? _financialRealtimeDebounce;

  bool get _isCustomer => _user?.getStringValue('role') == 'customer';
  bool get _isEmployee => _user?.getStringValue('role') == 'employee';
  bool get _isActive => _user?.getBoolValue('active') ?? true;

  @override
  void initState() {
    super.initState();
    _customerSection = widget.openFinancialChat ? 1 : 0;
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_subscribeFinancialRealtime());
    });
    _connectivitySub = ConnectivityService.instance.statusStream.listen((online) {
      if (online && mounted) _loadData();
    });
  }

  @override
  void dispose() {
    _financialRealtimeDebounce?.cancel();
    final financialChannel = _financialRealtimeChannel;
    if (financialChannel != null) {
      unawaited(PBService.client.removeChannel(financialChannel));
    }
    _profileScrollController.dispose();
    _financialSearchController.dispose();
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
      List<RecordModel> financialEvents = [];
      Map<String, double> employeeStats = {};

      if (role == 'customer') {
        final customerData = await Future.wait<List<RecordModel>>([
          PBService.getDebts(customerId: widget.userId),
          PBService.getPayments(customerId: widget.userId),
          PBService.getFinancialEvents(widget.userId),
        ]);
        debts = customerData[0];
        payments = customerData[1];
        financialEvents = customerData[2];
      } else if (role == 'employee') {
        employeeStats = await PBService.getEmployeeStats(widget.userId);
      }

      if (!mounted) return;
      setState(() {
        _user = user;
        _debts = debts;
        _payments = payments;
        _financialEvents = financialEvents;
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
      if (role == 'customer' && _customerSection == 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _jumpToLatest(animated: false);
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _user = null;
        _debts = [];
        _payments = [];
        _financialEvents = [];
        _employeeStats = {};
        _isLoading = false;
        _loadError =
            'نەتوانرا زانیارییەکانی پروفایل باربکرێن. پەیوەندی ئینتەرنێت بپشکنە.';
      });
    } finally {
      _loadInFlight = false;
    }
  }

  Future<void> _subscribeFinancialRealtime() async {
    try {
      await PBService.ensureInitialized();
      if (!mounted) return;

      final previous = _financialRealtimeChannel;
      if (previous != null) {
        try {
          await PBService.client.removeChannel(previous);
        } catch (_) {}
      }

      final channel = PBService.client
          .channel(
            'financial-chat:${widget.userId}:${DateTime.now().microsecondsSinceEpoch}',
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'financial_events',
            callback: (payload) {
              final raw = payload.newRecord.isNotEmpty
                  ? payload.newRecord
                  : payload.oldRecord;
              if (raw['customer_id']?.toString() != widget.userId) return;
              _handleFinancialRealtimeEvent();
            },
          )
          .subscribe();

      if (!mounted) {
        try {
          await PBService.client.removeChannel(channel);
        } catch (_) {}
        return;
      }
      _financialRealtimeChannel = channel;
    } catch (_) {
      // Reconnect and explicit manual refresh remain available if realtime
      // cannot be established. Never make live data look successfully cached.
    }
  }

  bool get _isNearFinancialEnd {
    if (!_profileScrollController.hasClients) return false;
    final position = _profileScrollController.position;
    return position.maxScrollExtent - position.pixels < 150;
  }

  void _handleFinancialRealtimeEvent() {
    if (!mounted) return;
    final autoJump = _customerSection == 1 && _isNearFinancialEnd;
    if (!autoJump && !_hasNewFinancialActivity) {
      setState(() => _hasNewFinancialActivity = true);
    }

    _financialRealtimeDebounce?.cancel();
    _financialRealtimeDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      unawaited(_refreshFinancialData(autoJump: autoJump));
    });
  }

  Future<void> _refreshFinancialData({
    bool autoJump = false,
    bool showError = false,
  }) async {
    if (!mounted) return;
    if (_financialRefreshInFlight) {
      _financialRefreshPending = true;
      _financialAutoJumpPending = _financialAutoJumpPending || autoJump;
      return;
    }

    _financialRefreshInFlight = true;
    try {
      final customerData = await Future.wait<List<RecordModel>>([
        PBService.getDebts(customerId: widget.userId),
        PBService.getPayments(customerId: widget.userId),
        PBService.getFinancialEvents(widget.userId),
      ]);
      if (!mounted) return;
      setState(() {
        _debts = customerData[0];
        _payments = customerData[1];
        _financialEvents = customerData[2];
      });
      if (autoJump && _customerSection == 1) {
        _jumpToLatest();
      }
    } catch (e) {
      if (showError && mounted) {
        AppHelpers.showSnackBar(
          context,
          AppHelpers.backendErrorMessage(
            e,
            fallback: 'نەتوانرا چاتی دارایی نوێ بکرێتەوە. دووبارە هەوڵ بدە.',
          ),
          isError: true,
        );
      }
    } finally {
      _financialRefreshInFlight = false;
      if (_financialRefreshPending && mounted) {
        final pendingAutoJump = _financialAutoJumpPending;
        _financialRefreshPending = false;
        _financialAutoJumpPending = false;
        Future<void>.delayed(const Duration(milliseconds: 80), () async {
          if (mounted) {
            await _refreshFinancialData(autoJump: pendingAutoJump);
          }
        });
      }
    }
  }

  void _jumpToLatest({bool animated = true}) {
    if (!mounted) return;
    if (_hasNewFinancialActivity) {
      setState(() => _hasNewFinancialActivity = false);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_profileScrollController.hasClients) return;
      final target = _profileScrollController.position.maxScrollExtent;
      if (animated) {
        unawaited(
          _profileScrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          ),
        );
      } else {
        _profileScrollController.jumpTo(target);
      }
    });
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
        controller: _profileScrollController,
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
      floatingActionButton: _isCustomer &&
              _customerSection == 1 &&
              _hasNewFinancialActivity
          ? FloatingActionButton.extended(
              onPressed: _jumpToLatest,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              label: const Text('مامەڵەی نوێ'),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: _isCustomer &&
              _customerSection == 1 &&
              auth.userRole != 'customer'
          ? _buildFinancialChatComposer(auth, isDark)
          : null,
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
    const labels = ['پوختە', 'چاتی دارایی', 'دەستکاری'];
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
                      if (index == 1) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _jumpToLatest(animated: false);
                        });
                      }
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
    final created = record.getStringValue('created');
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
      for (final event in _financialEvents)
        if (const <String>{
          'debt_updated',
          'debt_deleted',
          'payment_updated',
          'payment_deleted',
        }.contains(event.getStringValue('event_type')))
          _ProfileTimelineItem(
            kind: 'system',
            record: event,
            date: _timelineDate(event),
          ),
    ];

    // Oldest first gives a natural chat/timeline flow.
    items.sort((a, b) => a.date.compareTo(b.date));
    return items;
  }

  List<_ProfileTimelineItem> _filterFinancialTimeline(
    List<_ProfileTimelineItem> items,
  ) {
    final query = _financialSearchController.text.trim().toLowerCase();
    final range = _financialDateRange;

    return items.where((item) {
      if (_financialTypeFilter != 'all' && item.kind != _financialTypeFilter) {
        return false;
      }

      if (range != null) {
        final day = DateTime(item.date.year, item.date.month, item.date.day);
        final start = DateTime(
          range.start.year,
          range.start.month,
          range.start.day,
        );
        final end = DateTime(range.end.year, range.end.month, range.end.day);
        if (day.isBefore(start) || day.isAfter(end)) return false;
      }

      if (query.isEmpty) return true;
      final record = item.record;
      final searchable = <String>[
        item.kind,
        record.getStringValue('description'),
        record.getStringValue('note'),
        record.getStringValue('status'),
        record.getStringValue('event_type'),
        record.getStringValue('actor_name'),
        record.getStringValue('currency'),
        record.getDoubleValue('amount').toString(),
        DateFormat('yyyy/MM/dd HH:mm').format(item.date),
        if (item.relatedDebt != null)
          item.relatedDebt!.getStringValue('description'),
        if (item.relatedDebt != null)
          item.relatedDebt!.getDoubleValue('amount').toString(),
      ].join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList(growable: false);
  }

  Future<void> _pickFinancialDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _financialDateRange,
      helpText: 'فلتەری بەروار',
      cancelText: 'پاشگەزبوونەوە',
      confirmText: 'هەڵبژاردن',
      saveText: 'هەڵبژاردن',
    );
    if (!mounted || picked == null) return;
    setState(() => _financialDateRange = picked);
  }

  void _clearFinancialFilters() {
    if (_financialSearchController.text.isEmpty &&
        _financialDateRange == null &&
        _financialTypeFilter == 'all') {
      return;
    }
    _financialSearchController.clear();
    setState(() {
      _financialDateRange = null;
      _financialTypeFilter = 'all';
    });
  }

  Widget _buildFinancialChatTools({
    required double totalDebt,
    required double totalRemaining,
    required double totalPaid,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasFilters = _financialSearchController.text.trim().isNotEmpty ||
        _financialDateRange != null ||
        _financialTypeFilter != 'all';
    final dateLabel = _financialDateRange == null
        ? 'بەروار'
        : '${DateFormat('yyyy/MM/dd').format(_financialDateRange!.start)} — '
            '${DateFormat('yyyy/MM/dd').format(_financialDateRange!.end)}';

    Widget typeChip(String value, String label, IconData icon) {
      final selected = _financialTypeFilter == value;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 7),
        child: ChoiceChip(
          selected: selected,
          onSelected: (_) => setState(() => _financialTypeFilter = value),
          avatar: Icon(
            icon,
            size: 15,
            color: selected
                ? AppColors.primary
                : (isDark
                    ? AppDarkColors.textSecondary
                    : const Color(0xFF667085)),
          ),
          label: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          visualDensity: VisualDensity.compact,
          side: BorderSide(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.28)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFE4E7EC)),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _financialSearchController,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'گەڕان لە قەرز، پارەدانەوە، بڕ یان تێبینی...',
            prefixIcon: const Icon(Icons.search_rounded, size: 19),
            suffixIcon: _financialSearchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'سڕینەوەی گەڕان',
                    onPressed: () {
                      _financialSearchController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
            isDense: true,
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : const Color(0xFFE4E7EC),
              ),
            ),
          ),
        ),
        const SizedBox(height: 9),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              typeChip('all', 'هەموو', Icons.all_inclusive_rounded),
              typeChip('debt', 'قەرز', Icons.north_east_rounded),
              typeChip('payment', 'پارەدانەوە', Icons.south_west_rounded),
              typeChip('system', 'مێژووی گۆڕانکاری', Icons.history_rounded),
            ],
          ),
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickFinancialDateRange,
                icon: const Icon(Icons.date_range_outlined, size: 17),
                label: Text(
                  dateLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(42),
                  textStyle: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _generateAccountStatement(
                  totalDebt: totalDebt,
                  totalRemaining: totalRemaining,
                  totalPaid: totalPaid,
                ),
                icon: const Icon(Icons.ios_share_rounded, size: 17),
                label: const Text('کەشف / هاوبەشکردن'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(42),
                  textStyle: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (hasFilters) ...[
              const SizedBox(width: 5),
              IconButton(
                tooltip: 'پاککردنەوەی فلتەرەکان',
                onPressed: _clearFinancialFilters,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 19),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildFilteredTimelineEmptyState(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
            Icons.search_off_rounded,
            size: 30,
            color: isDark ? AppDarkColors.textSecondary : Colors.grey[400],
          ),
          const SizedBox(height: 8),
          Text(
            'هیچ مامەڵەیەک لەم گەڕان/فلتەرەدا نەدۆزرایەوە',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isDark
                  ? AppDarkColors.textPrimary
                  : const Color(0xFF344054),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _clearFinancialFilters,
            icon: const Icon(Icons.restart_alt_rounded, size: 17),
            label: const Text('هەموو مامەڵەکان پیشان بدە'),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerChatTimelineCard({
    required double totalDebt,
    required double totalRemaining,
    required double totalPaid,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allTimelineItems = _buildTimelineItems();
    final timelineItems = _filterFinancialTimeline(allTimelineItems);
    final health = _debtHealth(totalRemaining, totalDebt);

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: isDark ? AppDarkColors.card : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFE7ECF3),
                ),
              ),
              child: Column(
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
                        child: const Icon(
                          Icons.forum_outlined,
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
                              'چاتی دارایی',
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
                              '${timelineItems.length}/${allTimelineItems.length} مامەڵە • قەرز و پارەدانەوە لە یەک مێژوودا',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: isDark
                                    ? AppDarkColors.textSecondary
                                    : const Color(0xFF98A2B3),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'نوێکردنەوە',
                        onPressed: _financialRefreshInFlight
                            ? null
                            : () => _refreshFinancialData(showError: true),
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildChatSummaryValue(
                        label: 'قەرز',
                        value: totalDebt,
                        color: Colors.orange,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 7),
                      _buildChatSummaryValue(
                        label: 'دراوە',
                        value: totalPaid,
                        color: Colors.green,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 7),
                      _buildChatSummaryValue(
                        label: 'ماوە',
                        value: totalRemaining,
                        color: totalRemaining > 0 ? Colors.red : Colors.green,
                        isDark: isDark,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildFinancialChatTools(
                    totalDebt: totalDebt,
                    totalRemaining: totalRemaining,
                    totalPaid: totalPaid,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            _buildDebtHealthStrip(
              label: health.$1,
              color: health.$2,
              totalRemaining: totalRemaining,
              totalPaid: totalPaid,
            ),
            const SizedBox(height: 12),
            if (timelineItems.isEmpty)
              allTimelineItems.isEmpty
                  ? _buildEmptyTimelineState(isDark)
                  : _buildFilteredTimelineEmptyState(isDark)
            else
              ..._buildFinancialChatMessages(timelineItems),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildChatSummaryValue({
    required String label,
    required double value,
    required Color color,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.10 : 0.07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: isDark
                    ? AppDarkColors.textSecondary
                    : const Color(0xFF667085),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              AppHelpers.formatCurrency(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFinancialChatMessages(
    List<_ProfileTimelineItem> timelineItems,
  ) {
    final widgets = <Widget>[];
    DateTime? previousDay;

    for (var index = 0; index < timelineItems.length; index++) {
      final item = timelineItems[index];
      final day = DateTime(item.date.year, item.date.month, item.date.day);
      if (previousDay == null || day != previousDay) {
        widgets.add(_buildChatDaySeparator(item.date));
        previousDay = day;
      }
      widgets.add(
        item.isSystem
            ? _buildFinancialSystemMessage(item)
            : _buildTimelineBubble(item, index),
      );
    }
    return widgets;
  }

  Widget _buildChatDaySeparator(DateTime date) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : const Color(0xFFE4E7EC),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              AppHelpers.formatDate(date.toIso8601String()),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppDarkColors.textSecondary
                    : const Color(0xFF98A2B3),
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : const Color(0xFFE4E7EC),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialSystemMessage(_ProfileTimelineItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final record = item.record;
    final type = record.getStringValue('event_type');
    final actor = record.getStringValue('actor_name').trim();
    final amount = record.getDoubleValue('amount');
    final currency = record.getStringValue('currency').isEmpty
        ? 'IQD'
        : record.getStringValue('currency');
    final amountText = amount > 0
        ? AppHelpers.formatCurrencyWithType(amount, currency)
        : '';

    final (icon, message) = switch (type) {
      'debt_deleted' => (
          Icons.delete_outline_rounded,
          amountText.isEmpty ? 'قەرزێک سڕایەوە' : 'قەرزی $amountText سڕایەوە',
        ),
      'payment_updated' => (
          Icons.edit_note_rounded,
          'پارەدانەوە دەستکاری کرا',
        ),
      'payment_deleted' => (
          Icons.remove_circle_outline_rounded,
          amountText.isEmpty
              ? 'پارەدانەوەیەک سڕایەوە'
              : 'پارەدانەوەی $amountText سڕایەوە',
        ),
      _ => (Icons.edit_outlined, 'قەرز دەستکاری کرا'),
    };

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 18),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.055)
              : const Color(0xFFF2F4F7),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isDark
                  ? AppDarkColors.textSecondary
                  : const Color(0xFF667085),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                actor.isEmpty ? message : '$message • $actor',
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppDarkColors.textSecondary
                      : const Color(0xFF667085),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              DateFormat('HH:mm').format(item.date),
              style: TextStyle(
                fontSize: 9.5,
                color: isDark
                    ? AppDarkColors.textSecondary
                    : const Color(0xFF98A2B3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialChatComposer(AuthProvider auth, bool isDark) {
    final totalRemaining = _debts.fold<double>(
      0,
      (sum, debt) => sum + debt.getDoubleValue('remaining'),
    );
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        decoration: BoxDecoration(
          color: isDark ? AppDarkColors.card : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : const Color(0xFFE4E7EC),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _openAddDebtFromChat(),
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('قەرز زیاد بکە'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: totalRemaining > 0
                    ? () => _showFinancialPaymentSheet(auth)
                    : null,
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('پارەدانەوە'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  foregroundColor: Colors.green.shade700,
                  side: BorderSide(
                    color: totalRemaining > 0
                        ? Colors.green.withValues(alpha: 0.32)
                        : const Color(0xFFD0D5DD),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddDebtFromChat() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddDebtScreen(customerId: widget.userId),
      ),
    );
    if (result == true && mounted) {
      await _refreshFinancialData(autoJump: true);
    }
  }

  Future<void> _openTimelineItem(_ProfileTimelineItem item) async {
    final debtId = item.isPayment
        ? item.record.getStringValue('debt')
        : item.record.id;
    if (debtId.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DebtDetailScreen(debtId: debtId)),
    );
    if (mounted) await _refreshFinancialData();
  }

  Future<void> _showFinancialPaymentSheet(AuthProvider auth) async {
    final openDebts = _debts
        .where((debt) => debt.getDoubleValue('remaining') > 0)
        .toList()
      ..sort((a, b) => _timelineDate(a).compareTo(_timelineDate(b)));
    if (openDebts.isEmpty) {
      AppHelpers.showSnackBar(context, 'هیچ قەرزێکی ماوە نییە');
      return;
    }

    final amountController = TextEditingController();
    final noteController = TextEditingController();
    var selectedDebtId = openDebts.first.id;
    var saving = false;
    String? localError;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              final sheetDark =
                  Theme.of(sheetContext).brightness == Brightness.dark;
              final selectedDebt = openDebts.firstWhere(
                (debt) => debt.id == selectedDebtId,
                orElse: () => openDebts.first,
              );
              final remaining = selectedDebt.getDoubleValue('remaining');
              return Container(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
                ),
                decoration: BoxDecoration(
                  color: sheetDark ? AppDarkColors.card : Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD0D5DD),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'تۆمارکردنی پارەدانەوە',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'قەرز هەڵبژێرە و بڕی پارەدانەوە بنووسە.',
                        style: TextStyle(
                          fontSize: 12,
                          color: sheetDark
                              ? AppDarkColors.textSecondary
                              : const Color(0xFF667085),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedDebtId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'قەرز',
                          border: OutlineInputBorder(),
                        ),
                        items: openDebts.map((debt) {
                          final description =
                              debt.getStringValue('description').trim();
                          final balance = debt.getDoubleValue('remaining');
                          return DropdownMenuItem<String>(
                            value: debt.id,
                            child: Text(
                              description.isEmpty
                                  ? 'ماوە: ${AppHelpers.formatCurrency(balance)}'
                                  : '$description • ${AppHelpers.formatCurrency(balance)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value == null) return;
                                setSheetState(() {
                                  selectedDebtId = value;
                                  localError = null;
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: amountController,
                        enabled: !saving,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: 'بڕی پارەدانەوە',
                          helperText:
                              'ماوە: ${AppHelpers.formatCurrency(remaining)}',
                          prefixIcon: const Icon(Icons.payments_outlined),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: noteController,
                        enabled: !saving,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'تێبینی (ئارەزوومەندانە)',
                          prefixIcon: Icon(Icons.notes_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (localError != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          localError!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: saving
                            ? null
                            : () async {
                                final normalized = amountController.text
                                    .trim()
                                    .replaceAll(',', '');
                                final amount = double.tryParse(normalized) ?? 0;
                                if (amount <= 0) {
                                  setSheetState(() => localError =
                                      'بڕێکی دروستی پارەدانەوە بنووسە.');
                                  return;
                                }
                                if (amount > remaining) {
                                  setSheetState(() => localError =
                                      'بڕی پارەدانەوە نابێت لە ماوەی قەرز زیاتر بێت.');
                                  return;
                                }

                                setSheetState(() {
                                  saving = true;
                                  localError = null;
                                });
                                try {
                                  await PBService.createPayment(
                                    debtId: selectedDebtId,
                                    amount: amount,
                                    note: noteController.text.trim(),
                                    createdBy: auth.userId,
                                    createdByName: auth.userName,
                                  );
                                  if (!sheetContext.mounted) return;
                                  Navigator.pop(sheetContext);
                                  if (!mounted) return;
                                  AppHelpers.showSnackBar(
                                    context,
                                    'پارەدانەوە بە سەرکەوتوویی تۆمارکرا',
                                  );
                                  await _refreshFinancialData(autoJump: true);
                                } catch (e) {
                                  if (!sheetContext.mounted) return;
                                  setSheetState(() {
                                    saving = false;
                                    localError = AppHelpers.backendErrorMessage(
                                      e,
                                      fallback:
                                          'پارەدانەوە تۆمار نەکرا. دووبارە هەوڵ بدە.',
                                    );
                                  });
                                }
                              },
                        icon: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(saving ? 'تۆمار دەکرێت...' : 'تۆمارکردن'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: Colors.green.shade700,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      amountController.dispose();
      noteController.dispose();
    }
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
        ? record.getStringValue('note').trim()
        : record.getStringValue('description').trim();
    final status = isPayment ? '' : record.getStringValue('status');
    final color = isPayment ? Colors.green.shade700 : Colors.orange.shade800;
    final background = color.withValues(alpha: isDark ? 0.16 : 0.09);
    final formattedAmount = AppHelpers.formatCurrencyWithType(
      amount,
      currency,
      dollarRate: dollarRate,
      showConversion: currency == 'USD',
    );
    final receiptPath = isPayment ? '' : record.getStringValue('receipt_image');

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 160 + (index * 18).clamp(0, 220)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset((isPayment ? -8 : 8) * (1 - value), 0),
          child: child,
        ),
      ),
      child: Align(
        alignment: isPayment ? Alignment.centerLeft : Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.80,
            minWidth: 180,
          ),
          child: Material(
            color: background,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(17),
              topRight: const Radius.circular(17),
              bottomLeft: Radius.circular(isPayment ? 5 : 17),
              bottomRight: Radius.circular(isPayment ? 17 : 5),
            ),
            child: InkWell(
              onTap: () => _showFinancialTransactionActions(item),
              onLongPress: () => _showFinancialTransactionActions(item),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(17),
                topRight: const Radius.circular(17),
                bottomLeft: Radius.circular(isPayment ? 5 : 17),
                bottomRight: Radius.circular(isPayment ? 17 : 5),
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
                decoration: BoxDecoration(
                  border: Border.all(color: color.withValues(alpha: 0.16)),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(17),
                    topRight: const Radius.circular(17),
                    bottomLeft: Radius.circular(isPayment ? 5 : 17),
                    bottomRight: Radius.circular(isPayment ? 17 : 5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isPayment
                                ? Icons.south_west_rounded
                                : Icons.north_east_rounded,
                            size: 15,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isPayment ? 'پارەدانەوە' : 'قەرز',
                            style: TextStyle(
                              color: isDark
                                  ? AppDarkColors.textPrimary
                                  : const Color(0xFF1D2939),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (!isPayment && status.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              AppHelpers.statusName(status),
                              style: TextStyle(
                                color: color,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${isPayment ? '−' : '+'} $formattedAmount',
                      textDirection: TextDirection.ltr,
                      textAlign: isPayment ? TextAlign.left : TextAlign.right,
                      style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark
                              ? AppDarkColors.textSecondary
                              : const Color(0xFF475467),
                          fontSize: 11.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                    if (isPayment && relatedDebt != null) ...[
                      const SizedBox(height: 7),
                      _buildPaymentDebtReference(relatedDebt, color, isDark),
                    ],
                    if (!isPayment && receiptPath.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildReceiptPreview(record, receiptPath, color, isDark),
                    ],
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        if (receiptPath.isNotEmpty) ...[
                          Icon(
                            Icons.receipt_outlined,
                            size: 13,
                            color: color.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'وەصڵ',
                            style: TextStyle(
                              color: color,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          DateFormat('HH:mm').format(item.date),
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            color: isDark
                                ? AppDarkColors.textSecondary
                                : const Color(0xFF98A2B3),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 14,
                          color: isDark
                              ? AppDarkColors.textSecondary
                              : const Color(0xFF98A2B3),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentDebtReference(
    RecordModel debt,
    Color accent,
    bool isDark,
  ) {
    final description = debt.getStringValue('description').trim();
    final currency = debt.getStringValue('currency').isEmpty
        ? 'IQD'
        : debt.getStringValue('currency');
    final amount = debt.getDoubleValue('amount');
    final amountText = AppHelpers.formatCurrencyWithType(
      amount,
      currency,
      dollarRate: debt.getDoubleValue('dollar_rate'),
      showConversion: currency == 'USD',
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        border: BorderDirectional(
          start: BorderSide(color: accent, width: 2.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.reply_rounded, size: 14, color: accent),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'پەیوەست بە قەرز',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description.isEmpty ? amountText : '$description • $amountText',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : const Color(0xFF667085),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptPreview(
    RecordModel debt,
    String receiptPath,
    Color accent,
    bool isDark,
  ) {
    final imageUrl = PBService.pb.getFileUrl(debt, receiptPath).toString();
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: Container(
        height: 88,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : const Color(0xFFF2F4F7),
          border: Border.all(color: accent.withValues(alpha: 0.14)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) => Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_outlined, size: 17, color: accent),
                    const SizedBox(width: 5),
                    Text(
                      'وێنەی وەصڵ بەردەست نییە',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            PositionedDirectional(
              end: 7,
              bottom: 7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'وەصڵ',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFinancialTransactionActions(
    _ProfileTimelineItem item,
  ) async {
    if (item.isSystem || !mounted) return;

    final debt = item.isPayment ? item.relatedDebt : item.record;
    final receiptPath = debt?.getStringValue('receipt_image').trim() ?? '';
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final amount = item.record.getDoubleValue('amount');
        final currency = debt?.getStringValue('currency').isNotEmpty == true
            ? debt!.getStringValue('currency')
            : 'IQD';
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppDarkColors.card : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD0D5DD),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                leading: CircleAvatar(
                  backgroundColor: (item.isPayment ? Colors.green : Colors.orange)
                      .withValues(alpha: 0.10),
                  child: Icon(
                    item.isPayment
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                    color: item.isPayment ? Colors.green.shade700 : Colors.orange.shade800,
                    size: 19,
                  ),
                ),
                title: Text(
                  item.isPayment ? 'پارەدانەوە' : 'قەرز',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  AppHelpers.formatCurrencyWithType(amount, currency),
                  textDirection: TextDirection.ltr,
                ),
              ),
              const Divider(height: 12),
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('وردەکاری مامەڵە'),
                onTap: () => Navigator.pop(sheetContext, 'details'),
              ),
              if (receiptPath.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('بینینی وەصڵ'),
                  subtitle: const Text('گەورەکردن و جوڵاندنی وێنە'),
                  onTap: () => Navigator.pop(sheetContext, 'receipt'),
                ),
              if (debt != null)
                ListTile(
                  leading: const Icon(Icons.print_outlined),
                  title: const Text('چاپکردنی وەصڵ / Invoice'),
                  onTap: () => Navigator.pop(sheetContext, 'invoice'),
                ),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('کەشف حیساب'),
                onTap: () => Navigator.pop(sheetContext, 'statement'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'details':
        await _openTimelineItem(item);
        break;
      case 'receipt':
        if (debt != null && receiptPath.isNotEmpty) {
          await _openFinancialReceiptViewer(debt, receiptPath);
        }
        break;
      case 'invoice':
        if (debt != null) await _generateFinancialInvoice(debt);
        break;
      case 'statement':
        await _generateCurrentFinancialStatement();
        break;
    }
  }

  Future<void> _openFinancialReceiptViewer(
    RecordModel debt,
    String receiptPath,
  ) async {
    if (!mounted || receiptPath.isEmpty) return;
    final imageUrl = PBService.pb.getFileUrl(debt, receiptPath).toString();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (viewerContext) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            title: const Text('وەصڵ'),
          ),
          body: SafeArea(
            child: Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                boundaryMargin: const EdgeInsets.all(48),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const SizedBox(
                      width: 42,
                      height: 42,
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'وێنەی وەصڵ بار نەبوو. پەیوەندی ئینتەرنێت بپشکنە.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _generateFinancialInvoice(RecordModel debt) async {
    final auth = context.read<AuthProvider>();
    try {
      await PdfService.generateInvoice(
        debt: debt,
        marketName: auth.marketName,
        adminName: auth.userName,
        adminPhone: auth.user?.getStringValue('phone') ?? '',
      );
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'وەصڵ دروست نەکرا. دووبارە هەوڵ بدە.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _generateCurrentFinancialStatement() async {
    final totalDebt = _debts.fold<double>(
      0,
      (sum, debt) => sum + debt.getDoubleValue('amount'),
    );
    final totalRemaining = _debts.fold<double>(
      0,
      (sum, debt) => sum + debt.getDoubleValue('remaining'),
    );
    await _generateAccountStatement(
      totalDebt: totalDebt,
      totalRemaining: totalRemaining,
      totalPaid: totalDebt - totalRemaining,
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
                  if (!mounted || !dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  AppHelpers.showSnackBar(context, 'سنوری قەرز لابرا');
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
                      ? 'سنوری قەرز دانرا: ${AppHelpers.formatCurrency(newLimit)}'
                      : 'سنوری قەرز لابرا',
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

    if (!mounted) return;
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
      builder: (dialogContext) => AlertDialog(
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
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('پاشگەزبوونەوە'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              final senderId = context.read<AuthProvider>().userId;
              try {
                await PBService.createNotification(
                  customerId: widget.userId,
                  message: controller.text.trim(),
                  senderId: senderId,
                );
                if (!mounted || !dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                AppHelpers.showSnackBar(context, 'ئاگادارکردنەوە نێردرا');
              } catch (e) {
                if (!mounted) return;
                AppHelpers.showSnackBar(
                  context,
                  AppHelpers.backendErrorMessage(e),
                  isError: true,
                );
              }
            },
            child: const Text('ناردن'),
          ),
        ],
      ),
    );
  }
}
