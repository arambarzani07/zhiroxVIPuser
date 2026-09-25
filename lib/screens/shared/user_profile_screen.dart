import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/shared/add_debt_screen.dart';
import 'package:zhirox/screens/shared/debt_detail_screen.dart';
import 'package:zhirox/screens/shared/financial_payment_flow.dart';
import 'package:zhirox/screens/shared/customer_period_statement_screen.dart';
import 'package:zhirox/screens/shared/financial_document_actions.dart';

import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/services/customer_push_service.dart';
import 'package:zhirox/services/financial_date_range_summary.dart';
import 'package:zhirox/services/financial_ui_state.dart';
import 'package:zhirox/services/pdf_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:zhirox/providers/theme_provider.dart';
import 'package:zhirox/services/connectivity_service.dart';
import 'package:zhirox/widgets/customer_push_card.dart';

part 'user_profile_financial_chat.dart';
part 'user_profile_employee_management.dart';
part 'user_profile_account_management.dart';

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
  bool get isGeneralPayment =>
      isPayment && record.getStringValue('payment_scope') == 'general';
  bool get isSystem => kind == 'system';
}

class _FinancialChatRenderEntry {
  final _ProfileTimelineItem? item;
  final DateTime? separatorDate;
  final int timelineIndex;

  const _FinancialChatRenderEntry.item(
    _ProfileTimelineItem this.item,
    this.timelineIndex,
  ) : separatorDate = null;

  const _FinancialChatRenderEntry.separator(
    DateTime this.separatorDate,
    this.timelineIndex,
  ) : item = null;

  bool get isSeparator => separatorDate != null;
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  RecordModel? _user;
  // Timeline records contain only server pages already loaded into Financial Chat.
  List<RecordModel> _debts = [];
  List<RecordModel> _payments = [];
  List<RecordModel> _financialEvents = [];
  // Payment actions need all currently-open debts, not the historical timeline.
  List<RecordModel> _openDebts = [];
  double _financeTotalDebtIqd = 0;
  double _financeTotalRemainingIqd = 0;
  double _financeTotalPaidIqd = 0;
  bool _financeSummaryComplete = false;
  bool _financialTimelineHasMore = false;
  Map<String, dynamic>? _financialTimelineCursor;
  bool _financialHistoryLoading = false;
  bool _financialFilterHydrating = false;
  String? _financialHistoryError;
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
  bool _financialFiltersExpanded = false;
  _ProfileTimelineItem? _financialReplyTarget;

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
  Timer? _financialSearchDebounce;

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
    _financialSearchDebounce?.cancel();
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

  void _setProfileState(VoidCallback update) => setState(update);

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
      List<RecordModel> openDebts = [];
      var totalDebtIqd = 0.0;
      var totalRemainingIqd = 0.0;
      var totalPaidIqd = 0.0;
      var summaryComplete = false;
      var timelineHasMore = false;
      Map<String, dynamic>? timelineCursor;
      Map<String, double> employeeStats = {};

      if (role == 'customer') {
        final customerData = await Future.wait<Map<String, dynamic>>([
          PBService.getCustomerFinanceSnapshot(widget.userId),
          PBService.getCustomerFinancialTimelinePage(
            customerId: widget.userId,
            limit: 50,
          ),
        ]);
        final snapshot = customerData[0];
        final page = customerData[1];
        debts = List<RecordModel>.from(page['debts'] as List? ?? const []);
        payments = List<RecordModel>.from(page['payments'] as List? ?? const []);
        financialEvents = List<RecordModel>.from(
          page['financialEvents'] as List? ?? const [],
        );
        openDebts = List<RecordModel>.from(
          snapshot['openDebts'] as List? ?? const [],
        );
        totalDebtIqd = (snapshot['totalDebtIqd'] as num?)?.toDouble() ?? 0;
        totalRemainingIqd =
            (snapshot['totalRemainingIqd'] as num?)?.toDouble() ?? 0;
        totalPaidIqd = (snapshot['totalPaidIqd'] as num?)?.toDouble() ?? 0;
        summaryComplete = snapshot['complete'] == true;
        timelineHasMore = page['hasMore'] == true;
        timelineCursor = page['nextCursor'] is Map
            ? Map<String, dynamic>.from(page['nextCursor'] as Map)
            : null;
      } else if (role == 'employee') {
        employeeStats = await PBService.getEmployeeStats(widget.userId);
      }

      if (!mounted) return;
      setState(() {
        _user = user;
        _debts = debts;
        _payments = payments;
        _financialEvents = financialEvents;
        _openDebts = openDebts;
        _financeTotalDebtIqd = totalDebtIqd;
        _financeTotalRemainingIqd = totalRemainingIqd;
        _financeTotalPaidIqd = totalPaidIqd;
        _financeSummaryComplete = summaryComplete;
        _financialTimelineHasMore = timelineHasMore;
        _financialTimelineCursor = timelineCursor;
        _financialHistoryError = null;
        _financialHistoryLoading = false;
        _financialFilterHydrating = false;
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
        _openDebts = [];
        _financeTotalDebtIqd = 0;
        _financeTotalRemainingIqd = 0;
        _financeTotalPaidIqd = 0;
        _financeSummaryComplete = false;
        _financialTimelineHasMore = false;
        _financialTimelineCursor = null;
        _financialHistoryError = null;
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
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'customer_general_payments',
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
      final customerData = await Future.wait<Map<String, dynamic>>([
        PBService.getCustomerFinanceSnapshot(widget.userId),
        PBService.getCustomerFinancialTimelinePage(
          customerId: widget.userId,
          limit: 50,
        ),
      ]);
      final snapshot = customerData[0];
      final page = customerData[1];
      if (!mounted) return;
      setState(() {
        _debts = List<RecordModel>.from(page['debts'] as List? ?? const []);
        _payments = List<RecordModel>.from(page['payments'] as List? ?? const []);
        _financialEvents = List<RecordModel>.from(
          page['financialEvents'] as List? ?? const [],
        );
        _openDebts = List<RecordModel>.from(
          snapshot['openDebts'] as List? ?? const [],
        );
        _financeTotalDebtIqd =
            (snapshot['totalDebtIqd'] as num?)?.toDouble() ?? 0;
        _financeTotalRemainingIqd =
            (snapshot['totalRemainingIqd'] as num?)?.toDouble() ?? 0;
        _financeTotalPaidIqd =
            (snapshot['totalPaidIqd'] as num?)?.toDouble() ?? 0;
        _financeSummaryComplete = snapshot['complete'] == true;
        _financialTimelineHasMore = page['hasMore'] == true;
        _financialTimelineCursor = page['nextCursor'] is Map
            ? Map<String, dynamic>.from(page['nextCursor'] as Map)
            : null;
        _financialHistoryError = null;
      });
      if (_hasFinancialFilters && _financialTimelineHasMore) {
        unawaited(_hydrateFinancialHistoryForFilters());
      }
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

  List<RecordModel> _mergeFinancialRecords(
    List<RecordModel> current,
    List<RecordModel> incoming,
  ) {
    final byId = <String, RecordModel>{for (final item in current) item.id: item};
    for (final item in incoming) {
      byId[item.id] = item;
    }
    return byId.values.toList(growable: false);
  }

  Future<bool> _loadOlderFinancialHistory({
    bool preserveScroll = true,
    bool showError = true,
  }) async {
    if (!mounted || !_financialTimelineHasMore) return true;
    if (_financialHistoryLoading || _financialTimelineCursor == null) return false;

    final hadScroll = preserveScroll && _profileScrollController.hasClients;
    final oldPixels = hadScroll ? _profileScrollController.position.pixels : 0.0;
    final oldMax = hadScroll ? _profileScrollController.position.maxScrollExtent : 0.0;
    setState(() {
      _financialHistoryLoading = true;
      _financialHistoryError = null;
    });

    try {
      final page = await PBService.getCustomerFinancialTimelinePage(
        customerId: widget.userId,
        limit: 50,
        cursor: _financialTimelineCursor,
      );
      if (!mounted) return false;
      setState(() {
        _debts = _mergeFinancialRecords(
          _debts,
          List<RecordModel>.from(page['debts'] as List? ?? const []),
        );
        _payments = _mergeFinancialRecords(
          _payments,
          List<RecordModel>.from(page['payments'] as List? ?? const []),
        );
        _financialEvents = _mergeFinancialRecords(
          _financialEvents,
          List<RecordModel>.from(page['financialEvents'] as List? ?? const []),
        );
        _financialTimelineHasMore = page['hasMore'] == true;
        _financialTimelineCursor = page['nextCursor'] is Map
            ? Map<String, dynamic>.from(page['nextCursor'] as Map)
            : null;
        _financialHistoryError = null;
      });

      if (hadScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_profileScrollController.hasClients) return;
          final position = _profileScrollController.position;
          final delta = position.maxScrollExtent - oldMax;
          final target = (oldPixels + delta)
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble();
          _profileScrollController.jumpTo(target);
        });
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      final message = AppHelpers.backendErrorMessage(
        e,
        fallback: 'نەتوانرا مامەڵە کۆنەکان باربکرێن. دووبارە هەوڵ بدە.',
      );
      setState(() => _financialHistoryError = message);
      if (showError) {
        AppHelpers.showSnackBar(context, message, isError: true);
      }
      return false;
    } finally {
      if (mounted) setState(() => _financialHistoryLoading = false);
    }
  }

  Future<bool> _ensureAllFinancialHistoryLoaded({
    bool showError = true,
  }) async {
    var pages = 0;
    while (mounted && _financialTimelineHasMore) {
      if (pages++ > 10000) return false;
      final loaded = await _loadOlderFinancialHistory(
        preserveScroll: false,
        showError: showError,
      );
      if (!loaded) return false;
    }
    return mounted;
  }

  bool get _hasFinancialFilters =>
      _financialSearchController.text.trim().isNotEmpty ||
      _financialDateRange != null ||
      _financialTypeFilter != 'all';

  void _scheduleFinancialSearchHydration() {
    _financialSearchDebounce?.cancel();
    if (!mounted || !_hasFinancialFilters || !_financialTimelineHasMore) return;
    _financialSearchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      unawaited(_hydrateFinancialHistoryForFilters());
    });
  }

  Future<void> _hydrateFinancialHistoryForFilters() async {
    if (!mounted || !_hasFinancialFilters || !_financialTimelineHasMore) return;
    if (_financialFilterHydrating) return;
    setState(() {
      _financialFilterHydrating = true;
      _financialHistoryError = null;
    });
    try {
      await _ensureAllFinancialHistoryLoaded(showError: false);
    } finally {
      if (mounted) setState(() => _financialFilterHydrating = false);
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
                                if (value == 'read_link' || value == 'revoke_link') {
                                  await _manageReadLink(revoke: value == 'revoke_link');
                                  return;
                                }
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
                                if (_isCustomer && auth.userRole == 'admin') ...[
                                  const PopupMenuItem<String>(
                                    value: 'read_link',
                                    child: Text('لینکی خوێندنەوەی کڕیار'),
                                  ),
                                  const PopupMenuItem<String>(
                                    value: 'revoke_link',
                                    child: Text('ڕاگرتنی لینکی کڕیار'),
                                  ),
                                ],
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
    final totalDebt = _financeTotalDebtIqd;
    final totalRemaining = _financeTotalRemainingIqd;
    final totalPaid = _financeTotalPaidIqd;
    final totalsComplete = _financeSummaryComplete;
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
                totalsComplete ? AppHelpers.formatCurrency(totalDebt) : '—',
                Colors.orange,
              ),
              const SizedBox(width: 10),
              _buildStatChip(
                Icons.pending_outlined,
                'ماوە',
                totalsComplete ? AppHelpers.formatCurrency(totalRemaining) : '—',
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
              onPressed: totalsComplete
                  ? _generateCurrentFinancialStatement
                  : _showIncompleteCurrencySummaryMessage,
              icon: const Icon(Icons.receipt_long_rounded, size: 19),
              label: const Text('کەشفی گشتی'),
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
      if (auth.canViewDebts)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: FilledButton.icon(
              onPressed: _openPeriodStatement,
              icon: const Icon(Icons.date_range_rounded, size: 19),
              label: const Text('کەشفی حیسابی ماوە'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: _accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
      if (!totalsComplete) _buildCurrencySummaryWarning(),
      _buildDebtLimitCard(),
      if (auth.canSendNotifications)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: CustomerPushCard(customerId: widget.userId),
          ),
        ),
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
  // ── Customer Chat Timeline ──  // Employee management UI/actions live in user_profile_employee_management.dart.


  // ═══════════════════════════════════════════

  // Password/profile/debt-limit management lives in user_profile_account_management.dart.

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

  Future<void> _manageReadLink({required bool revoke}) async {
    final confirmed = await AppHelpers.showConfirmDialog(
      context,
      title: revoke ? 'ڕاگرتنی لینکی کڕیار' : 'لینکی کڕیار',
      message: revoke
          ? 'هەموو لینک و ئامێرە پەیوەستکراوەکانی ئەم کڕیارە ڕادەگیرێن. دڵنیایت؟'
          : 'لینکەکە لە push.zhirox.com دەکرێتەوە و هەژماری کڕیار، ئاگادارکردنەوە و پسووڵەکان لە هەمان پۆرتالدا پیشان دەدرێن.',
    );
    if (!confirmed || !mounted) return;

    const gateway = CustomerPushService();
    try {
      if (revoke) {
        await gateway.revokeAll(widget.userId);
        if (mounted) {
          AppHelpers.showSnackBar(
            context,
            'هەموو لینک و ئامێرەکانی کڕیار ڕاگیران',
          );
        }
        return;
      }

      final link = await gateway.createLink(widget.userId);
      final url = link.url.toString();
      if (!url.startsWith('https://push.zhirox.com/')) {
        throw const FormatException('unexpected customer portal host');
      }
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('لینکی تایبەتی کڕیار'),
          content: SelectableText(url, textDirection: TextDirection.ltr),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('داخستن'),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                if (mounted) {
                  AppHelpers.showSnackBar(context, 'لینکی push.zhirox.com کۆپی کرا');
                }
              },
              child: const Text('کۆپیکردنی لینک'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          'نەتوانرا لینکی push.zhirox.com ئامادە بکرێت. دووبارە هەوڵ بدە.',
          isError: true,
        );
      }
    }
  }

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