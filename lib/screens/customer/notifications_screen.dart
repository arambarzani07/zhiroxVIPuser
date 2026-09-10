import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
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
    PBService.pb.collection('notifications').subscribe('*', (e) {
      if (mounted) _loadNotifications();
    });
  }

  Future<void> _loadNotifications() async {
    if (!mounted || _loadInFlight) return;
    _loadInFlight = true;
    final showInitialLoading = _notifications.isEmpty;
    if (showInitialLoading) {
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
          _loadError = 'نەتوانرا ئاگادارکردنەوەکان بار بکرێن. دووبارە هەوڵ بدە.';
        }
      });
    } finally {
      _loadInFlight = false;
    }
  }

  void _setReadState(String id, bool isRead) {
    final index = _notifications.indexWhere((n) => n.id == id);
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
    if (mounted) {
      setState(() => _setReadState(id, true));
    }
    try {
      await PBService.markNotificationRead(id);
      _updateDashboardCount();
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
        .where((n) => !n.getBoolValue('is_read'))
        .toList();
    if (unread.isEmpty || !mounted) return;

    setState(() {
      for (final notification in unread) {
        _setReadState(notification.id, true);
      }
    });

    AppHelpers.showLoadingDialog(context);
    try {
      for (final notification in unread) {
        await PBService.markNotificationRead(notification.id);
      }
      if (!mounted) return;
      Navigator.pop(context);
      _updateDashboardCount();
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

  void _updateDashboardCount() {
    // This might be handled by the dashboard's own creating polling or callback
    // But since we pushed this screen, popping it will trigger the dashboard's "then" callback
  }

  Map<String, List<RecordModel>> _groupNotifications() {
    final Map<String, List<RecordModel>> grouped = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (var n in _notifications) {
      final created = n.getStringValue('created');
      final date = DateTime.tryParse(created);
      final dateOnly = date == null ? null : DateTime(date.year, date.month, date.day);

      String key = 'پێشتر';
      if (dateOnly != null && dateOnly.isAtSameMomentAs(today)) {
        key = 'ئەمڕۆ';
      } else if (dateOnly != null && dateOnly.isAtSameMomentAs(yesterday)) {
        key = 'دوێنێ';
      }

      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(n);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupNotifications();
    final keys = grouped.keys.toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppDarkColors.card : Colors.white;
    final border = isDark ? AppDarkColors.cardBorder : const Color(0xFFEAECF0);
    final textPrimary = isDark ? AppDarkColors.textPrimary : const Color(0xFF1D2939);
    final textSecondary = isDark ? AppDarkColors.textSecondary : const Color(0xFF667085);
    final unreadCount = _notifications.where((n) => !n.getBoolValue('is_read')).length;

    return Scaffold(
      backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF7F8FA),
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
                unreadCount == 0 ? 'هەمووی خوێندراونەتەوە' : '$unreadCount نەخوێندراو',
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
                _showTelegramSettings(context);
              }
            },
            itemBuilder: (context) => [
              if (unreadCount > 0)
                const PopupMenuItem(
                  value: 'all',
                  child: Row(
                    children: [
                      Icon(Icons.done_all_rounded, size: 19, color: AppColors.primary),
                      SizedBox(width: 10),
                      Text('هەمووی وەک خوێندراو'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'telegram',
                child: Row(
                  children: [
                    Icon(Icons.send_outlined, size: 19, color: AppColors.primary),
                    SizedBox(width: 10),
                    Text('ڕێکخستنی تێلیگرام'),
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
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null && _notifications.isEmpty
                ? ListView(
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
                                Container(
                                  width: 52,
                                  height: 52,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(
                                    Icons.wifi_off_rounded,
                                    color: Colors.orange,
                                    size: 25,
                                  ),
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
                  )
                : _notifications.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.62,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.07),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Icon(
                                      Icons.notifications_none_rounded,
                                      size: 24,
                                      color: AppColors.primary,
                                    ),
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
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                        itemCount: keys.length,
                        itemBuilder: (context, index) {
                          final key = keys[index];
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
                      ),
      ),
    );
  }

  Widget _buildNotificationRow(RecordModel n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRead = n.getBoolValue('is_read');
    final message = n.getStringValue('message');
    final created = n.getStringValue('created');
    final type = n.getStringValue('type');
    final isOverdue = type == 'debt_overdue';

    IconData iconData;
    Color accent;
    if (isOverdue) {
      iconData = Icons.warning_amber_rounded;
      accent = Colors.red;
    } else if (message.contains('قەرز') ||
        message.contains('وەصڵ') ||
        message.contains('پارە')) {
      iconData = Icons.receipt_long_outlined;
      accent = Colors.orange;
    } else {
      iconData = Icons.notifications_none_rounded;
      accent = AppColors.primary;
    }

    final textPrimary = isDark ? AppDarkColors.textPrimary : const Color(0xFF1D2939);
    final textSecondary = isDark ? AppDarkColors.textSecondary : const Color(0xFF667085);

    return Material(
      color: isRead
          ? Colors.transparent
          : AppColors.primary.withValues(alpha: isDark ? 0.05 : 0.025),
      child: InkWell(
        onTap: () => _markAsRead(n),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 6, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
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
                      iconData,
                      size: 18,
                      color: isRead ? textSecondary : accent,
                    ),
                  ),
                  if (!isRead)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? AppDarkColors.card : Colors.white,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
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
                  if (value == 'delete') _confirmDelete(n);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
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

  Future<void> _confirmDelete(RecordModel n) async {
    final confirm = await AppHelpers.showConfirmDialog(
      context,
      title: 'سڕینەوە',
      message: 'دڵنیایت لە سڕینەوەی ئەم ئاگادارکردنەوەیە؟',
    );
    if (!confirm || !mounted) return;

    try {
      await PBService.deleteNotification(n.id);
      if (!mounted) return;
      setState(() {
        _notifications.removeWhere((item) => item.id == n.id);
      });
      _updateDashboardCount();
    } catch (_) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        'نەتوانرا ئاگادارکردنەوەکە بسڕدرێتەوە.',
        isError: true,
      );
    }
  }

  void _showTelegramSettings(BuildContext context) {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final botTokenController = TextEditingController(
      text: auth.user?.getStringValue('telegram_bot_token') ?? '',
    );
    final chatIdController = TextEditingController(
      text: auth.user?.getStringValue('telegram_chat_id') ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.telegram, color: Colors.blue),
            SizedBox(width: 10),
            Text('ڕێکخستنی تێلیگرام'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'بۆ وەرگرتنی ئاگادارکردنەوەکان لە تێلیگرام، تکایە زانیاریەکانی خوارەوە پڕبکەرەوە.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showTelegramHelp(context),
              child: const Row(
                children: [
                  Icon(Icons.help_outline, size: 16, color: AppColors.primary),
                  SizedBox(width: 4),
                  Text(
                    'چۆنێتی پەیوەست بوون بە بۆتی مارکێت  و ڕێنمایی',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: botTokenController,
              decoration: const InputDecoration(
                labelText: 'Bot Token',
                hintText: '123456789:ABC...',
                prefixIcon: Icon(Icons.key),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: chatIdController,
              decoration: const InputDecoration(
                labelText: 'Chat ID',
                hintText: '12345678',
                prefixIcon: Icon(Icons.chat),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'پاشگەزبوونەوە',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          OutlinedButton(
            onPressed: () async {
              if (botTokenController.text.isEmpty ||
                  chatIdController.text.isEmpty) {
                AppHelpers.showSnackBar(
                  context,
                  'تکایە هەردوو خانەکە پڕبکەرەوە',
                  isError: true,
                );
                return;
              }
              try {
                AppHelpers.showLoadingDialog(context);
                final success = await PBService.sendTelegramMessage(
                  botTokenController.text.trim(),
                  chatIdController.text.trim(),
                  'تایگیکردنی پەیوەندی... سەرکەوتو بوو ✅',
                );
                if (context.mounted) {
                  Navigator.pop(context); // Close loading
                  if (success) {
                    AppHelpers.showSnackBar(
                      context,
                      'پەیوەندی سەرکەوتوو بوو ✅',
                    );
                  } else {
                    AppHelpers.showSnackBar(
                      context,
                      'پەیوەندی سەرکەوتوو نەبوو ❌\nدڵنیابەرەوە لە زانیاریەکان و بۆتەکە Start بکە',
                      isError: true,
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context); // Close loading
                  AppHelpers.showSnackBar(context, 'پەیوەندی تێلیگرام سەرکەوتوو نەبوو.', isError: true);
                }
              }
            },
            child: const Text('تاقیکردنەوە'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                AppHelpers.showLoadingDialog(context);
                await PBService.updateUser(auth.userId, {
                  'telegram_bot_token': botTokenController.text.trim(),
                  'telegram_chat_id': chatIdController.text.trim(),
                });
                await auth.refreshUser(); // Refresh local user data
                if (context.mounted) {
                  Navigator.pop(context); // Close loading
                  Navigator.pop(context); // Close dialog
                  AppHelpers.showSnackBar(context, 'ڕێکخستنەکان پاشەکەوت کران');
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context); // Close loading
                  AppHelpers.showSnackBar(context, 'پەیوەندی تێلیگرام سەرکەوتوو نەبوو.', isError: true);
                }
              }
            },
            child: const Text('پاشەکەوت کردن'),
          ),
        ],
      ),
    );
  }

  void _showTelegramHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('چۆنێتی بەکارهێنان'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '١. لە تێلیگرام بۆ @BotFather بگەڕێ.\n'
                '٢. دەستپێکردن (Start) بکە و بنووسە /newbot.\n'
                '٣. ناوێک و یوزەرنەیمێک بۆ بۆتەکەت هەڵبژێرە.\n'
                '٤. کۆدی API Token کۆپی بکە و لێرە لە بەشی Bot Token دایبنێ.\n\n'
                '٥. بۆ @userinfobot بگەڕێ و Start بکە.\n'
                '٦. کۆدی Id کۆپی بکە و لە بەشی Chat ID دایبنێ.\n\n'
                '٧. گرنگ: دەبێت بۆتەکەی خۆت Start بکەیت بۆ ئەوەی بتوانێت نامەت بۆ بنێرێت.',
                style: TextStyle(height: 1.6, fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('باشە'),
          ),
        ],
      ),
    );
  }
}
