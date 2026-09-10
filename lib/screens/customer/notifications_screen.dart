import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/models/record_model.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/shared/debt_detail_screen.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<RecordModel> _notifications = const [];
  bool _loading = true;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNotifications();
      _subscribeToNotifications();
    });
  }

  @override
  void dispose() {
    PBService.pb.collection('notifications').unsubscribe();
    super.dispose();
  }

  void _subscribeToNotifications() {
    PBService.pb.collection('notifications').subscribe('*', (_) {
      if (mounted) _loadNotifications(showLoader: false);
    });
  }

  Future<void> _loadNotifications({bool showLoader = true}) async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.userRole != 'customer' || auth.userId.isEmpty) {
      setState(() {
        _loading = false;
        _notifications = const [];
      });
      return;
    }

    if (showLoader) setState(() => _loading = true);
    try {
      final rows = await PBService.getNotifications(auth.userId);
      if (!mounted) return;
      setState(() => _notifications = rows);
    } catch (e) {
      if (mounted && showLoader) {
        AppHelpers.showSnackBar(
          context,
          'ئاگادارکردنەوەکان بار نەبوون',
          isError: true,
        );
      }
    } finally {
      if (mounted && showLoader) setState(() => _loading = false);
    }
  }

  Future<void> _markAsRead(RecordModel notification) async {
    if (notification.getBoolValue('is_read')) return;
    try {
      await PBService.markNotificationRead(notification.id);
      if (!mounted) return;
      setState(() {
        final index = _notifications.indexWhere((n) => n.id == notification.id);
        if (index == -1) return;
        final json = _notifications[index].toJson();
        json['is_read'] = true;
        _notifications = List<RecordModel>.from(_notifications)
          ..[index] = RecordModel.fromJson(json);
      });
    } catch (_) {
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          'نەتوانرا ئاگادارکردنەوەکە وەک خوێندراو دیاری بکرێت',
          isError: true,
        );
      }
    }
  }

  Future<void> _openNotification(RecordModel notification) async {
    await _markAsRead(notification);
    if (!mounted) return;
    final debtId = notification.getStringValue('debt');
    if (debtId.isEmpty) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => DebtDetailScreen(debtId: debtId)),
    );
  }

  Future<void> _markAllRead() async {
    if (_markingAll) return;
    final unread = _notifications
        .where((n) => !n.getBoolValue('is_read'))
        .toList(growable: false);
    if (unread.isEmpty) return;

    setState(() => _markingAll = true);
    try {
      for (final notification in unread) {
        await PBService.markNotificationRead(notification.id);
      }
      await _loadNotifications(showLoader: false);
    } catch (_) {
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          'هەموو ئاگادارکردنەوەکان نوێ نەکرانەوە',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _deleteNotification(RecordModel notification) async {
    final confirmed = await AppHelpers.showConfirmDialog(
      context,
      title: 'سڕینەوە',
      message: 'دڵنیایت لە سڕینەوەی ئەم ئاگادارکردنەوەیە؟',
    );
    if (!confirmed || !mounted) return;

    try {
      await PBService.deleteNotification(notification.id);
      if (!mounted) return;
      setState(() {
        _notifications = _notifications
            .where((item) => item.id != notification.id)
            .toList(growable: false);
      });
    } catch (_) {
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          'ئاگادارکردنەوەکە نەسڕایەوە',
          isError: true,
        );
      }
    }
  }

  Map<String, List<RecordModel>> _groupNotifications() {
    final grouped = <String, List<RecordModel>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final notification in _notifications) {
      final parsed = DateTime.tryParse(notification.created)?.toLocal();
      final date = parsed == null
          ? null
          : DateTime(parsed.year, parsed.month, parsed.day);
      final key = date == today
          ? 'ئەمڕۆ'
          : date == yesterday
              ? 'دوێنێ'
              : 'پێشتر';
      grouped.putIfAbsent(key, () => []).add(notification);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final grouped = _groupNotifications();
    final orderedKeys = ['ئەمڕۆ', 'دوێنێ', 'پێشتر']
        .where(grouped.containsKey)
        .toList(growable: false);
    final hasUnread = _notifications.any((n) => !n.getBoolValue('is_read'));

    return Scaffold(
      backgroundColor: isDark ? AppDarkColors.background : AppColors.background,
      appBar: AppBar(
        title: const Text('ئاگادارکردنەوەکان'),
        actions: [
          if (hasUnread)
            IconButton(
              tooltip: 'خوێندنەوەی هەمووی',
              onPressed: _markingAll ? null : _markAllRead,
              icon: _markingAll
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.done_all_rounded),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? const _EmptyNotifications()
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: orderedKeys.length,
                    itemBuilder: (context, index) {
                      final key = orderedKeys[index];
                      final notifications = grouped[key]!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
                            child: Text(
                              key,
                              style: TextStyle(
                                color: isDark
                                    ? AppDarkColors.textSecondary
                                    : AppColors.textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ...notifications.map(
                            (notification) => _NotificationCard(
                              notification: notification,
                              onOpen: () => _openNotification(notification),
                              onDelete: () => _deleteNotification(notification),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      );
                    },
                  ),
                ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onOpen,
    required this.onDelete,
  });

  final RecordModel notification;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRead = notification.getBoolValue('is_read');
    final message = notification.getStringValue('message');
    final type = notification.getStringValue('type');
    final isOverdue = type == 'debt_overdue';
    final hasDebt = notification.getStringValue('debt').isNotEmpty;

    final icon = isOverdue
        ? Icons.warning_amber_rounded
        : hasDebt
            ? Icons.receipt_long_rounded
            : Icons.notifications_none_rounded;
    final accent = isOverdue
        ? AppColors.danger
        : hasDebt
            ? AppColors.warning
            : AppColors.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isRead ? Colors.grey : accent).withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: isRead ? Colors.grey : accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            message,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.55,
                              fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                              color: isDark
                                  ? (isRead
                                      ? AppDarkColors.textSecondary
                                      : AppDarkColors.textPrimary)
                                  : (isRead
                                      ? AppColors.textSecondary
                                      : AppColors.textPrimary),
                            ),
                          ),
                        ),
                        if (!isRead)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(top: 5, right: 6),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          AppHelpers.formatTime(notification.created),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (hasDebt) ...[
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.chevron_left_rounded,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const Text(
                            'بینینی قەرز',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'سڕینەوە',
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.danger,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => RefreshIndicator(
        onRefresh: () async {
          // Pull-to-refresh is handled by reopening/loading through the parent;
          // this keeps the empty state scrollable without introducing secrets or
          // customer-side notification configuration.
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: constraints.maxHeight,
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 58,
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(height: 14),
                  Text(
                    'هیچ ئاگادارکردنەوەیەک نییە',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
