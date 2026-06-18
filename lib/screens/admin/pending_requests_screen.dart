import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/services/connectivity_service.dart';

class PendingRequestsScreen extends StatefulWidget {
  final String adminId;

  const PendingRequestsScreen({super.key, required this.adminId});

  @override
  State<PendingRequestsScreen> createState() => _PendingRequestsScreenState();
}

class _PendingRequestsScreenState extends State<PendingRequestsScreen> {
  List<RecordModel> _pendingUsers = [];
  bool _isLoading = true;
  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _loadPending();
    _connectivitySub = ConnectivityService.instance.statusStream.listen((online) {
      if (online && mounted) _loadPending();
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _loadPending() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final cacheKey = 'cached_pending_${widget.adminId}';

    try {
      _pendingUsers = await PBService.getUsers(
        role: 'customer',
        adminId: widget.adminId,
        approved: false,
      );
      final prefs = await SharedPreferences.getInstance();
      final usersJson = _pendingUsers.map((u) => u.toJson()).toList();
      await prefs.setString(cacheKey, jsonEncode(usersJson));
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedString = prefs.getString(cacheKey);
        if (cachedString != null) {
          final decoded = jsonDecode(cachedString) as List<dynamic>;
          _pendingUsers = decoded.map((item) => RecordModel.fromJson(item)).toList();
        }
      } catch (_) {}
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _approve(RecordModel user) async {
    try {
      await PBService.updateUser(user.id, {'approved': true});
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'کڕیار ڕێگەی پێدرا ✅');
      _loadPending();
    } catch (_) {
      if (!mounted) return;
      AppHelpers.showSnackBar(context, AppStrings.savedForLater, isError: true);
    }
  }

  Future<void> _reject(RecordModel user) async {
    final confirm = await AppHelpers.showConfirmDialog(
      context,
      title: AppStrings.reject,
      message: 'دڵنیایت لە ڕەتکردنەوەی ئەم داواکارییە؟',
    );
    if (!confirm) return;

    try {
      await PBService.deleteUser(user.id);
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'داواکاری ڕەتکرایەوە');
      _loadPending();
    } catch (_) {
      if (!mounted) return;
      AppHelpers.showSnackBar(context, AppStrings.savedForLater, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primary.withOpacity(0.72)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ڕێگەپێدانەکان',
                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isLoading ? 'ئامادەکردن...' : '${_pendingUsers.length} داواکاری',
                            style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_isLoading)
          const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
        else if (_pendingUsers.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(Icons.check_circle_outline, size: 56, color: Colors.green.withOpacity(0.45)),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'هیچ داواکارییەکی چاوەڕوان نییە',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppDarkColors.textPrimary : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'کاتێک کڕیارێکی نوێ تۆمار دەبێت لێرە دەردەکەوێت',
                    style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildRequestCard(_pendingUsers[index], index),
                childCount: _pendingUsers.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRequestCard(RecordModel user, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = user.getStringValue('name');
    final fatherName = user.getStringValue('father_name');
    final grandfatherName = user.getStringValue('grandfather_name');
    final phone = user.getStringValue('phone');
    final fullName = '$name $fatherName $grandfatherName'.trim();
    final date = user.getStringValue('created');
    final hue = (name.hashCode % 360).abs().toDouble();
    final avatarColor = HSLColor.fromAHSL(1, hue, 0.6, 0.5).toColor();

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 400 + (index * 80).clamp(0, 500)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 25 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? AppDarkColors.card : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [avatarColor, avatarColor.withOpacity(0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'ک',
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName.isEmpty ? 'کڕیار' : fullName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isDark ? AppDarkColors.textPrimary : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.phone_android, size: 13, color: Colors.grey[400]),
                            const SizedBox(width: 4),
                            Text(
                              phone,
                              textDirection: TextDirection.ltr,
                              style: TextStyle(color: Colors.grey[500], fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      AppHelpers.formatDate(date),
                      style: TextStyle(fontSize: 10, color: Colors.orange[700], fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _approve(user),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text(AppStrings.approve),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _reject(user),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text(AppStrings.reject),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
