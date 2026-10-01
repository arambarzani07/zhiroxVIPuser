import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/customer/telegram_settings_dialog.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<RecordModel> _notifications = [];
  bool _isLoading = true;
  bool _loadInFlight = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _subscribeToNotifications();
  }

  @override
  void dispose() {
    try {
      PBService.pb.collection('notifications').unsubscribe();
    } catch (_) {}
    super.dispose();
  }

  void _subscribeToNotifications() {
    PBService.pb.collection('notifications').subscribe('*', (_) {
      if (mounted) _loadNotifications();
    });
  }

  Future<void> _loadNotifications() async {
    if (!mounted || _loadInFlight) return;
    _loadInFlight = true;
    if (_notifications.isEmpty) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final auth = context.read<AuthProvider>();
      if (auth.userId.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final items = await PBService.getNotifications(auth.userId);
      if (!mounted) return;
      setState(() {
        _notifications = items;
        _isLoading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (_notifications.isEmpty) {
          _loadError =
              'نەتوانرا ئاگادارکردنەوەکان بار بکرێن. دووبارە هەوڵ بدە.';
        }
      });
    } finally {
      _loadInFlight = false;
    }
  }

  void _setReadState(String id, bool isRead) {
    final index = _notifications.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final old = _notifications[index];
    final json = old.toJson();
    json['is_read'] = isRead;
    final data = Map<String, dynamic>.from(old.data);
    if (data.containsKey('is_read')) data['is_read'] = isRead;
    if (data.isNotEmpty) json['data'] = data;
    _notifications[index] = RecordModel.fromJson(json);
  }

  Future<void> _markAsRead(RecordModel notification) async {
    if (notification.getBoolValue('is_read')) return;
    final id = notification.id;
    setState(() => _setReadState(id, true));
    try {
      await PBService.markNotificationRead(id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _setReadState(id, false));
      AppHelpers.showSnackBar(
        context,
        'نەتوانرا ئاگادارکردنەوەکە وەک خوێندراو تۆمار بکرێت.',
        isError: true,
      );
    }
  }

  Future<void> _markAllRead() async {
    final unread = _notifications
        .where((item) => !item.getBoolValue('is_read'))
        .toList();
    if (unread.isEmpty || !mounted) return;

    setState(() {
      for (final item in unread) {
        _setReadState(item.id, true);
      }
    });

    AppHelpers.showLoadingDialog(context);
    try {
      for (final item in unread) {
        await PBService.markNotificationRead(item.id);
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      Navigator.pop(context);
      await _loadNotifications();
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        'نەتوانرا هەموو ئاگادارکردنەوەکان نوێ بکرێنەوە.',
        isError: true,
      );
    }
  }

  Future<void> _confirmDelete(RecordModel notification) async {
    final confirm = await AppHelpers.showConfirmDialog(
      context,
      title: 'سڕینەوە',
      message: 'دڵنیایت لە سڕینەوەی ئەم ئاگادارکردنەوەیە؟',
    );
    if (!confirm || !mounted) return;

    try {
      await PBService.deleteNotification(notification.id);
      if (!mounted) return;
      setState(() {
        _notifications.removeWhere((item) => item.id == notification.id);
      });
    } catch (_) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        'نەتوانرا ئاگادارکردنەوەکە بسڕدرێتەوە.',
        isError: true,
      );
    }
  }

  void _showTelegramSettings() {
    showDialog<void>(
      context: context,
      builder: (_) => const TelegramSettingsDialog(),
    );
  }

  Map<String, List<RecordModel>> _groupNotifications() {
    final grouped = <String, List<RecordModel>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final item in _notifications) {
      final raw = item.getStringValue('created');
      final parsed = DateTime.tryParse(raw)?.toLocal();
      final date = parsed == null
          ? null
          : DateTime(parsed.year, parsed.month, parsed.day);
      final key = date == today
          ? 'ئەمڕۆ'
          : date == yesterday
              ? 'دوێنێ'
              : 'پێشتر';
      grouped.putIfAbsent(key, () => <RecordModel>[]).add(item);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppDarkColors.textPrimary : const Color(0xFF1D2939);
    final textSecondary =
        isDark ? AppDarkColors.textSecondary : const Color(0xFF667085);
    final border =
        isDark ? AppDarkColors.cardBorder : const Color(0xFFEAECF0);
    final surface = isDark ? AppDarkColors.card : Colors.white;
    final unreadCount =
        _notifications.where((item) => !item.getBoolValue('is_read')).length;
    final grouped = _groupNotifications();
    final groupKeys = grouped.keys.toList();

    return Scaffold(
      backgroundColor:
          isDark ? AppDarkColors.background : const Color(0xFFF7F8FA),
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ئاگادارکردنەوەکان',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: textPrimary,
              ),
            ),
            if (!_isLoading && _notifications.isNotEmpty)
              Text(
                unreadCount == 0
                    ? 'هەمووی خوێندراونەتەوە'
                    : '$unreadCount نەخوێندراو',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: textSecondary,
                ),
              ),
          ],
        ),
        backgroundColor: isDark ? AppDarkColors.surface : Colors.white,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: border),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'کردارەکان',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (value) {
              if (value == 'all') {
                _markAllRead();
              } else if (value == 'telegram') {
                _showTelegramSettings();
              }
            },
            itemBuilder: (_) => [
              if (unreadCount > 0)
                const PopupMenuItem(
                  value: 'all',
                  child: Row(
                    children: [
                      Icon(
                        Icons.done_all_rounded,
                        size: 19,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 10),
                      Text('هەمووی وەک خوێندراو'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'telegram',
                child: Row(
                  children: [
                    Icon(Icons.telegram, size: 19, color: Colors.blue),
                    SizedBox(width: 10),
                    Text('ڕێکخستنی Telegram'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadNotifications,
        child: _buildBody(
          groupKeys: groupKeys,
          grouped: grouped,
          surface: surface,
          border: border,
          textSecondary: textSecondary,
        ),
      ),
    );
  }

  Widget _buildBody({
    required List<String> groupKeys,
    required Map<String, List<RecordModel>> grouped,
    required Color surface,
    required Color border,
    required Color textSecondary,
  }) {
    if (_isLoading && _notifications.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null && _notifications.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.62,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.wifi_off_rounded,
                      color: Colors.orange,
                      size: 34,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _loadError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textSecondary, height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _loadNotifications,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('دووبارە هەوڵ بدە'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (_notifications.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.62,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.notifications_none_rounded,
                    size: 34,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'هیچ ئاگادارکردنەوەیەک نییە',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      itemCount: groupKeys.length,
      itemBuilder: (context, index) {
        final key = groupKeys[index];
        final items = grouped[key]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
              child: Text(
                key,
                style: TextStyle(
                  color: textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    _buildNotificationRow(items[i]),
                    if (i != items.length - 1)
                      Divider(height: 1, indent: 58, color: border),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildNotificationRow(RecordModel notification) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRead = notification.getBoolValue('is_read');
    final message = notification.getStringValue('message');
    final created = notification.getStringValue('created');
    final type = notification.getStringValue('type');
    final isOverdue = type == 'debt_overdue';

    IconData icon;
    Color accent;
    if (isOverdue) {
      icon = Icons.warning_amber_rounded;
      accent = Colors.red;
    } else if (message.contains('قەرز') ||
        message.contains('وەصڵ') ||
        message.contains('وەسڵ') ||
        message.contains('پارە')) {
      icon = Icons.receipt_long_outlined;
      accent = Colors.orange;
    } else {
      icon = Icons.notifications_none_rounded;
      accent = AppColors.primary;
    }

    final textPrimary =
        isDark ? AppDarkColors.textPrimary : const Color(0xFF1D2939);
    final textSecondary =
        isDark ? AppDarkColors.textSecondary : const Color(0xFF667085);

    return Material(
      color: isRead
          ? Colors.transparent
          : AppColors.primary.withValues(alpha: isDark ? 0.05 : 0.025),
      child: InkWell(
        onTap: () => _markAsRead(notification),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 6, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isRead ? 0.06 : 0.09),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: isRead ? textSecondary : accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                        color: isRead ? textSecondary : textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppHelpers.formatTime(created),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'کردار',
                padding: EdgeInsets.zero,
                iconSize: 19,
                icon: Icon(Icons.more_horiz_rounded, color: textSecondary),
                onSelected: (value) {
                  if (value == 'delete') _confirmDelete(notification);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: Colors.red,
                        ),
                        SizedBox(width: 10),
                        Text('سڕینەوە'),
                      ],
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
