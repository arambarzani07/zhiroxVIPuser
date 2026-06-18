import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/screens/shared/user_profile_screen_clean.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class UserListScreenClean extends StatefulWidget {
  final String role;
  final String adminId;

  const UserListScreenClean({super.key, required this.role, required this.adminId});

  @override
  State<UserListScreenClean> createState() => _UserListScreenCleanState();
}

class _UserListScreenCleanState extends State<UserListScreenClean> {
  final _searchController = TextEditingController();
  List<RecordModel> _users = [];
  bool _isLoading = true;

  bool get _isCustomers => widget.role == 'customer';

  String get _title => _isCustomers ? 'کڕیارەکان' : 'کارمەندەکان';
  String get _subtitle => _isCustomers ? 'چاودێری کڕیار و قەرزەکان' : 'چاودێری کاری کارمەندەکان';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUsers());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final users = await PBService.getUsers(role: widget.role, adminId: widget.adminId);
      if (mounted) _users = users;
    } catch (_) {
      // Keep the visible screen calm and preserve the last state.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<RecordModel> get _filteredUsers {
    final q = _searchController.text.trim().toLowerCase();
    final list = q.isEmpty
        ? List<RecordModel>.from(_users)
        : _users.where((u) {
            final name = u.getStringValue('name').toLowerCase();
            final phone = u.getStringValue('phone').toLowerCase();
            return name.contains(q) || phone.contains(q);
          }).toList();
    list.sort((a, b) => a.getStringValue('name').compareTo(b.getStringValue('name')));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppDarkColors.card : Colors.white;
    final textColor = isDark ? AppDarkColors.textPrimary : AppColors.textPrimary;
    final subColor = isDark ? AppDarkColors.textSecondary : AppColors.textSecondary;
    final users = _filteredUsers;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: _loadUsers,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primary.withOpacity(0.72)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.22),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(18)),
                      child: Icon(_isCustomers ? Icons.people_rounded : Icons.badge_rounded, color: Colors.white, size: 30),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(_subtitle, style: TextStyle(color: Colors.white.withOpacity(0.76), fontSize: 13)),
                        ],
                      ),
                    ),
                    Text('${users.length}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: _isCustomers ? 'گەڕان بە ناو یان ژمارەی کڕیار' : 'گەڕان بە ناو یان ژمارەی کارمەند',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      ),
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (users.isEmpty)
              _EmptyListCard(isCustomers: _isCustomers, cardColor: cardColor, textColor: textColor, subColor: subColor)
            else
              ...users.map((user) => _UserCard(user: user, isCustomers: _isCustomers, cardColor: cardColor, textColor: textColor, subColor: subColor)),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final RecordModel user;
  final bool isCustomers;
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const _UserCard({required this.user, required this.isCustomers, required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    final name = user.getStringValue('name');
    final phone = user.getStringValue('phone');
    final active = user.getBoolValue('active');
    final approved = user.getBoolValue('approved');
    final debtLimit = user.getDoubleValue('debt_limit');

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreenClean(userId: user.id))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: (isCustomers ? AppColors.primary : AppColors.secondary).withOpacity(0.10),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Center(
                child: Text(name.isEmpty ? (isCustomers ? 'ک' : 'ک') : name[0], style: TextStyle(color: isCustomers ? AppColors.primary : AppColors.secondary, fontSize: 21, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.isEmpty ? (isCustomers ? 'کڕیار' : 'کارمەند') : name, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  if (phone.isNotEmpty) Text(phone, textDirection: TextDirection.ltr, style: TextStyle(color: subColor, fontSize: 12)),
                  if (isCustomers && debtLimit > 0) ...[
                    const SizedBox(height: 4),
                    Text('سنووری قەرز: ${AppHelpers.formatCurrency(debtLimit)}', textDirection: TextDirection.ltr, style: TextStyle(color: subColor, fontSize: 12)),
                  ],
                ],
              ),
            ),
            _StatusPill(active: active, approved: approved),
            Icon(Icons.chevron_left_rounded, color: subColor),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool active;
  final bool approved;

  const _StatusPill({required this.active, required this.approved});

  @override
  Widget build(BuildContext context) {
    final ready = active && approved;
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: (ready ? AppColors.secondary : AppColors.warning).withOpacity(0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        ready ? 'چالاک' : 'چاوەڕوان',
        style: TextStyle(color: ready ? AppColors.secondary : AppColors.warning, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _EmptyListCard extends StatelessWidget {
  final bool isCustomers;
  final Color cardColor;
  final Color textColor;
  final Color subColor;

  const _EmptyListCard({required this.isCustomers, required this.cardColor, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Icon(isCustomers ? Icons.people_outline_rounded : Icons.badge_outlined, color: AppColors.primary, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isCustomers ? 'هێشتا کڕیارێک نییە' : 'هێشتا کارمەندێک نییە', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(isCustomers ? 'کاتێک کڕیار زیاد دەکرێت، لێرە دەردەکەوێت.' : 'کاتێک کارمەند زیاد دەکرێت، لێرە دەردەکەوێت.', style: TextStyle(color: subColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
