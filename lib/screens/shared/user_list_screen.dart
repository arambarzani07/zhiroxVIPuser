import 'package:flutter/material.dart';
import 'dart:async';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/shared/user_profile_screen.dart';
import 'package:zhirox/screens/shared/add_user_screen.dart';
import 'package:zhirox/screens/shared/add_debt_screen.dart';
import 'package:zhirox/screens/shared/financial_payment_flow.dart';
import 'package:zhirox/services/pdf_service.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/services/user_list_layout.dart';
import 'package:zhirox/features/customers/customer_directory_controller.dart';
import 'package:zhirox/features/customers/customer_center_widgets.dart';
import 'package:zhirox/widgets/app_async_state.dart';

class UserListScreen extends StatefulWidget {
  final String role;
  final String? adminId;

  const UserListScreen({super.key, required this.role, this.adminId});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  late final CustomerDirectoryController _directory;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    final resolvedAdminId =
        widget.adminId?.trim().isNotEmpty == true ? widget.adminId!.trim() : auth.adminId;
    _directory = CustomerDirectoryController(
      role: widget.role,
      adminId: resolvedAdminId,
    )..addListener(_onDirectoryChanged);
    _scrollController.addListener(_onScroll);
    unawaited(_directory.initialize());
  }

  @override
  void dispose() {
    _directory.removeListener(_onDirectoryChanged);
    _directory.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isEmployee => widget.role == 'employee';

  void _onDirectoryChanged() {
    if (mounted) setState(() {});
  }

  List<RecordModel> get _users => _directory.users;
  bool get _isLoading => _directory.isLoading;
  bool get _isLoadingMore => _directory.isLoadingMore;
  String? get _loadError => _directory.loadError;
  String? get _inboxError => _directory.inboxError;
  Map<String, double> get _balances => _directory.balances;
  Set<String> get _balanceErrors => _directory.balanceErrors;
  Map<String, Map<String, dynamic>> get _customerInbox => _directory.inbox;
  bool get _hasMoreUsers => _directory.hasMore;
  int get _totalUsers => _directory.totalUsers;
  String get _customerFilter => _directory.filter;

  void _onScroll() {
    if (widget.role != 'customer' ||
        !_hasMoreUsers ||
        _isLoadingMore ||
        !_scrollController.hasClients) {
      return;
    }
    if (_scrollController.position.extentAfter < 500) {
      unawaited(_directory.loadMore());
    }
  }

  Future<void> _loadUsers({String? search, bool loadMore = false}) {
    return _directory.load(
      search: search ?? _searchController.text.trim(),
      loadMore: loadMore,
    );
  }

  void _scheduleCustomerSearch(String value) {
    _directory.scheduleSearch(value);
  }

  void _selectCustomerFilter(String value) {
    unawaited(_directory.selectFilter(value));
  }

  String _inboxTimeLabel(Map<String, dynamic>? row) {
    final parsed = DateTime.tryParse(row?['last_activity_at']?.toString() ?? '');
    if (parsed == null) return '';
    final at = parsed.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    if (day == today) {
      return '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    }
    if (today.difference(day).inDays == 1) return 'دوێنێ';
    if (at.year == now.year) return '${at.month}/${at.day}';
    return '${at.year}/${at.month}/${at.day}';
  }

  String _inboxPreview(Map<String, dynamic>? row) {
    if (row == null || row['last_activity_at'] == null) return 'هێشتا مامەڵەی دارایی نییە';
    final kind = row['last_kind']?.toString() ?? '';
    final eventType = row['last_event_type']?.toString() ?? '';
    final amount = (row['last_amount'] as num?)?.toDouble() ??
        double.tryParse('${row['last_amount'] ?? ''}') ??
        0;
    final detail = row['last_preview']?.toString().trim() ?? '';
    String title;
    if (kind == 'debt') {
      title = 'قەرز ${AppHelpers.formatCurrency(amount)}';
    } else if (kind == 'payment') {
      title = 'پارەدانەوە ${AppHelpers.formatCurrency(amount)}';
    } else {
      switch (eventType) {
        case 'debt_created':
          title = 'قەرز زیادکرا';
          break;
        case 'debt_updated':
          title = 'قەرز دەستکاری کرا';
          break;
        case 'debt_deleted':
          title = 'قەرز سڕایەوە';
          break;
        case 'payment_created':
          title = 'پارەدانەوە تۆمارکرا';
          break;
        case 'payment_updated':
          title = 'پارەدانەوە دەستکاری کرا';
          break;
        case 'payment_deleted':
          title = 'پارەدانەوە سڕایەوە';
          break;
        default:
          title = 'مامەڵەی دارایی نوێ';
      }
    }
    if (detail.isEmpty || detail == title) return title;
    return '$title • $detail';
  }

  Future<void> _markFinancialChatReadBestEffort(
    String customerId,
    DateTime? readThrough,
  ) {
    return _directory.markFinancialChatReadBestEffort(customerId, readThrough);
  }

  Future<void> _openUserProfile(RecordModel user) async {
    if (widget.role == 'customer') {
      final row = _customerInbox[user.id];
      final readThrough = DateTime.tryParse(
        row?['last_activity_at']?.toString() ?? '',
      );
      if (row != null && row['unread'] == true) {
        _directory.markUnreadOptimistic(user.id, false);
      }
      unawaited(_markFinancialChatReadBestEffort(user.id, readThrough));
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userId: user.id,
          openFinancialChat: widget.role == 'customer',
        ),
      ),
    );
    if (mounted) _loadUsers(search: _searchController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canAdd =
        (auth.userRole == 'admin') ||
        (auth.userRole == 'employee' &&
            auth.canAddCustomers &&
            widget.role == 'customer');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pinHeader = shouldPinUserListHeader(widget.role);
    final header = _buildDirectoryHeader(canAdd: canAdd);

    return Scaffold(
      backgroundColor: isDark
          ? AppDarkColors.background
          : const Color(0xFFF5F7FA),
      body: Column(
        children: [
          if (pinHeader) header,
          Expanded(
            child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: widget.role == 'customer',
        interactive: true,
        thickness: 4,
        radius: const Radius.circular(8),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
          // ───── Header (scrolls only for non-customer lists) ─────
          if (!pinHeader) SliverToBoxAdapter(child: header),

          // ───── List ─────
          if (!_isLoading &&
              _loadError == null &&
              _users.isNotEmpty &&
              widget.role == 'customer' &&
              _inboxError != null)
            SliverToBoxAdapter(
              child: CustomerInboxWarning(
                message: _inboxError!,
                onRetry: () => unawaited(_directory.refreshInbox()),
              ),
            ),
          _isLoading
              ? const SliverFillRemaining(
                  child: AppAsyncStateView(
                    state: AppAsyncState.loading,
                    loadingLabel: 'کڕیارەکان وەردەگیرێن...',
                    child: SizedBox.shrink(),
                  ),
                )
              : _loadError != null
              ? SliverFillRemaining(child: _buildLoadErrorState())
              : _users.isEmpty
              ? SliverFillRemaining(child: _buildEmptyState())
              : SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    _inboxError == null ? 16 : 10,
                    16,
                    16,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) =>
                          _buildUserCard(_users[index], auth),
                      childCount: _users.length,
                    ),
                  ),
                ),

          if (_isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 50)),
          ],
        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectoryHeader({
    required bool canAdd,
  }) {
    return CustomerCenterHeader(
      title: _isEmployee ? 'کارمەندەکان' : 'کڕیارەکان',
      icon: _isEmployee ? Icons.badge_rounded : Icons.people_rounded,
      totalCount: _totalUsers == 0 ? _users.length : _totalUsers,
      countLabel: _isEmployee ? 'کارمەند' : 'کڕیار',
      searchController: _searchController,
      onSearchChanged: _scheduleCustomerSearch,
      onClearSearch: () {
        _searchController.clear();
        unawaited(_directory.clearSearch());
      },
      canAdd: canAdd,
      onAdd: canAdd ? _showAddDialog : null,
      showFilters: widget.role == 'customer',
      selectedFilter: _customerFilter,
      onFilterSelected: _selectCustomerFilter,
    );
  }

  // ═══════════════════════════════════════════
  // ── Widgets ──
  // ═══════════════════════════════════════════

  void _showAddDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => AddUserDialog(role: widget.role),
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
          child: child,
        );
      },
    ).then((result) {
      if (result == true) {
        _loadUsers(search: _searchController.text.trim());
      }
    });
  }

  Widget _buildLoadErrorState() {
    return AppAsyncStateView(
      state: AppAsyncState.error,
      message: _loadError,
      onRetry: () => _loadUsers(search: _searchController.text.trim()),
      child: const SizedBox.shrink(),
    );
  }

  Widget _buildEmptyState() {
    return AppAsyncStateView(
      state: AppAsyncState.empty,
      emptyTitle: _isEmployee ? 'هیچ کارمەندێک نییە' : 'هیچ کڕیارێک نییە',
      emptyMessage: _searchController.text.trim().isNotEmpty
          ? 'هیچ ئەنجامێک بۆ ئەم گەڕانە نەدۆزرایەوە.'
          : null,
      emptyIcon:
          _isEmployee ? Icons.badge_outlined : Icons.people_outline_rounded,
      child: const SizedBox.shrink(),
    );
  }

  String _normalizedCustomerName(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\\s+'), ' ');

  bool _hasSameNamePeer(RecordModel user) {
    if (widget.role != 'customer') return false;
    final normalized = _normalizedCustomerName(user.getStringValue('name'));
    if (normalized.isEmpty) return false;
    return _users.any(
      (other) =>
          other.id != user.id &&
          _normalizedCustomerName(other.getStringValue('name')) == normalized,
    );
  }

  String _customerPhoneTail(RecordModel user) {
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
    final buffer = StringBuffer();
    for (final codePoint in user.getStringValue('phone').runes) {
      final char = String.fromCharCode(codePoint);
      final latin = '0123456789'.indexOf(char);
      if (latin >= 0) {
        buffer.write(char);
        continue;
      }
      final arabic = arabicDigits.indexOf(char);
      if (arabic >= 0) {
        buffer.write(arabic);
        continue;
      }
      final persian = persianDigits.indexOf(char);
      if (persian >= 0) buffer.write(persian);
    }
    final digits = buffer.toString();
    if (digits.length <= 4) return digits;
    return digits.substring(digits.length - 4);
  }

  Future<void> _quickCustomerDebt(RecordModel user) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddDebtScreen(customerId: user.id),
      ),
    );
    if (mounted) {
      await _loadUsers(search: _searchController.text.trim());
    }
  }

  Future<void> _quickCustomerPayment(
    RecordModel user,
    AuthProvider auth,
  ) async {
    try {
      final snapshot = await PBService.getCustomerFinanceSnapshot(user.id);
      if (!mounted) return;
      final openDebts = List<RecordModel>.from(
        snapshot['openDebts'] as List? ?? const [],
      );
      final saved = await FinancialPaymentFlow.show(
        context: context,
        debts: openDebts,
        createdBy: auth.userId,
        createdByName: auth.userName,
        customerWideOnly: true,
      );
      if (saved && mounted) {
        await _loadUsers(search: _searchController.text.trim());
      }
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا پارەدانەوە بکەرێتەوە.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _quickCustomerChat(RecordModel user) async {
    final inbox = _customerInbox[user.id];
    final readThrough = DateTime.tryParse(
      inbox?['last_activity_at']?.toString() ?? '',
    );
    if (inbox != null && inbox['unread'] == true) {
      _directory.markUnreadOptimistic(user.id, false);
    }
    unawaited(
      _markFinancialChatReadBestEffort(
        user.id,
        readThrough,
      ),
    );
    await _openUserProfile(user);
  }

  Future<void> _quickCustomerStatement(
    RecordModel user,
    AuthProvider auth,
  ) async {
    try {
      final snapshot = await PBService.getCustomerFinanceSnapshot(user.id);
      if (!mounted) return;
      if (snapshot['complete'] != true) {
        AppHelpers.showSnackBar(
          context,
          'کەشف حساب تەواو نییە؛ دووبارە هەوڵ بدە.',
          isError: true,
        );
        return;
      }
      final debts = await PBService.getAllCustomerDebtsLive(user.id);
      if (!mounted) return;
      await PdfService.generateCustomerStatement(
        activeDebts: debts,
        customerName: user.getStringValue('name'),
        marketName: auth.marketName,
        adminName: auth.userName,
        adminPhone: auth.user?.getStringValue('phone') ?? '',
        totalDebt: (snapshot['totalDebtIqd'] as num?)?.toDouble() ?? 0,
        totalRemaining:
            (snapshot['totalRemainingIqd'] as num?)?.toDouble() ?? 0,
        totalPaid: (snapshot['totalPaidIqd'] as num?)?.toDouble() ?? 0,
      );
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا کەشف حساب دروست بکرێت.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _showCustomerPrioritySheet(
    RecordModel user,
    AuthProvider auth,
  ) async {
    if (widget.role != 'customer' || auth.userRole != 'admin') return;

    Map<String, dynamic>? recommendation;
    try {
      recommendation =
          await PBService.getCustomerDebtLimitRecommendation(user.id);
    } catch (_) {}
    if (!mounted) return;

    var isPinned = user.getBoolValue('is_pinned');
    var isVip = user.getBoolValue('is_vip');
    var saving = false;
    final currentLimit = user.getDoubleValue('debt_limit');
    final limitController = TextEditingController(
      text: currentLimit > 0 ? currentLimit.toStringAsFixed(0) : '0',
    );

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final isDark =
              Theme.of(sheetContext).brightness == Brightness.dark;
          final suggested =
              (recommendation?['suggested_limit'] as num?)?.toDouble() ?? 0;
          final paymentRatio =
              ((recommendation?['payment_ratio'] as num?)?.toDouble() ?? 0)
                  .clamp(0.0, 1.0)
                  .toDouble();
          final debtCount =
              (recommendation?['debt_count'] as num?)?.toInt() ?? 0;
          final settledCount =
              (recommendation?['settled_count'] as num?)?.toInt() ?? 0;
          final overdueCount =
              (recommendation?['overdue_open_count'] as num?)?.toInt() ?? 0;
          final confidence =
              recommendation?['confidence']?.toString() ?? 'low';
          final confidenceLabel = switch (confidence) {
            'high' => 'بەرز',
            'medium' => 'مامناوەند',
            _ => 'کەم',
          };

          return Container(
            padding: EdgeInsets.fromLTRB(
              14,
              10,
              14,
              14 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              color: isDark ? AppDarkColors.card : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 34,
                      height: 3,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppDarkColors.cardBorder
                            : const Color(0xFFD0D5DD),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.workspace_premium_outlined,
                          size: 19,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.getStringValue('name'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? AppDarkColors.textPrimary
                                    : const Color(0xFF1D2939),
                              ),
                            ),
                            Text(
                              'Pin • VIP • سنووری قەرز',
                              style: TextStyle(
                                fontSize: 10.5,
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
                  const SizedBox(height: 10),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: isPinned,
                    onChanged: saving
                        ? null
                        : (value) =>
                            setSheetState(() => isPinned = value),
                    secondary: Icon(
                      isPinned
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                      color: isPinned ? AppColors.primary : null,
                    ),
                    title: const Text(
                      'پینکردنی کڕیار',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: const Text(
                      'لە سەرەوەی لیستی کڕیاران بمێنێتەوە',
                      style: TextStyle(fontSize: 10.5),
                    ),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: isVip,
                    onChanged: saving
                        ? null
                        : (value) => setSheetState(() => isVip = value),
                    secondary: Icon(
                      isVip
                          ? Icons.workspace_premium_rounded
                          : Icons.workspace_premium_outlined,
                      color: isVip ? Colors.amber.shade700 : null,
                    ),
                    title: const Text(
                      'کڕیاری VIP',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: const Text(
                      'نیشانەی VIP و سنووری قەرزی تایبەتی',
                      style: TextStyle(fontSize: 10.5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (recommendation != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(
                          alpha: isDark ? 0.10 : 0.055,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.auto_awesome_rounded,
                                size: 17,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text(
                                  'پێشنیاری زیرەکی سنووری قەرز',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              Text(
                                'دڵنیایی: $confidenceLabel',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: isDark
                                      ? AppDarkColors.textSecondary
                                      : const Color(0xFF667085),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Text(
                            suggested > 0
                                ? AppHelpers.formatCurrency(suggested)
                                : 'هێشتا داتای پێویست نییە',
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: isDark
                                  ? AppDarkColors.textPrimary
                                  : const Color(0xFF101828),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'پارەدانەوە ${(paymentRatio * 100).toStringAsFixed(0)}٪ • '
                            '$settledCount/$debtCount قەرز تەواوکراو • '
                            '$overdueCount بەسەرچوو',
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark
                                  ? AppDarkColors.textSecondary
                                  : const Color(0xFF667085),
                            ),
                          ),
                          if (suggested > 0) ...[
                            const SizedBox(height: 7),
                            OutlinedButton.icon(
                              onPressed: saving
                                  ? null
                                  : () {
                                      limitController.text =
                                          suggested.toStringAsFixed(0);
                                      setSheetState(() {});
                                    },
                              icon: const Icon(
                                Icons.bolt_rounded,
                                size: 16,
                              ),
                              label: const Text(
                                'پێشنیارەکە بەکاربهێنە',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: limitController,
                    enabled: !saving,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: isVip
                          ? 'سنووری قەرزی VIP'
                          : 'سنووری قەرز',
                      suffixText: 'د.ع',
                      prefixIcon: const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            final limit = double.tryParse(
                                  limitController.text
                                      .replaceAll(',', '')
                                      .trim(),
                                ) ??
                                -1;
                            if (limit < 0) {
                              AppHelpers.showSnackBar(
                                context,
                                'سنووری قەرز دروست نییە',
                                isError: true,
                              );
                              return;
                            }
                            setSheetState(() => saving = true);
                            try {
                              await PBService.updateUser(
                                user.id,
                                {
                                  'is_pinned': isPinned,
                                  'is_vip': isVip,
                                  'debt_limit': limit,
                                },
                              );
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext, true);
                              }
                            } catch (e) {
                              if (sheetContext.mounted) {
                                setSheetState(() => saving = false);
                              }
                              if (mounted) {
                                AppHelpers.showSnackBar(
                                  context,
                                  AppHelpers.backendErrorMessage(
                                    e,
                                    fallback:
                                        'نەتوانرا ڕێکخستنەکانی کڕیار پاشەکەوت بکرێت.',
                                  ),
                                  isError: true,
                                );
                              }
                            }
                          },
                    icon: saving
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined, size: 18),
                    label: Text(
                      saving ? 'پاشەکەوتکردن...' : 'پاشەکەوتکردن',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    limitController.dispose();

    if (saved == true && mounted) {
      await _loadUsers(search: _searchController.text.trim());
    }
  }

  Widget _buildUserCard(
    RecordModel user,
    AuthProvider auth,
  ) {
    final name = user.getStringValue('name');
    final phoneTail = _customerPhoneTail(user);
    final displayName =
        _hasSameNamePeer(user) && phoneTail.isNotEmpty ? '$name · $phoneTail' : name;
    final inbox = _customerInbox[user.id];
    final canManageCustomer = widget.role == 'customer' &&
        (auth.userRole == 'admin' || auth.userRole == 'employee');
    final balance = _balances[user.id] ?? 0;

    return CustomerDirectoryCard(
      customerId: user.id,
      name: name,
      displayName: displayName,
      phone: user.getStringValue('phone'),
      isEmployee: _isEmployee,
      approved: user.getBoolValue('approved'),
      isPinned: user.getBoolValue('is_pinned'),
      isVip: user.getBoolValue('is_vip'),
      unread: !_isEmployee && inbox?['unread'] == true,
      timeLabel: _inboxTimeLabel(inbox),
      preview: _inboxPreview(inbox),
      balance: balance,
      hasBalance: _balances.containsKey(user.id),
      balanceUnavailable: _balanceErrors.contains(user.id),
      openDebtCount: (inbox?['open_debt_count'] as num?)?.toInt() ?? 0,
      canManage: canManageCustomer,
      onTap: () => _openUserProfile(user),
      onLongPress: canManageCustomer && auth.userRole == 'admin'
          ? () => _showCustomerPrioritySheet(user, auth)
          : null,
      actions: canManageCustomer
          ? [
              CustomerCardAction(
                icon: Icons.add_card_rounded,
                label: 'قەرز',
                color: Colors.orange,
                onTap: () => _quickCustomerDebt(user),
              ),
              CustomerCardAction(
                icon: Icons.payments_outlined,
                label: 'پارە',
                color: Colors.green,
                onTap: () => _quickCustomerPayment(user, auth),
              ),
              CustomerCardAction(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'چات',
                color: AppColors.primary,
                onTap: () => _quickCustomerChat(user),
              ),
              CustomerCardAction(
                icon: Icons.picture_as_pdf_outlined,
                label: 'کەشف',
                color: Colors.deepPurple,
                onTap: () => _quickCustomerStatement(user, auth),
              ),
            ]
          : const [],
    );
  }

}