import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/shared/add_debt_screen.dart';
import 'package:zhirox/screens/shared/add_user_screen.dart';
import 'package:zhirox/screens/shared/customer_money_profile_screen.dart';
import 'package:zhirox/screens/shared/user_profile_screen.dart';
import 'package:zhirox/services/connectivity_service.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class UserListScreen extends StatefulWidget {
  final String role;
  final String? adminId;

  const UserListScreen({super.key, required this.role, this.adminId});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  final _searchController = TextEditingController();
  final Map<String, double> _balances = {};
  List<RecordModel> _users = [];
  bool _isLoading = true;
  Timer? _searchDebounce;
  StreamSubscription<bool>? _connectivitySub;

  bool get _isEmployee => widget.role == 'employee';

  String get _adminId {
    if (widget.adminId != null && widget.adminId!.isNotEmpty) return widget.adminId!;
    return context.read<AuthProvider>().adminId;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUsers());
    _connectivitySub = ConnectivityService.instance.statusStream.listen((online) {
      if (online && mounted) _loadUsers(search: _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _connectivitySub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers({String? search}) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

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
        _loadBalancesInBackground(users);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppHelpers.showSnackBar(context, 'هەڵە لە هێنانی لیست: $e', isError: true);
    }
  }

  Future<void> _loadBalancesInBackground(List<RecordModel> users) async {
    await Future.wait(users.map((user) async {
      try {
        _balances[user.id] = await PBService.getCustomerBalance(user.id);
      } catch (_) {
        _balances[user.id] = 0;
      }
    }));
    if (mounted) setState(() {});
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _loadUsers(search: value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canAdd = auth.userRole == 'admin' ||
        (auth.userRole == 'employee' && auth.canAddCustomers && widget.role == 'customer');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
        body: RefreshIndicator(
          onRefresh: () => _loadUsers(search: _searchController.text.trim()),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _Header(
                  isEmployee: _isEmployee,
                  count: _users.length,
                  canAdd: canAdd,
                  searchController: _searchController,
                  onAdd: _showAddDialog,
                  onSearchChanged: _onSearchChanged,
                ),
              ),
              if (_isLoading)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
              else if (_users.isEmpty)
                SliverFillRemaining(child: _EmptyState(isEmployee: _isEmployee, onRefresh: () => _loadUsers()))
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                  sliver: SliverList.builder(
                    itemCount: _users.length,
                    itemBuilder: (context, index) => _UserCard(
                      user: _users[index],
                      isEmployee: _isEmployee,
                      balance: _balances[_users[index].id],
                      canQuickAddDebt: widget.role == 'customer' &&
                          (auth.userRole == 'admin' || auth.userRole == 'employee'),
                      onOpen: () => _openUser(_users[index]),
                      onAddDebt: () => _openAddDebt(_users[index]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) => AddUserDialog(role: widget.role),
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
          child: child,
        );
      },
    ).then((result) {
      if (result == true) _loadUsers(search: _searchController.text.trim());
    });
  }

  void _openUser(RecordModel user) {
    final screen = widget.role == 'customer'
        ? CustomerMoneyProfileScreen(userId: user.id)
        : UserProfileScreen(userId: user.id);

    Navigator.push(context, MaterialPageRoute(builder: (_) => screen)).then((_) {
      _loadUsers(search: _searchController.text.trim());
    });
  }

  void _openAddDebt(RecordModel user) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddDebtScreen(customerId: user.id)),
    ).then((_) => _loadUsers(search: _searchController.text.trim()));
  }
}

class _Header extends StatelessWidget {
  final bool isEmployee;
  final int count;
  final bool canAdd;
  final TextEditingController searchController;
  final VoidCallback onAdd;
  final ValueChanged<String> onSearchChanged;

  const _Header({
    required this.isEmployee,
    required this.count,
    required this.canAdd,
    required this.searchController,
    required this.onAdd,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = isEmployee ? 'کارمەندەکان' : 'کڕیارەکان';
    final icon = isEmployee ? Icons.badge_rounded : Icons.people_alt_rounded;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isEmployee
              ? [const Color(0xFF4A6CF7), const Color(0xFF6B8CFF)]
              : [AppColors.primary, AppColors.primary.withOpacity(0.84)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(99)),
                    child: Text('$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  if (canAdd) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add_rounded, color: Colors.white),
                      style: IconButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.18)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? AppDarkColors.card : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  controller: searchController,
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    hintText: isEmployee ? 'گەڕان بەدوای کارمەند...' : 'گەڕان بەدوای ناو یان ژمارە...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final RecordModel user;
  final bool isEmployee;
  final double? balance;
  final bool canQuickAddDebt;
  final VoidCallback onOpen;
  final VoidCallback onAddDebt;

  const _UserCard({
    required this.user,
    required this.isEmployee,
    required this.balance,
    required this.canQuickAddDebt,
    required this.onOpen,
    required this.onAddDebt,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = user.getStringValue('name');
    final phone = user.getStringValue('phone');
    final approved = user.getBoolValue('approved');
    final currentBalance = balance ?? 0;
    final hasDebt = currentBalance > 0;
    final accent = isEmployee ? const Color(0xFF4A6CF7) : AppColors.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: isDark ? AppDarkColors.card : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: accent.withOpacity(0.12),
                child: Text(
                  name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                  style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 20),
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
                            name.isEmpty ? 'بێ ناو' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                        if (isEmployee && approved)
                          const _SmallBadge(label: 'چالاک', color: Colors.green),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      phone.isEmpty ? 'ژمارەی مۆبایل نەدراوە' : phone,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      textDirection: TextDirection.ltr,
                    ),
                    if (!isEmployee) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            hasDebt ? Icons.warning_amber_rounded : Icons.verified_rounded,
                            size: 17,
                            color: hasDebt ? Colors.redAccent : Colors.green,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            balance == null
                                ? 'ماوە: ...'
                                : hasDebt
                                    ? 'ماوە: ${AppHelpers.formatCurrency(currentBalance)}'
                                    : 'هیچ قەرزێکی ماوە نییە',
                            style: TextStyle(
                              color: hasDebt ? Colors.redAccent : Colors.green,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (canQuickAddDebt)
                IconButton(
                  tooltip: 'قەرزی نوێ',
                  onPressed: onAddDebt,
                  icon: Icon(Icons.add_circle_outline_rounded, color: AppColors.primary),
                ),
              const Icon(Icons.chevron_left_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _SmallBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isEmployee;
  final VoidCallback onRefresh;

  const _EmptyState({required this.isEmployee, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isEmployee ? Icons.badge_outlined : Icons.people_outline, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(isEmployee ? 'هیچ کارمەندێک نییە' : 'هیچ کڕیارێک نییە'),
          const SizedBox(height: 12),
          TextButton.icon(onPressed: onRefresh, icon: const Icon(Icons.refresh), label: const Text('نوێکردنەوە')),
        ],
      ),
    );
  }
}
