from pathlib import Path
import os

root = Path(os.environ.get('REPO_ROOT', Path.cwd())).resolve()


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label} anchor count={count}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')

# PBService: batch Customer Inbox summary + persistent read marker.
pb_path = root / 'lib/services/pb_service.dart'
pb_anchor = "  static Future<Map<String, dynamic>> getCustomerFinanceSnapshot(\n"
pb_insert = r'''  static Future<Map<String, Map<String, dynamic>>> getCustomerInboxRows(
    List<String> customerIds,
  ) async {
    if (customerIds.isEmpty) return const {};
    await ensureInitialized();
    final raw = await client.rpc(
      'get_customer_inbox_rows',
      params: {'p_customer_ids': customerIds},
    );
    if (raw is! List) throw Exception('invalid customer inbox rows');
    final result = <String, Map<String, dynamic>>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final customerId = row['customer_id']?.toString() ?? '';
      if (customerId.isNotEmpty) result[customerId] = row;
    }
    return result;
  }

  static Future<void> markFinancialChatRead(String customerId) async {
    await ensureInitialized();
    await client.rpc(
      'mark_financial_chat_read',
      params: {'p_customer_id': customerId},
    );
  }

'''
replace_once(pb_path, pb_anchor, pb_insert + pb_anchor, 'pb customer inbox')

# Customer list: remove N+1 balance loading and turn rows into realtime chat inbox cards.
list_path = root / 'lib/screens/shared/user_list_screen.dart'
replace_once(
    list_path,
    "import 'package:pocketbase/pocketbase.dart';\n",
    "import 'package:pocketbase/pocketbase.dart';\nimport 'package:supabase_flutter/supabase_flutter.dart';\n",
    'user list supabase import',
)
replace_once(
    list_path,
    "  final Map<String, double> _balances = {};\n  final Set<String> _balanceErrors = <String>{};\n  StreamSubscription<bool>? _connectivitySub;\n",
    "  final Map<String, double> _balances = {};\n  final Set<String> _balanceErrors = <String>{};\n  final Map<String, Map<String, dynamic>> _customerInbox = {};\n  String? _inboxError;\n  int _loadGeneration = 0;\n  StreamSubscription<bool>? _connectivitySub;\n  RealtimeChannel? _inboxRealtimeChannel;\n  Timer? _inboxRealtimeDebounce;\n",
    'user list fields',
)
replace_once(
    list_path,
    "    _connectivitySub = ConnectivityService.instance.statusStream.listen((online) {\n      if (online && mounted) _loadUsers();\n    });\n",
    "    _connectivitySub = ConnectivityService.instance.statusStream.listen((online) {\n      if (online && mounted) _loadUsers();\n    });\n    if (widget.role == 'customer') {\n      WidgetsBinding.instance.addPostFrameCallback((_) {\n        if (mounted) unawaited(_subscribeCustomerInboxRealtime());\n      });\n    }\n",
    'user list init realtime',
)
replace_once(
    list_path,
    "  void dispose() {\n    _connectivitySub?.cancel();\n    _searchController.dispose();\n    super.dispose();\n  }\n",
    "  void dispose() {\n    _inboxRealtimeDebounce?.cancel();\n    final channel = _inboxRealtimeChannel;\n    if (channel != null) {\n      unawaited(PBService.client.removeChannel(channel));\n    }\n    _connectivitySub?.cancel();\n    _searchController.dispose();\n    super.dispose();\n  }\n",
    'user list dispose',
)
replace_once(
    list_path,
    "  Future<void> _loadUsers({String? search}) async {\n    if (!mounted) return;\n    setState(() {\n",
    "  Future<void> _loadUsers({String? search}) async {\n    if (!mounted) return;\n    final generation = ++_loadGeneration;\n    setState(() {\n",
    'user list generation start',
)
replace_once(
    list_path,
    "      if (!mounted) return;\n      setState(() {\n        _users = users;\n        _isLoading = false;\n      });\n\n      if (widget.role == 'customer' && users.isNotEmpty) {\n        unawaited(_loadBalancesInBackground());\n      }\n",
    "      if (!mounted || generation != _loadGeneration) return;\n      setState(() {\n        _users = users;\n        _isLoading = false;\n      });\n\n      if (widget.role == 'customer' && users.isNotEmpty) {\n        unawaited(_loadCustomerInboxInBackground(users, generation: generation));\n      }\n",
    'user list load inbox call',
)
old_balance_method = r'''  /// Load all customer balances in parallel (non-blocking)
  Future<void> _loadBalancesInBackground() async {
    final usersCopy = List<RecordModel>.from(_users);
    await Future.wait(
      usersCopy.map((user) async {
        try {
          final balance = await PBService.getCustomerBalance(user.id);
          _balances[user.id] = balance;
          _balanceErrors.remove(user.id);
        } catch (_) {
          _balances.remove(user.id);
          _balanceErrors.add(user.id);
        }
      }),
    );
    if (mounted) setState(() {}); // Refresh UI with loaded balances
  }

'''
new_inbox_methods = r'''  Future<void> _loadCustomerInboxInBackground(
    List<RecordModel> users, {
    int? generation,
  }) async {
    final ids = users.map((user) => user.id).where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return;
    try {
      final rows = await PBService.getCustomerInboxRows(ids);
      if (!mounted || (generation != null && generation != _loadGeneration)) return;
      final sorted = List<RecordModel>.from(_users);
      DateTime? activityFor(String id) =>
          DateTime.tryParse(rows[id]?['last_activity_at']?.toString() ?? '');
      sorted.sort((a, b) {
        final aAt = activityFor(a.id);
        final bAt = activityFor(b.id);
        if (aAt == null && bAt == null) {
          return a.getStringValue('name').compareTo(b.getStringValue('name'));
        }
        if (aAt == null) return 1;
        if (bAt == null) return -1;
        return bAt.compareTo(aAt);
      });
      setState(() {
        _customerInbox
          ..clear()
          ..addAll(rows);
        _balances.clear();
        _balanceErrors.clear();
        for (final user in _users) {
          final row = rows[user.id];
          if (row == null) {
            _balanceErrors.add(user.id);
            continue;
          }
          _balances[user.id] = (row['remaining'] as num?)?.toDouble() ??
              double.tryParse('${row['remaining'] ?? ''}') ??
              0;
        }
        _users = sorted;
        _inboxError = null;
      });
    } catch (_) {
      if (!mounted || (generation != null && generation != _loadGeneration)) return;
      setState(() {
        _customerInbox.clear();
        _balances.clear();
        _balanceErrors
          ..clear()
          ..addAll(ids);
        _inboxError = 'نەتوانرا پوختەی چاتی کڕیاران باربکرێت';
      });
    }
  }

  Future<void> _subscribeCustomerInboxRealtime() async {
    try {
      await PBService.ensureInitialized();
      if (!mounted || widget.role != 'customer') return;
      final previous = _inboxRealtimeChannel;
      if (previous != null) {
        try {
          await PBService.client.removeChannel(previous);
        } catch (_) {}
      }
      final channel = PBService.client
          .channel('customer-inbox:${DateTime.now().microsecondsSinceEpoch}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'financial_events',
            callback: (_) => _scheduleCustomerInboxRefresh(),
          )
          .subscribe();
      if (!mounted) {
        try {
          await PBService.client.removeChannel(channel);
        } catch (_) {}
        return;
      }
      _inboxRealtimeChannel = channel;
    } catch (_) {
      // Explicit reconnect/load remains available; never fake cached success.
    }
  }

  void _scheduleCustomerInboxRefresh() {
    if (!mounted || widget.role != 'customer') return;
    _inboxRealtimeDebounce?.cancel();
    _inboxRealtimeDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted || _users.isEmpty) return;
      unawaited(
        _loadCustomerInboxInBackground(
          List<RecordModel>.from(_users),
          generation: _loadGeneration,
        ),
      );
    });
  }

  String _inboxTimeLabel(Map<String, dynamic>? row) {
    final parsed = DateTime.tryParse(row?['last_activity_at']?.toString() ?? '');
    if (parsed == null) return '';
    final at = parsed.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    if (day == today) {
      return '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    }
    if (today.difference(day).inDays == 1) return 'دوێنێ';
    if (at.year == now.year) return '${at.month}/${at.day}';
    return '${at.year}/${at.month}/${at.day}';
  }

  String _inboxPreview(Map<String, dynamic>? row) {
    if (row == null || row['last_activity_at'] == null) return 'هێشتا مامەڵەی دارایی نییە';
    final kind = row['last_kind']?.toString() ?? '';
    final eventType = row['last_event_type']?.toString() ?? '';
    final amount = (row['last_amount'] as num?)?.toDouble() ??
        double.tryParse('${row['last_amount'] ?? ''}') ??
        0;
    final detail = row['last_preview']?.toString().trim() ?? '';
    String title;
    if (kind == 'debt') {
      title = 'قەرز ${AppHelpers.formatCurrency(amount)}';
    } else if (kind == 'payment') {
      title = 'پارەدانەوە ${AppHelpers.formatCurrency(amount)}';
    } else {
      switch (eventType) {
        case 'debt_created':
          title = 'قەرز زیادکرا';
          break;
        case 'debt_updated':
          title = 'قەرز دەستکاری کرا';
          break;
        case 'debt_deleted':
          title = 'قەرز سڕایەوە';
          break;
        case 'payment_created':
          title = 'پارەدانەوە تۆمارکرا';
          break;
        case 'payment_updated':
          title = 'پارەدانەوە دەستکاری کرا';
          break;
        case 'payment_deleted':
          title = 'پارەدانەوە سڕایەوە';
          break;
        default:
          title = 'مامەڵەی دارایی نوێ';
      }
    }
    if (detail.isEmpty || detail == title) return title;
    return '$title • $detail';
  }

  Future<void> _openUserProfile(RecordModel user) async {
    if (widget.role == 'customer') {
      final row = _customerInbox[user.id];
      if (row != null && row['unread'] == true) {
        setState(() => row['unread'] = false);
      }
      unawaited(PBService.markFinancialChatRead(user.id));
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userId: user.id,
          openFinancialChat: widget.role == 'customer',
        ),
      ),
    );
    if (mounted) _loadUsers(search: _searchController.text.trim());
  }

'''
replace_once(list_path, old_balance_method, new_inbox_methods, 'user list inbox methods')

# Card locals and border state.
replace_once(
    list_path,
    "    final balance = _balances[user.id] ?? 0;\n    final balanceUnavailable = _balanceErrors.contains(user.id);\n",
    "    final balance = _balances[user.id] ?? 0;\n    final balanceUnavailable = _balanceErrors.contains(user.id);\n    final inbox = _customerInbox[user.id];\n    final unread = !_isEmployee && inbox?['unread'] == true;\n",
    'user list card inbox locals',
)
replace_once(
    list_path,
    "          color: isDark\n              ? Colors.white.withValues(alpha: 0.06)\n              : const Color(0xFFE9EDF3),\n",
    "          color: unread\n              ? AppColors.primary.withValues(alpha: 0.28)\n              : isDark\n                  ? Colors.white.withValues(alpha: 0.06)\n                  : const Color(0xFFE9EDF3),\n",
    'user list unread border',
)
old_tap = r'''          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserProfileScreen(
                  userId: user.id,
                  openFinancialChat: widget.role == 'customer',
                ),
              ),
            ).then((_) => _loadUsers());
          },
'''
replace_once(
    list_path,
    old_tap,
    "          onTap: () => _openUserProfile(user),\n",
    'user list open chat',
)
# Add unread dot/time to name row.
replace_once(
    list_path,
    "                          if (_isEmployee && approved)\n",
    "                          if (unread) ...[\n                            const SizedBox(width: 6),\n                            Container(\n                              width: 8,\n                              height: 8,\n                              decoration: const BoxDecoration(\n                                color: AppColors.primary,\n                                shape: BoxShape.circle,\n                              ),\n                            ),\n                          ],\n                          if (!_isEmployee && _inboxTimeLabel(inbox).isNotEmpty) ...[\n                            const SizedBox(width: 7),\n                            Text(\n                              _inboxTimeLabel(inbox),\n                              style: TextStyle(\n                                fontSize: 10.5,\n                                fontWeight: unread ? FontWeight.w700 : FontWeight.w500,\n                                color: unread\n                                    ? AppColors.primary\n                                    : (isDark\n                                        ? AppDarkColors.textSecondary\n                                        : const Color(0xFF98A2B3)),\n                              ),\n                              textDirection: TextDirection.ltr,\n                            ),\n                          ],\n                          if (_isEmployee && approved)\n",
    'user list unread header',
)
old_customer_balance = r'''                      if (!_isEmployee) ...[
                        const SizedBox(height: 5),
                        Text(
                          balanceUnavailable
                              ? 'ماوە: نەتوانرا باربکرێت'
                              : _balances.containsKey(user.id)
                                  ? 'ماوە: ${AppHelpers.formatCurrency(balance)}'
                                  : 'ماوە: ...',
                          style: TextStyle(
                            color: balanceUnavailable
                                ? Colors.orange[500]
                                : !_balances.containsKey(user.id)
                                    ? Colors.grey[400]
                                    : balance > 0
                                        ? Colors.red[500]
                                        : Colors.green[500],
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
'''
new_customer_inbox = r'''                      if (!_isEmployee) ...[
                        const SizedBox(height: 4),
                        Text(
                          _inboxPreview(inbox),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unread
                                ? (isDark
                                    ? AppDarkColors.textPrimary
                                    : const Color(0xFF344054))
                                : (isDark
                                    ? AppDarkColors.textSecondary
                                    : const Color(0xFF98A2B3)),
                            fontSize: 11.5,
                            fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              balanceUnavailable
                                  ? 'ماوە: نەتوانرا باربکرێت'
                                  : _balances.containsKey(user.id)
                                      ? 'ماوە: ${AppHelpers.formatCurrency(balance)}'
                                      : 'ماوە: ...',
                              style: TextStyle(
                                color: balanceUnavailable
                                    ? Colors.orange[500]
                                    : !_balances.containsKey(user.id)
                                        ? Colors.grey[400]
                                        : balance > 0
                                            ? Colors.red[500]
                                            : Colors.green[500],
                                fontSize: 11.5,
                                fontWeight: FontWeight.w650,
                              ),
                            ),
                            if (inbox != null && (inbox['open_debt_count'] as num? ?? 0) > 0) ...[
                              const SizedBox(width: 7),
                              Text(
                                '${inbox['open_debt_count']} قەرزی کراوە',
                                style: TextStyle(
                                  color: isDark
                                      ? AppDarkColors.textSecondary
                                      : const Color(0xFF98A2B3),
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
'''
replace_once(
    list_path,
    old_customer_balance,
    new_customer_inbox,
    'user list customer inbox body',
)
# Popup payment should also clear unread state before opening chat.
replace_once(
    list_path,
    "                      } else if (value == 'payment') {\n                        Navigator.push(\n",
    "                      } else if (value == 'payment') {\n                        unawaited(PBService.markFinancialChatRead(user.id));\n                        Navigator.push(\n",
    'user list payment read marker',
)

# Keep analyzer from flagging the explicit fail-closed inbox message as dead state.
replace_once(
    list_path,
    "        _inboxError = 'نەتوانرا پوختەی چاتی کڕیاران باربکرێت';\n",
    "        _inboxError = 'نەتوانرا پوختەی چاتی کڕیاران باربکرێت';\n        debugPrint(_inboxError);\n",
    'user list inbox error use',
)

print('Customer Inbox Phase 5 patch prepared successfully')
