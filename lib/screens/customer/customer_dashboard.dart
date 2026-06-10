import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/providers/theme_provider.dart';
import 'package:zhirox/screens/shared/debt_detail_screen.dart';
import 'package:zhirox/screens/shared/user_profile_screen.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/services/pdf_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

import 'package:zhirox/screens/customer/notifications_screen.dart';
import 'package:zhirox/services/connectivity_service.dart';

class CustomerDashboard extends StatefulWidget {
  const CustomerDashboard({super.key});

  @override
  State<CustomerDashboard> createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> {
  // Active debts (not paid) - loaded all at once (usually few)
  List<RecordModel> _activeDebts = [];
  // History debts (paid) - loaded with pagination
  List<RecordModel> _historyDebts = [];
  bool _isLoading = true;
  int _selectedTab = 0; // 0: Active, 1: History
  int _unreadCount = 0;

  // Pagination state for history
  int _historyPage = 1;
  bool _hasMoreHistory = true;
  bool _isLoadingMore = false;
  int _historyTotalItems = 0;
  static const int _pageSize = 20;

  // Scroll controller for pagination
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<bool>? _connectivitySub;

  // Stats (calculated from ALL debts, not just loaded ones)
  double _totalDebtAmount = 0;
  double _totalRemainingAmount = 0;
  String _marketName = '';

  List<RecordModel> get _filteredDebts {
    return _selectedTab == 0 ? _activeDebts : _historyDebts;
  }

  int get _activeCount => _activeDebts.length;
  int get _historyCount => _historyTotalItems;

  double get _totalRemaining => _totalRemainingAmount;

  double get _totalDebt => _totalDebtAmount;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadDebts();
    _checkNotifications();
    _connectivitySub = ConnectivityService.instance.statusStream.listen((online) {
      if (online && mounted) {
        _loadDebts();
        _checkNotifications();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.user != null) {
        // Subscribe to debts changes
        PBService.pb.collection('debts').subscribe('*', (e) {
          if (!mounted) return;
          final action = e.action;
          if (action == 'create' || action == 'update' || action == 'delete') {
            if (mounted) {
              Future.delayed(const Duration(milliseconds: 500), () {
                _loadDebts();
              });
            }
          }
        });

        // Subscribe to notifications changes
        PBService.pb.collection('notifications').subscribe('*', (e) {
          if (mounted) {
            _checkNotifications();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    try {
      PBService.pb.collection('debts').unsubscribe('*');
      PBService.pb.collection('notifications').unsubscribe('*');
    } catch (_) {}
    super.dispose();
  }

  void _onScroll() {
    if (_selectedTab != 1) return; // Only paginate history tab
    if (_isLoadingMore || !_hasMoreHistory) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final threshold = maxScroll * 0.8; // Load more at 80% scroll

    if (currentScroll >= threshold) {
      _loadMoreHistory();
    }
  }

  Future<void> _checkNotifications() async {
    if (!mounted) return;
    try {
      final auth = context.read<AuthProvider>();
      if (auth.userId.isEmpty) return;

      final count = await PBService.getUnreadNotificationCount(auth.userId);

      if (mounted) {
        setState(() {
          _unreadCount = count;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDebts() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    if (auth.userId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // Fetch admin's market name
      if (_marketName.isEmpty && auth.adminId.isNotEmpty) {
        try {
          final admin = await PBService.getUser(auth.adminId);
          _marketName = admin.getStringValue('market_name');
        } catch (_) {}
      }

      // Load ALL debts once for accurate stats
      final allDebts = await PBService.getDebts(customerId: auth.userId);

      // Calculate stats from all debts
      double totalDebt = 0;
      double totalRemaining = 0;
      for (var d in allDebts) {
        totalDebt += d.getDoubleValue('amount');
        totalRemaining += d.getDoubleValue('remaining');
      }

      // Separate active debts for display
      final activeDebts = allDebts
          .where((d) => d.getStringValue('status') != 'paid')
          .toList();

      // Load first page of history debts for display
      final historyResult = await PBService.getDebtsPaginated(
        customerId: auth.userId,
        status: 'paid',
        page: 1,
        perPage: _pageSize,
      );

      if (mounted) {
        setState(() {
          // Stats
          _totalDebtAmount = totalDebt;
          _totalRemainingAmount = totalRemaining;

          // Display lists
          _activeDebts = activeDebts;
          _historyDebts = historyResult['items'] as List<RecordModel>;
          _historyTotalItems = historyResult['totalItems'] as int;
          _historyPage = 1;
          _hasMoreHistory = _historyDebts.length < _historyTotalItems;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        if (ConnectivityService.instance.isOnline) {
          AppHelpers.showSnackBar(
            context,
            'هەڵە لە باردانی قەرزەکان: $e',
            isError: true,
          );
        }
      }
    }
  }

  Future<void> _loadMoreHistory() async {
    if (_isLoadingMore || !_hasMoreHistory) return;
    setState(() => _isLoadingMore = true);

    try {
      final auth = context.read<AuthProvider>();
      final nextPage = _historyPage + 1;

      final result = await PBService.getDebtsPaginated(
        customerId: auth.userId,
        status: 'paid',
        page: nextPage,
        perPage: _pageSize,
      );

      final newItems = result['items'] as List<RecordModel>;

      if (mounted) {
        setState(() {
          _historyDebts.addAll(newItems);
          _historyPage = nextPage;
          _hasMoreHistory =
              _historyDebts.length < (result['totalItems'] as int);
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<void> _printStatement() async {
    if (_activeDebts.isEmpty) {
      AppHelpers.showSnackBar(
        context,
        'هیچ قەرزێکی چالاکت نییە بۆ چاپکردن',
        isError: true,
      );
      return;
    }

    try {
      AppHelpers.showLoadingDialog(context);
      final auth = context.read<AuthProvider>();

      // Fetch Admin Info
      String marketName = '';
      String adminName = '';
      String adminPhone = '';
      try {
        final admin = await PBService.getUser(auth.adminId);
        marketName = admin.getStringValue('market_name');
        adminName = admin.getStringValue('name');
        adminPhone = admin.getStringValue('phone');
      } catch (_) {
        marketName = 'Zhirox System';
        adminName = 'Admin';
      }

      if (mounted) Navigator.pop(context); // Close loading

      await PdfService.generateCustomerStatement(
        activeDebts: _activeDebts,
        customerName: auth.userName,
        marketName: marketName,
        adminName: adminName,
        adminPhone: adminPhone,
        totalDebt: _totalDebt,
        totalRemaining: _totalRemaining,
        totalPaid: _totalDebt - _totalRemaining,
      );
    } catch (e) {
      if (mounted) Navigator.pop(context); // Close loading
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          'هەڵەیەک ڕوویدا لە کاتی چاپکردن',
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final totalPaid = _totalDebt - _totalRemaining;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppDarkColors.background : Colors.grey[50],
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // ───── Gradient Header ─────
          SliverAppBar(
            expandedHeight: 280,
            floating: false,
            pinned: true,
            backgroundColor: AppColors.primary,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, Color(0xFF673AB7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    // Decorative Circles
                    Positioned(
                      top: -50,
                      right: -50,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 50,
                      left: -30,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),

                    // Header Content
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 10),
                            // Top Bar (Avatar/Name + Actions)
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => UserProfileScreen(
                                            userId: auth.userId,
                                          ),
                                        ),
                                      ).then((_) {
                                        if (mounted) setState(() {});
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.1,
                                                ),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: CircleAvatar(
                                            radius: 22,
                                            backgroundColor: Colors.grey[100],
                                            child: const Icon(
                                              Icons.person,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _marketName.isNotEmpty
                                                    ? _marketName
                                                    : 'بەخێربێیت،',
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withOpacity(0.8),
                                                  fontSize:
                                                      _marketName.isNotEmpty
                                                      ? 16
                                                      : 14,
                                                  fontWeight:
                                                      _marketName.isNotEmpty
                                                      ? FontWeight.w600
                                                      : FontWeight.normal,
                                                ),
                                              ),
                                              Text(
                                                auth.userName,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                // Notifications Icon
                                Stack(
                                  children: [
                                    IconButton(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const NotificationsScreen(),
                                          ),
                                        ).then((_) => _checkNotifications());
                                      },
                                      icon: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.notifications_outlined,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                    if (_unreadCount > 0)
                                      Positioned(
                                        right: 8,
                                        top: 8,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                          ),
                                          constraints: const BoxConstraints(
                                            minWidth: 16,
                                            minHeight: 16,
                                          ),
                                          child: Text(
                                            '$_unreadCount',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),

                                // Print Statement Icon
                                IconButton(
                                  onPressed: _printStatement,
                                  icon: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.print_outlined,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),

                                // Dark Mode Toggle
                                IconButton(
                                  onPressed: () {
                                    context.read<ThemeProvider>().toggleTheme();
                                  },
                                  icon: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      isDark
                                          ? Icons.light_mode_rounded
                                          : Icons.dark_mode_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 30),

                            // Total Debt Big Display
                            Center(
                              child: Column(
                                children: [
                                  Text(
                                    'کۆی گشتی قەرز',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.8),
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    AppHelpers.formatCurrency(_totalRemaining),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
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
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(80),
              child: Container(
                height: 80,
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                transform: Matrix4.translationValues(0, 40, 0),
                decoration: BoxDecoration(
                  color: isDark ? AppDarkColors.card : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.2 : 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _buildStatItem(
                      'دراوە',
                      AppHelpers.formatCurrency(totalPaid),
                      Colors.green,
                      Icons.check_circle_outline,
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: isDark ? AppDarkColors.divider : Colors.grey[200],
                    ),
                    _buildStatItem(
                      'ژمارەی قەرز',
                      '${_activeCount + _historyCount}',
                      Colors.orange,
                      Icons.receipt_long_rounded,
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 60)),

          // ───── Tabs ─────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? AppDarkColors.card : Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    // Active Debts Tab
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTab = 0),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _selectedTab == 0
                                ? Colors.orange
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: _selectedTab == 0
                                ? [
                                    BoxShadow(
                                      color: Colors.orange.withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : [],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.receipt_long_rounded,
                                color: _selectedTab == 0
                                    ? Colors.white
                                    : Colors.grey,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'قەرزەکانت',
                                style: TextStyle(
                                  color: _selectedTab == 0
                                      ? Colors.white
                                      : Colors.grey[600],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _selectedTab == 0
                                      ? Colors.white.withOpacity(0.2)
                                      : Colors.grey.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$_activeCount',
                                  style: TextStyle(
                                    color: _selectedTab == 0
                                        ? Colors.white
                                        : isDark
                                        ? AppDarkColors.textSecondary
                                        : Colors.black54,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),

                    // History Tab
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTab = 1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _selectedTab == 1
                                ? Colors.green
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: _selectedTab == 1
                                ? [
                                    BoxShadow(
                                      color: Colors.green.withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : [],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.history_rounded,
                                color: _selectedTab == 1
                                    ? Colors.white
                                    : Colors.grey,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'مێژوو',
                                style: TextStyle(
                                  color: _selectedTab == 1
                                      ? Colors.white
                                      : Colors.grey[600],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _selectedTab == 1
                                      ? Colors.white.withOpacity(0.2)
                                      : Colors.grey.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$_historyCount',
                                  style: TextStyle(
                                    color: _selectedTab == 1
                                        ? Colors.white
                                        : isDark
                                        ? AppDarkColors.textSecondary
                                        : Colors.black54,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ───── Debts List ─────
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_filteredDebts.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _selectedTab == 0
                            ? Colors.orange.withOpacity(0.08)
                            : Colors.green.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        _selectedTab == 0
                            ? Icons.receipt_long_rounded
                            : Icons.history_rounded,
                        size: 56,
                        color: _selectedTab == 0
                            ? Colors.orange.withOpacity(0.4)
                            : Colors.green.withOpacity(0.4),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _selectedTab == 0
                          ? 'هیچ قەرزێکت نییە 🎉'
                          : 'هیچ مێژوویەکت نییە',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppDarkColors.textSecondary
                            : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      _buildDebtCard(_filteredDebts[index], index),
                  childCount: _filteredDebts.length,
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),

          // ───── Loading More Indicator (History Tab) ─────
          if (_selectedTab == 1 && _isLoadingMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.green.withOpacity(0.6),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ───── End of History Info ─────
          if (_selectedTab == 1 &&
              !_isLoadingMore &&
              !_hasMoreHistory &&
              _historyDebts.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24, top: 8),
                child: Center(
                  child: Text(
                    'هەموو مێژووەکان نیشان درا • ${_historyDebts.length}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? AppDarkColors.textSecondary
                      : Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebtCard(RecordModel debt, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = debt.getStringValue('status');
    final remaining = debt.getDoubleValue('remaining');
    final amount = debt.getDoubleValue('amount');
    final currency = debt.getStringValue('currency');
    final dollarRate = debt.getDoubleValue('dollar_rate');
    final description = debt.getStringValue('description');
    final customDate = debt.getStringValue('custom_date');
    final date = customDate.isNotEmpty
        ? customDate
        : debt.getStringValue('created');
    final updated = debt.getStringValue('updated');
    final isPaid = status == 'paid';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 400 + (index * 100).clamp(0, 600)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? AppDarkColors.card : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DebtDetailScreen(debtId: debt.id),
                ),
              ).then((_) => _loadDebts());
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Icon Container
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppHelpers.statusColor(status).withOpacity(0.2),
                          AppHelpers.statusColor(status).withOpacity(0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.receipt_long_rounded,
                      color: AppHelpers.statusColor(status),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          description,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              AppHelpers.formatDate(date),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              AppHelpers.formatTime(date),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isPaid
                                ? Colors.green.withOpacity(0.1)
                                : Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            AppHelpers.getDaysCounter(date, updated, isPaid),
                            style: TextStyle(
                              color: isPaid ? Colors.green : Colors.orange,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Amount & Status
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        AppHelpers.formatCurrencyWithType(
                          (currency == 'USD' && dollarRate > 0)
                              ? (isPaid ? amount : remaining) / dollarRate
                              : (isPaid ? amount : remaining),
                          (currency == 'USD' && dollarRate > 0) ? 'USD' : 'IQD',
                          dollarRate: dollarRate,
                          showConversion: false,
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: remaining > 0
                              ? Colors.red[400]
                              : Colors.green[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppHelpers.statusColor(
                            status,
                          ).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          AppHelpers.statusName(status),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppHelpers.statusColor(status),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
