import 'package:flutter/material.dart';
import 'dart:async';
import 'package:pocketbase/pocketbase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/screens/shared/user_profile_screen.dart';
import 'package:zhirox/screens/shared/add_user_screen.dart';
import 'package:zhirox/screens/shared/add_debt_screen.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/services/connectivity_service.dart';
import 'package:zhirox/services/user_list_layout.dart';

class UserListScreen extends StatefulWidget {
  final String role;
  final String? adminId;

  const UserListScreen({super.key, required this.role, this.adminId});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  List<RecordModel> _users = [];
  bool _isLoading = true;
  String? _loadError;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final Map<String, double> _balances = {};
  final Set<String> _balanceErrors = <String>{};
  final Map<String, Map<String, dynamic>> _customerInbox = {};
  String? _inboxError;
  int _loadGeneration = 0;
  StreamSubscription<bool>? _connectivitySub;
  RealtimeChannel? _inboxRealtimeChannel;
  Timer? _inboxRealtimeDebounce;
  Timer? _customerSearchDebounce;
  bool _inboxRefreshInFlight = false;
  bool _inboxRefreshPending = false;
  bool _isLoadingMore = false;
  bool _hasMoreUsers = false;
  int _totalUsers = 0;
  Map<String, dynamic>? _nextUserCursor;
  String _customerFilter = 'all';

  static const Map<String, String> _customerFilterLabels = {
    'all': 'هەموو',
    'with_debt': 'قەرزدار',
    'debt_free': 'بێ قەرز',
    'active': 'چالاک',
    'inactive': 'ناچالاک',
  };

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUsers();
    });
    _connectivitySub = ConnectivityService.instance.statusStream.listen((online) {
      if (online && mounted) {
        _loadUsers(search: _searchController.text.trim());
      }
    });
    if (widget.role == 'customer') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_subscribeCustomerInboxRealtime());
      });
    }
  }

  @override
  void dispose() {
    _inboxRealtimeDebounce?.cancel();
    _customerSearchDebounce?.cancel();
    final channel = _inboxRealtimeChannel;
    if (channel != null) {
      unawaited(PBService.client.removeChannel(channel));
    }
    _connectivitySub?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String get _adminId {
    if (widget.adminId != null && widget.adminId!.isNotEmpty) {
      return widget.adminId!;
    }
    final auth = context.read<AuthProvider>();
    return auth.adminId;
  }

  bool get _isEmployee => widget.role == 'employee';

  void _onScroll() {
    if (widget.role != 'customer' ||
        !_hasMoreUsers ||
        _isLoadingMore ||
        !_scrollController.hasClients) {
      return;
    }
    if (_scrollController.position.extentAfter < 500) {
      unawaited(
        _loadUsers(
          search: _searchController.text.trim(),
          loadMore: true,
        ),
      );
    }
  }

  RecordModel _customerRecord(Map<String, dynamic> row) {
    final phone = row['phone']?.toString() ?? '';
    return RecordModel.fromJson({
      ...row,
      'id': row['id']?.toString() ?? '',
      'collectionId': '',
      'collectionName': 'users',
      'email': phone.isEmpty ? '' : '$phone@zhirox.local',
      'created': row['created_at']?.toString() ?? '',
      'updated': row['updated_at']?.toString() ?? row['created_at']?.toString() ?? '',
    });
  }

  Future<Map<String, dynamic>> _getCustomerDirectoryPage({
    required String search,
    int limit = 60,
    Map<String, dynamic>? cursor,
  }) async {
    if (_customerFilter == 'all') {
      return PBService.getCustomerDirectoryPage(
        search: search,
        limit: limit,
        cursor: cursor,
      );
    }

    await PBService.ensureInitialized();
    final params = <String, dynamic>{
      'p_search': search.trim(),
      'p_filter': _customerFilter,
      'p_limit': limit.clamp(1, 100),
    };
    final cursorCreatedAt = cursor?['created_at']?.toString() ?? '';
    final cursorId = cursor?['id']?.toString() ?? '';
    if (cursorCreatedAt.isNotEmpty && cursorId.isNotEmpty) {
      params['p_cursor_created_at'] = cursorCreatedAt;
      params['p_cursor_id'] = cursorId;
    }

    final raw = await PBService.client.rpc(
      'get_customer_directory_page_filtered',
      params: params,
    );
    if (raw is! Map) throw Exception('invalid customer directory page');

    final data = Map<String, dynamic>.from(raw);
    final users = <RecordModel>[];
    final inbox = <String, Map<String, dynamic>>{};
    final items = data['items'];
    if (items is List) {
      for (final item in items) {
        if (item is! Map) continue;
        final row = Map<String, dynamic>.from(item);
        final user = _customerRecord(row);
        users.add(user);
        inbox[user.id] = {
          'customer_id': user.id,
          'remaining': row['remaining'],
          'open_debt_count': row['open_debt_count'],
          'last_activity_at': row['last_activity_at'],
          'last_kind': row['last_kind'],
          'last_amount': row['last_amount'],
          'last_preview': row['last_preview'],
          'last_event_type': row['last_event_type'],
          'unread': row['unread'] == true,
        };
      }
    }

    return {
      'items': users,
      'inbox': inbox,
      'totalItems': int.tryParse('${data['total_count'] ?? 0}') ?? 0,
      'hasMore': data['has_more'] == true,
      'nextCursor': data['next_cursor'] is Map
          ? Map<String, dynamic>.from(data['next_cursor'] as Map)
          : null,
    };
  }

  void _selectCustomerFilter(String value) {
    if (_customerFilter == value || !_customerFilterLabels.containsKey(value)) {
      return;
    }
    setState(() => _customerFilter = value);
    unawaited(_loadUsers(search: _searchController.text.trim()));
  }

  List<RecordModel> _dedupeUsersById(Iterable<RecordModel> users) {
    final byId = <String, RecordModel>{};
    final idless = <RecordModel>[];
    for (final user in users) {
      final id = user.id.trim();
      if (id.isEmpty) {
        idless.add(user);
        continue;
      }
      // Keep the latest copy of the same backend row while preserving the
      // original insertion position in Dart's linked map.
      byId[id] = user;
    }
    return <RecordModel>[...byId.values, ...idless];
  }

  Future<void> _loadUsers({String? search, bool loadMore = false}) async {
    if (!mounted) return;
    if (loadMore && (_isLoadingMore || !_hasMoreUsers)) return;
    final generation = ++_loadGeneration;
    setState(() {
      if (loadMore) {
        _isLoadingMore = true;
      } else {
        _isLoading = true;
        _nextUserCursor = null;
      }
      _loadError = null;
    });

    try {
      final adminId = _adminId;
      late final List<RecordModel> users;
      Map<String, Map<String, dynamic>>? pageInbox;
      var totalUsers = 0;
      var hasMoreUsers = false;
      Map<String, dynamic>? nextUserCursor;
      if (widget.role == 'customer') {
        final page = await _getCustomerDirectoryPage(
          search: search ?? '',
          limit: 60,
          cursor: loadMore ? _nextUserCursor : null,
        );
        users = page['items'] as List<RecordModel>;
        pageInbox = page['inbox'] as Map<String, Map<String, dynamic>>;
        totalUsers = page['totalItems'] as int;
        hasMoreUsers = page['hasMore'] == true;
        nextUserCursor = page['nextCursor'] as Map<String, dynamic>?;
      } else {
        users = await PBService.getUsers(
          role: widget.role,
          search: search,
          adminId: adminId.isNotEmpty ? adminId : null,
        );
        totalUsers = users.length;
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _totalUsers = totalUsers;
        _hasMoreUsers = hasMoreUsers;
        _nextUserCursor = nextUserCursor;
        if (loadMore) {
          _users = _dedupeUsersById(<RecordModel>[..._users, ...users]);
        } else {
          _users = _dedupeUsersById(users);
          _customerInbox.clear();
          _balances.clear();
          _balanceErrors.clear();
        }
        if (pageInbox != null) {
          _customerInbox.addAll(pageInbox);
          for (final user in users) {
            final row = pageInbox[user.id];
            _balances[user.id] =
                (row?['remaining'] as num?)?.toDouble() ??
                double.tryParse('${row?['remaining'] ?? ''}') ??
                0;
          }
          _inboxError = null;
        }
        _isLoading = false;
        _isLoadingMore = false;
      });
      if (!loadMore && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        if (!loadMore) _users = [];
        _isLoading = false;
        _isLoadingMore = false;
        final message = AppHelpers.backendErrorMessage(
          error,
          fallback: 'نەتوانرا لیستەکە باربکرێت. دووبارە هەوڵ بدە.',
        );
        if (loadMore) {
          _inboxError = message;
        } else {
          _loadError = message;
        }
      });
    }
  }

  Future<void> _loadCustomerInboxInBackground(
    List<RecordModel> users, {
    int? generation,
  }) async {
    if (_inboxRefreshInFlight) {
      _inboxRefreshPending = true;
      return;
    }

    final ids = users.map((user) => user.id).where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return;
    _inboxRefreshInFlight = true;
    try {
      final rows = await PBService.getCustomerInboxRows(ids);
      if (!mounted || (generation != null && generation != _loadGeneration)) return;
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
        _inboxError = null;
      });
    } catch (error) {
      if (!mounted || (generation != null && generation != _loadGeneration)) return;
      setState(() {
        _customerInbox.clear();
        _balances.clear();
        _balanceErrors
          ..clear()
          ..addAll(ids);
        _inboxError = AppHelpers.backendErrorMessage(
          error,
          fallback: 'نەتوانرا پوختە و باڵانسی کڕیاران باربکرێت. دووبارە هەوڵ بدە.',
        );
        debugPrint(_inboxError);
      });
    } finally {
      _inboxRefreshInFlight = false;
      if (_inboxRefreshPending && mounted) {
        _inboxRefreshPending = false;
        final currentUsers = List<RecordModel>.from(_users);
        if (currentUsers.isNotEmpty) {
          unawaited(
            _loadCustomerInboxInBackground(
              currentUsers,
              generation: _loadGeneration,
            ),
          );
        }
      }
    }
  }

  void _scheduleCustomerSearch(String value) {
    _customerSearchDebounce?.cancel();
    final query = value.trim();
    if (mounted) setState(() {});
    _customerSearchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      unawaited(_loadUsers(search: query));
    });
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

  Future<void> _markFinancialChatReadBestEffort(
    String customerId,
    DateTime? readThrough,
  ) async {
    if (readThrough == null) return;
    try {
      await PBService.markFinancialChatRead(
        customerId,
        readThrough: readThrough,
      );
    } catch (_) {
      if (mounted) _scheduleCustomerInboxRefresh();
    }
  }

  Future<void> _openUserProfile(RecordModel user) async {
    if (widget.role == 'customer') {
      final row = _customerInbox[user.id];
      final readThrough = DateTime.tryParse(
        row?['last_activity_at']?.toString() ?? '',
      );
      if (row != null && row['unread'] == true) {
        setState(() => row['unread'] = false);
      }
      unawaited(_markFinancialChatReadBestEffort(user.id, readThrough));
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canAdd =
        (auth.userRole == 'admin') ||
        (auth.userRole == 'employee' &&
            auth.canAddCustomers &&
            widget.role == 'customer');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pinHeader = shouldPinUserListHeader(widget.role);
    final header = _buildDirectoryHeader(canAdd: canAdd, isDark: isDark);

    return Scaffold(
      backgroundColor: isDark
          ? AppDarkColors.background
          : const Color(0xFFF5F7FA),
      body: Column(
        children: [
          if (pinHeader) header,
          Expanded(
            child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: widget.role == 'customer',
        interactive: true,
        thickness: 4,
        radius: const Radius.circular(8),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
          // ───── Header (scrolls only for non-customer lists) ─────
          if (!pinHeader) SliverToBoxAdapter(child: header),

          // ───── List ─────
          if (!_isLoading &&
              _loadError == null &&
              _users.isNotEmpty &&
              widget.role == 'customer' &&
              _inboxError != null)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: isDark ? 0.14 : 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _inboxError!,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark
                              ? AppDarkColors.textPrimary
                              : const Color(0xFF7A4D00),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _loadCustomerInboxInBackground(
                        List<RecordModel>.from(_users),
                        generation: _loadGeneration,
                      ),
                      child: const Text('هەوڵدانەوە'),
                    ),
                  ],
                ),
              ),
            ),
          _isLoading
              ? const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              : _loadError != null
              ? SliverFillRemaining(child: _buildLoadErrorState())
              : _users.isEmpty
              ? SliverFillRemaining(child: _buildEmptyState())
              : SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    _inboxError == null ? 16 : 10,
                    16,
                    16,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) =>
                          _buildUserCard(_users[index], index, auth),
                      childCount: _users.length,
                    ),
                  ),
                ),

          if (_isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 50)),
          ],
        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectoryHeader({
    required bool canAdd,
    required bool isDark,
  }) {
    return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.88)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title + Add Button + Count
                      Row(
                        children: [
                          Icon(
                            _isEmployee ? Icons.badge : Icons.people,
                            color: Colors.white,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _isEmployee ? 'کارمەندەکان' : 'کڕیارەکان',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          if (!_isLoading)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_totalUsers == 0 ? _users.length : _totalUsers} ${_isEmployee ? 'کارمەند' : 'کڕیار'}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          if (canAdd) ...[
                            const SizedBox(width: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: IconButton(
                                padding: const EdgeInsets.all(8),
                                constraints: const BoxConstraints(),
                                icon: const Icon(
                                  Icons.person_add,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                onPressed: () => _showAddDialog(),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Search Bar
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? AppDarkColors.card : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: isDark
                              ? []
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: TextStyle(
                            color: isDark
                                ? AppDarkColors.textPrimary
                                : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            hintText: 'گەڕان بەدوای ناو یان ژمارە...',
                            hintStyle: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 14,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              color: AppColors.primary,
                              size: 22,
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(
                                      Icons.clear,
                                      size: 18,
                                      color: Colors.grey[400],
                                    ),
                                    onPressed: () {
                                      _customerSearchDebounce?.cancel();
                                      _searchController.clear();
                                      _loadUsers();
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          onChanged: _scheduleCustomerSearch,
                        ),
                      ),
                      if (widget.role == 'customer') ...[
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.filter_list_rounded,
                                color: Colors.white70,
                                size: 19,
                              ),
                              const SizedBox(width: 7),
                              ..._customerFilterLabels.entries.map((entry) {
                                final selected = _customerFilter == entry.key;
                                return Padding(
                                  padding: const EdgeInsetsDirectional.only(end: 7),
                                  child: ChoiceChip(
                                    label: Text(entry.value),
                                    selected: selected,
                                    onSelected: (_) =>
                                        _selectCustomerFilter(entry.key),
                                    showCheckmark: false,
                                    selectedColor: Colors.white,
                                    backgroundColor: const Color(0xFFDCE6FF),
                                    side: BorderSide(
                                      color: selected
                                          ? Colors.white
                                          : const Color(0xFFAFC3FF),
                                      width: selected ? 1.4 : 1,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    labelStyle: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: selected
                                          ? FontWeight.w800
                                          : FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
  }

  // ═══════════════════════════════════════════
  // ── Widgets ──
  // ═══════════════════════════════════════════

  void _showAddDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => AddUserDialog(role: widget.role),
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
          child: child,
        );
      },
    ).then((result) {
      if (result == true) {
        _loadUsers(search: _searchController.text.trim());
      }
    });
  }

  Widget _buildLoadErrorState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 40, color: Colors.orange[400]),
            const SizedBox(height: 12),
            Text(
              _loadError ?? 'نەتوانرا زانیاری باربکرێت',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: isDark ? AppDarkColors.textSecondary : const Color(0xFF667085),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => _loadUsers(search: _searchController.text.trim()),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('دووبارە هەوڵ بدە'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isEmployee ? Icons.badge_outlined : Icons.people_outline,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            AppStrings.noData,
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () =>
                _loadUsers(search: _searchController.text.trim()),
            icon: const Icon(Icons.refresh),
            label: const Text('نوێکردنەوە'),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(RecordModel user, int index, AuthProvider auth) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = user.getStringValue('name');
    final approved = user.getBoolValue('approved');
    final accentColor = AppColors.primary;
    final balance = _balances[user.id] ?? 0;
    final balanceUnavailable = _balanceErrors.contains(user.id);
    final inbox = _customerInbox[user.id];
    final unread = !_isEmployee && inbox?['unread'] == true;
    final canManageCustomer = widget.role == 'customer' &&
        (auth.userRole == 'admin' || auth.userRole == 'employee');

    return Container(
      key: ValueKey<String>('user-card-${user.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unread
              ? AppColors.primary.withValues(alpha: 0.28)
              : isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFE9EDF3),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openUserProfile(user),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: accentColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: isDark
                                    ? AppDarkColors.textPrimary
                                    : const Color(0xFF1F2937),
                              ),
                            ),
                          ),
                          if (unread) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                          if (!_isEmployee && _inboxTimeLabel(inbox).isNotEmpty) ...[
                            const SizedBox(width: 7),
                            Text(
                              _inboxTimeLabel(inbox),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                                color: unread
                                    ? AppColors.primary
                                    : (isDark
                                        ? AppDarkColors.textSecondary
                                        : const Color(0xFF98A2B3)),
                              ),
                              textDirection: TextDirection.ltr,
                            ),
                          ],
                          if (_isEmployee && approved)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'چالاک',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (_isEmployee) ...[
                        const SizedBox(height: 4),
                        Text(
                          user.getStringValue('phone').isEmpty
                              ? 'ژمارە مۆبایل نەدراوە'
                              : user.getStringValue('phone'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            color: isDark
                                ? AppDarkColors.textSecondary
                                : const Color(0xFF98A2B3),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                      if (!_isEmployee) ...[
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
                                fontWeight: FontWeight.w600,
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
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (canManageCustomer)
                  PopupMenuButton<String>(
                    tooltip: 'کردارەکان',
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      if (value == 'debt') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddDebtScreen(customerId: user.id),
                          ),
                        ).then(
                          (_) => _loadUsers(
                            search: _searchController.text.trim(),
                          ),
                        );
                      } else if (value == 'payment') {
                        unawaited(
                          _markFinancialChatReadBestEffort(
                            user.id,
                            DateTime.tryParse(
                              inbox?['last_activity_at']?.toString() ?? '',
                            ),
                          ),
                        );
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UserProfileScreen(
                              userId: user.id,
                              openFinancialChat: true,
                            ),
                          ),
                        ).then(
                          (_) => _loadUsers(
                            search: _searchController.text.trim(),
                          ),
                        );
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem<String>(
                        value: 'debt',
                        child: Row(
                          children: [
                            Icon(Icons.add_card_rounded, size: 20),
                            SizedBox(width: 10),
                            Text('قەرز زیاد بکە'),
                          ],
                        ),
                      ),
                      if (balance > 0)
                        const PopupMenuItem<String>(
                          value: 'payment',
                          child: Row(
                            children: [
                              Icon(Icons.payments_outlined, size: 20),
                              SizedBox(width: 10),
                              Text('پارەدانەوە'),
                            ],
                          ),
                        ),
                    ],
                    icon: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.more_horiz_rounded,
                        color: accentColor,
                        size: 22,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_left_rounded,
                    color: isDark ? Colors.grey[600] : Colors.grey[350],
                    size: 22,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
