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
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final auth = context.read<AuthProvider>();
      if (auth.userId.isEmpty) return;
      // Fetch sorted by created desc
      _notifications = await PBService.getNotifications(auth.userId);
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _markAsRead(RecordModel notification) async {
    if (notification.getBoolValue('is_read')) return;
    try {
      await PBService.markNotificationRead(notification.id);
      setState(() {
        final index = _notifications.indexWhere((n) => n.id == notification.id);
        if (index != -1) {
          final old = _notifications[index];
          final oldJson = old.toJson();
          if (oldJson.containsKey('is_read')) {
            oldJson['is_read'] = true;
          } else {
            Map<String, dynamic> data = old.data; // data field
            if (data.containsKey('is_read')) {
              data['is_read'] = true;
              oldJson['data'] = data;
            }
            oldJson['is_read'] = true;
          }
          _notifications[index] = RecordModel.fromJson(oldJson);
        }
      });
      _updateDashboardCount();
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          'هەڵە لە خوێندنەوەی ئاگادارکردنەوە: $e',
          isError: true,
        );
      }
    }
  }

  Future<void> _markAllRead() async {
    try {
      AppHelpers.showLoadingDialog(context);
      final unread = _notifications.where((n) => !n.getBoolValue('is_read'));
      for (var n in unread) {
        await PBService.markNotificationRead(n.id);
      }
      Navigator.pop(context); // Close loading
      _loadNotifications();
      _updateDashboardCount();
    } catch (_) {
      Navigator.pop(context);
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
      final date = DateTime.parse(n.created);
      final dateOnly = DateTime(date.year, date.month, date.day);

      String key = 'پێشتر';
      if (dateOnly.isAtSameMomentAs(today)) {
        key = 'ئەمڕۆ';
      } else if (dateOnly.isAtSameMomentAs(yesterday)) {
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
    final keys = grouped.keys
        .toList(); // Order: Today, Yesterday, Earlier (due to sort)
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppDarkColors.background
          : const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'ئاگادارکردنەوەکان',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: isDark ? AppDarkColors.surface : Colors.white,
        foregroundColor: isDark ? AppDarkColors.textPrimary : Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.telegram, color: Colors.blue, size: 28),
            tooltip: 'ڕێکخستنی تێلیگرام',
            onPressed: () => _showTelegramSettings(context),
          ),
          if (_notifications.any((n) => !n.getBoolValue('is_read')))
            IconButton(
              icon: const Icon(Icons.done_all, color: AppColors.primary),
              tooltip: 'خوێندنەوەی هەمووی',
              onPressed: _markAllRead,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.notifications_off_outlined,
                      size: 48,
                      color: Colors.blue[200],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'هیچ ئاگادارکردنەوەیەک نییە',
                    style: TextStyle(color: Colors.grey[500], fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: keys.length,
              itemBuilder: (context, index) {
                final key = keys[index];
                final items = grouped[key]!;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 4,
                      ),
                      child: Text(
                        key,
                        style: TextStyle(
                          color: isDark
                              ? AppDarkColors.textSecondary
                              : Colors.grey[600],
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    ...items.map((n) => _buildNotificationCard(n)),
                    const SizedBox(height: 10),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildNotificationCard(RecordModel n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRead = n.getBoolValue('is_read');
    final message = n.getStringValue('message');
    final created = n.getStringValue('created');
    final type = n.getStringValue('type');

    // Determine Icon and Color based on type
    final bool isOverdue = type == 'debt_overdue';
    IconData iconData;
    Color iconColor;

    if (isOverdue) {
      iconData = Icons.warning_rounded;
      iconColor = Colors.red;
    } else if (message.contains('قەرز') ||
        message.contains('وەصڵ') ||
        message.contains('پارە')) {
      iconData = Icons.receipt_long_rounded;
      iconColor = Colors.orange;
    } else {
      iconData = Icons.notifications_none_rounded;
      iconColor = Colors.blue;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isOverdue
            ? (isDark ? const Color(0xFF2A1520) : const Color(0xFFFFF5F5))
            : (isDark ? AppDarkColors.card : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: isOverdue
            ? Border.all(color: Colors.red.withOpacity(0.3), width: 1.5)
            : (isDark ? Border.all(color: AppDarkColors.cardBorder) : null),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: isOverdue
                      ? Colors.red.withOpacity(0.08)
                      : Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _markAsRead(n),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isRead
                        ? Colors.grey.withOpacity(0.1)
                        : iconColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    iconData,
                    size: 24,
                    color: isRead ? Colors.grey : iconColor,
                  ),
                ),
                const SizedBox(width: 16),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              message,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isRead
                                    ? FontWeight.normal
                                    : FontWeight.bold,
                                color: isRead
                                    ? (isDark
                                          ? AppDarkColors.textSecondary
                                          : Colors.grey[800])
                                    : (isDark
                                          ? AppDarkColors.textPrimary
                                          : Colors.black87),
                                height: 1.5,
                              ),
                            ),
                          ),
                          if (!isRead)
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppHelpers.formatTime(created), // Show Time
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),

                // Delete Button
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                  onPressed: () => _confirmDelete(n),
                ),
              ],
            ),
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

    if (confirm) {
      try {
        await PBService.deleteNotification(n.id);
        setState(() {
          _notifications.removeWhere((item) => item.id == n.id);
        });
        _updateDashboardCount();
      } catch (e) {
        if (mounted) {
          AppHelpers.showSnackBar(
            context,
            'هەڵەیەک ڕوویدا لە کاتی سڕینەوە',
            isError: true,
          );
        }
      }
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
                  AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);
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
                  AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);
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
