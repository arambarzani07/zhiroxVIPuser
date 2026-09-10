import 'package:flutter/material.dart';
import 'dart:async';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/shared/user_profile_screen.dart';
import 'package:zhirox/screens/shared/add_user_screen.dart';
import 'package:zhirox/screens/shared/add_debt_screen.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/services/connectivity_service.dart';

class UserListScreen extends StatefulWidget {
  final String role;
  final String? adminId;

  const UserListScreen({super.key, required this.role, this.adminId});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  List<RecordModel> _users = [];
  bool _isLoading = true;
  String? _loadError;
  final _searchController = TextEditingController();
  final Map<String, double> _balances = {};
  final Set<String> _balanceErrors = <String>{};
  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUsers();
    });
    _connectivitySub = ConnectivityService.instance.statusStream.listen((online) {
      if (online && mounted) _loadUsers();
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String get _adminId {
    if (widget.adminId != null && widget.adminId!.isNotEmpty) {
      return widget.adminId!;
    }
    final auth = context.read<AuthProvider>();
    return auth.adminId;
  }

  bool get _isEmployee => widget.role == 'employee';

  Future<void> _loadUsers({String? search}) async {
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

  /// Load all customer balances in parallel (non-blocking)
  Future<void> _loadBalancesInBackground() async {
    final usersCopy = List<RecordModel>.from(_users);
    await Future.wait(
      usersCopy.map((user) async {
        try {
          final balance = await PBService.getCustomerBalance(user.id);
          _balances[user.id] = balance;
          _balanceErrors.remove(user.id);
        } catch (_) {
          _balances.remove(user.id);
          _balanceErrors.add(user.id);
        }
      }),
    );
    if (mounted) setState(() {}); // Refresh UI with loaded balances
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
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title + Add Button + Count
                      Row(
                        children: [
                          Icon(
                            _isEmployee ? Icons.badge : Icons.people,
                            color: Colors.white,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _isEmployee ? 'کارمەندەکان' : 'کڕیارەکان',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          if (!_isLoading)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_users.length} ${_isEmployee ? 'کارمەند' : 'کڕیار'}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          if (canAdd) ...[
                            const SizedBox(width: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: IconButton(
                                padding: const EdgeInsets.all(8),
                                constraints: const BoxConstraints(),
                                icon: const Icon(
                                  Icons.person_add,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                onPressed: () => _showAddDialog(),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Search Bar
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? AppDarkColors.card : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: isDark
                              ? []
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: TextStyle(
                            color: isDark
                                ? AppDarkColors.textPrimary
                                : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            hintText: 'گەڕان بەدوای ناو یان ژمارە...',
                            hintStyle: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 14,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              color: AppColors.primary,
                              size: 22,
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(
                                      Icons.clear,
                                      size: 18,
                                      color: Colors.grey[400],
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      _loadUsers();
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          onChanged: (value) => _loadUsers(search: value),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ───── List ─────
          _isLoading
              ? const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              : _loadError != null
              ? SliverFillRemaining(child: _buildLoadErrorState())
              : _users.isEmpty
              ? SliverFillRemaining(child: _buildEmptyState())
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) =>
                          _buildUserCard(_users[index], index, auth),
                      childCount: _users.length,
                    ),
                  ),
                ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 50)),
        ],
      ),
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
      if (result == true) _loadUsers();
    });
  }

  Widget _buildLoadErrorState() {
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isEmployee ? Icons.badge_outlined : Icons.people_outline,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            AppStrings.noData,
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => _loadUsers(),
            icon: const Icon(Icons.refresh),
            label: const Text('نوێکردنەوە'),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(RecordModel user, int index, AuthProvider auth) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = user.getStringValue('name');
    final approved = user.getBoolValue('approved');
    final accentColor = AppColors.primary;
    final balance = _balances[user.id] ?? 0;
    final balanceUnavailable = _balanceErrors.contains(user.id);
    final canManageCustomer = widget.role == 'customer' &&
        (auth.userRole == 'admin' || auth.userRole == 'employee');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE9EDF3),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserProfileScreen(
                  userId: user.id,
                  openFinancialChat: widget.role == 'customer',
                ),
              ),
            ).then((_) => _loadUsers());
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: accentColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: isDark
                                    ? AppDarkColors.textPrimary
                                    : const Color(0xFF1F2937),
                              ),
                            ),
                          ),
                          if (_isEmployee && approved)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'چالاک',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (_isEmployee) ...[
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
                        const SizedBox(height: 5),
                        Text(
                          balanceUnavailable
                              ? 'ماوە: نەتوانرا باربکرێت'
                              : _balances.containsKey(user.id)
                                  ? 'ماوە: ${AppHelpers.formatCurrency(balance)}'
                                  : 'ماوە: ...',
                          style: TextStyle(
                            color: balanceUnavailable
                                ? Colors.orange[500]
                                : !_balances.containsKey(user.id)
                                    ? Colors.grey[400]
                                    : balance > 0
                                        ? Colors.red[500]
                                        : Colors.green[500],
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (canManageCustomer)
                  PopupMenuButton<String>(
                    tooltip: 'کردارەکان',
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      if (value == 'debt') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddDebtScreen(customerId: user.id),
                          ),
                        ).then((_) => _loadUsers());
                      } else if (value == 'payment') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UserProfileScreen(
                              userId: user.id,
                              openFinancialChat: true,
                            ),
                          ),
                        ).then((_) => _loadUsers());
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem<String>(
                        value: 'debt',
                        child: Row(
                          children: [
                            Icon(Icons.add_card_rounded, size: 20),
                            SizedBox(width: 10),
                            Text('قەرز زیاد بکە'),
                          ],
                        ),
                      ),
                      if (balance > 0)
                        const PopupMenuItem<String>(
                          value: 'payment',
                          child: Row(
                            children: [
                              Icon(Icons.payments_outlined, size: 20),
                              SizedBox(width: 10),
                              Text('پارەدانەوە'),
                            ],
                          ),
                        ),
                    ],
                    icon: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.more_horiz_rounded,
                        color: accentColor,
                        size: 22,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_left_rounded,
                    color: isDark ? Colors.grey[600] : Colors.grey[350],
                    size: 22,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
