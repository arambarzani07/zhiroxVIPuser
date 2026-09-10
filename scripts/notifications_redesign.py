from pathlib import Path
import re

path = Path('lib/screens/customer/notifications_screen.dart')
text = path.read_text()

text = text.replace(
    "  bool _isLoading = true;\n",
    "  bool _isLoading = true;\n  bool _loadInFlight = false;\n  String? _loadError;\n",
    1,
)

text = re.sub(
    r"  Future<void> _loadNotifications\(\) async \{.*?\n  \}\n\n  Future<void> _markAsRead",
    '''  Future<void> _loadNotifications() async {
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

  Future<void> _markAsRead''',
    text,
    count=1,
    flags=re.S,
)

text = re.sub(
    r"  Future<void> _markAsRead\(RecordModel notification\) async \{.*?\n  \}\n\n  Future<void> _markAllRead",
    '''  Future<void> _markAsRead(RecordModel notification) async {
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

  Future<void> _markAllRead''',
    text,
    count=1,
    flags=re.S,
)

text = re.sub(
    r"  Future<void> _markAllRead\(\) async \{.*?\n  \}\n\n  void _updateDashboardCount",
    '''  Future<void> _markAllRead() async {
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

  void _updateDashboardCount''',
    text,
    count=1,
    flags=re.S,
)

text = text.replace(
    "      final date = DateTime.parse(n.created);\n      final dateOnly = DateTime(date.year, date.month, date.day);\n\n      String key = 'پێشتر';\n      if (dateOnly.isAtSameMomentAs(today)) {\n",
    "      final created = n.getStringValue('created');\n      final date = DateTime.tryParse(created);\n      final dateOnly = date == null ? null : DateTime(date.year, date.month, date.day);\n\n      String key = 'پێشتر';\n      if (dateOnly != null && dateOnly.isAtSameMomentAs(today)) {\n",
    1,
)
text = text.replace(
    "      } else if (dateOnly.isAtSameMomentAs(yesterday)) {\n",
    "      } else if (dateOnly != null && dateOnly.isAtSameMomentAs(yesterday)) {\n",
    1,
)

new_build = r'''  @override
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
'''

text, count = re.subn(
    r"  @override\n  Widget build\(BuildContext context\) \{.*?\n  Future<void> _confirmDelete",
    new_build + "\n  Future<void> _confirmDelete",
    text,
    count=1,
    flags=re.S,
)
if count != 1:
    raise SystemExit('build/card replacement failed')

text = re.sub(
    r"  Future<void> _confirmDelete\(RecordModel n\) async \{.*?\n  \}\n\n  void _showTelegramSettings",
    '''  Future<void> _confirmDelete(RecordModel n) async {
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

  void _showTelegramSettings''',
    text,
    count=1,
    flags=re.S,
)

text = text.replace("AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);", "AppHelpers.showSnackBar(context, 'پەیوەندی تێلیگرام سەرکەوتوو نەبوو.', isError: true);")
text = text.replace("AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);", "AppHelpers.showSnackBar(context, 'نەتوانرا ڕێکخستنەکان پاشەکەوت بکرێن.', isError: true);")

path.write_text(text)
