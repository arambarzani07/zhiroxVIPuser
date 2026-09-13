import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhirox/screens/admin/legacy_import_screen.dart';
import 'package:zhirox/services/connectivity_service.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

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
    _connectivitySub = ConnectivityService.instance.statusStream.listen((
      online,
    ) {
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
    var loadedUsers = <RecordModel>[];

    try {
      loadedUsers = await PBService.getUsers(
        role: 'customer',
        adminId: widget.adminId,
        approved: false,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        cacheKey,
        jsonEncode(loadedUsers.map((u) => u.toJson()).toList()),
      );
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString(cacheKey);
        if (cached != null) {
          final decoded = jsonDecode(cached) as List<dynamic>;
          loadedUsers = decoded.map((e) => RecordModel.fromJson(e)).toList();
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _pendingUsers = loadedUsers;
      _isLoading = false;
    });
  }

  Future<void> _approve(RecordModel user) async {
    try {
      await PBService.updateUser(user.id, {'approved': true});
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'کڕیار قبوڵ کرا ✅');
      await _loadPending();
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);
    }
  }

  Future<void> _reject(RecordModel user) async {
    final confirm = await AppHelpers.showConfirmDialog(
      context,
      title: AppStrings.reject,
      message: 'دڵنیایت لە ڕەتکردنەوەی ئەم داواکاریە؟',
    );
    if (!mounted || !confirm) return;

    try {
      await PBService.deleteUser(user.id);
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'داواکاری ڕەتکرایەوە');
      await _loadPending();
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);
    }
  }

  Future<void> _openLegacyImport() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const LegacyImportScreen()));
    if (mounted) await _loadPending();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: _loadPending,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 2),
              child: _buildImportCard(isDark),
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_pendingUsers.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyState(isDark),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      _buildRequestCard(_pendingUsers[index], index, isDark),
                  childCount: _pendingUsers.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade700, Colors.purple.shade400],
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
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.person_add_alt_1_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'داواکارییەکان',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _isLoading ? '...' : '${_pendingUsers.length} چاوەڕوان',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: 'گواستنەوەی داتای کۆن',
                child: Material(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(13),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(13),
                    onTap: _openLegacyImport,
                    child: const Padding(
                      padding: EdgeInsets.all(11),
                      child: Icon(
                        Icons.move_to_inbox_rounded,
                        color: Colors.white,
                        size: 23,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImportCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withOpacity(0.16)),
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.035),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.folder_zip_rounded, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'گواستنەوەی داتای کۆن',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 3),
                Text(
                  'ZIP ـی Kanichnar/Zhirox بە پشکنین و duplicate protection',
                  style: TextStyle(fontSize: 11.5, height: 1.5),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: _openLegacyImport,
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.check_circle_outline_rounded,
                size: 54,
                color: Colors.green.withOpacity(0.45),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'هیچ داواکارییەکی چاوەڕوان نییە',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isDark ? AppDarkColors.textPrimary : Colors.black54,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'بۆ Import ـی داتای کۆن کارتێکی سەرەوە بەکاربهێنە.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppDarkColors.textSecondary
                    : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(RecordModel user, int index, bool isDark) {
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
      duration: Duration(
        milliseconds: 360 + (index * 60).clamp(0, 420).toInt(),
      ),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Transform.translate(
        offset: Offset(0, 20 * (1 - value)),
        child: Opacity(opacity: value, child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppDarkColors.card : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isDark
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [avatarColor, avatarColor.withOpacity(0.72)],
                    ),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Center(
                    child: Text(
                      name.isEmpty ? '?' : name[0],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        phone,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          color: isDark
                              ? AppDarkColors.textSecondary
                              : Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  AppHelpers.formatDate(date),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w700,
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
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text(AppStrings.approve),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _reject(user),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text(AppStrings.reject),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
