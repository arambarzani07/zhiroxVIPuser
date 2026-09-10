import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
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
  bool _loadFailed = false;
  String? _busyUserId;
  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _loadPending();
    _connectivitySub = ConnectivityService.instance.statusStream.listen((online) {
      if (online && mounted) _loadPending(showLoader: false);
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _loadPending({bool showLoader = true}) async {
    if (!mounted) return;
    if (showLoader) {
      setState(() {
        _isLoading = true;
        _loadFailed = false;
      });
    }

    try {
      final users = await PBService.getUsers(
        role: 'customer',
        adminId: widget.adminId,
        approved: false,
      );
      if (!mounted) return;
      setState(() {
        _pendingUsers = users;
        _isLoading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _approve(RecordModel user) async {
    if (_busyUserId != null) return;
    setState(() => _busyUserId = user.id);
    try {
      await PBService.updateUser(user.id, {'approved': true});
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'کڕیار قبوڵ کرا ✅');
      await _loadPending(showLoader: false);
    } catch (_) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        'قبوڵکردنی داواکاری سەرکەوتوو نەبوو',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  Future<void> _reject(RecordModel user) async {
    if (_busyUserId != null) return;
    final confirm = await AppHelpers.showConfirmDialog(
      context,
      title: AppStrings.reject,
      message: 'دڵنیایت لە ڕەتکردنەوەی ئەم داواکاریە؟',
    );
    if (!mounted || !confirm) return;

    setState(() => _busyUserId = user.id);
    try {
      await PBService.deleteUser(user.id);
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'داواکاری ڕەتکرایەوە');
      await _loadPending(showLoader: false);
    } catch (_) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        'ڕەتکردنەوەی داواکاری سەرکەوتوو نەبوو',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? AppDarkColors.background
        : const Color(0xFFF7F8FA);

    return ColoredBox(
      color: background,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(isDark)),
          if (_isLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          else if (_loadFailed)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildErrorState(isDark),
            )
          else if (_pendingUsers.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyState(isDark),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              sliver: SliverList.separated(
                itemCount: _pendingUsers.length,
                itemBuilder: (context, index) =>
                    _buildRequestCard(_pendingUsers[index], isDark),
                separatorBuilder: (_, _) => const SizedBox(height: 8),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.person_add_alt_1_rounded,
                color: AppColors.primary,
                size: 21,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'داواکارییەکان',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? AppDarkColors.textPrimary
                          : const Color(0xFF101828),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _isLoading
                        ? 'خەریکی نوێکردنەوەیە...'
                        : '${_pendingUsers.length} داواکاری چاوەڕوانە',
                    style: TextStyle(
                      fontSize: 11.5,
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
              onPressed: _isLoading ? null : () => _loadPending(),
              icon: const Icon(Icons.refresh_rounded, size: 21),
              color: isDark
                  ? AppDarkColors.textSecondary
                  : const Color(0xFF667085),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                size: 30,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'هیچ داواکاریەکی چاوەڕوان نییە',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppDarkColors.textPrimary
                    : const Color(0xFF344054),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'داواکاریی کڕیارانی نوێ لێرە دەردەکەون',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
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

  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.cloud_off_outlined,
                size: 29,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'داواکارییەکان بار نەبوون',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppDarkColors.textPrimary
                    : const Color(0xFF344054),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'پەیوەندی ئینتەرنێت بپشکنە و دووبارە هەوڵ بدەرەوە',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppDarkColors.textSecondary
                    : const Color(0xFF98A2B3),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _loadPending(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('دووبارە هەوڵ بدەرەوە'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(RecordModel user, bool isDark) {
    final name = user.getStringValue('name');
    final fatherName = user.getStringValue('father_name');
    final grandfatherName = user.getStringValue('grandfather_name');
    final phone = user.getStringValue('phone');
    final fullName = [name, fatherName, grandfatherName]
        .where((part) => part.trim().isNotEmpty)
        .join(' ');
    final date = user.getStringValue('created');
    final busy = _busyUserId == user.id;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? AppDarkColors.cardBorder
              : const Color(0xFFE9EDF3),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName.isEmpty ? 'کڕیاری نوێ' : fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppDarkColors.textPrimary
                            : const Color(0xFF344054),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.phone_outlined,
                          size: 13,
                          color: isDark
                              ? AppDarkColors.textSecondary
                              : const Color(0xFF98A2B3),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            phone.isEmpty ? 'ژمارە نەدراوە' : phone,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark
                                  ? AppDarkColors.textSecondary
                                  : const Color(0xFF667085),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                AppHelpers.formatDate(date),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppDarkColors.textSecondary
                      : const Color(0xFF98A2B3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ElevatedButton.icon(
                    onPressed: busy ? null : () => _approve(user),
                    icon: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 17),
                    label: const Text(AppStrings.approve),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : () => _reject(user),
                    icon: const Icon(Icons.close_rounded, size: 17),
                    label: const Text(AppStrings.reject),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: BorderSide(
                        color: Colors.red.withValues(alpha: 0.22),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
