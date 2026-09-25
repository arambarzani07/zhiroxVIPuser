import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zhirox/services/connectivity_service.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/helpers.dart';

abstract class CustomerDirectoryGateway {
  const CustomerDirectoryGateway();

  Future<Map<String, dynamic>> getCustomerPage({
    required String search,
    required String filter,
    required int limit,
    Map<String, dynamic>? cursor,
  });

  Future<List<RecordModel>> getUsers({
    required String role,
    required String search,
    required String adminId,
  });

  Future<List<RecordModel>> getPinnedCustomers({required String search});

  Future<Map<String, Map<String, dynamic>>> getInboxRows(
    List<String> customerIds,
  );

  Future<void> markFinancialChatRead(
    String customerId, {
    required DateTime readThrough,
  });
}

class PBServiceCustomerDirectoryGateway implements CustomerDirectoryGateway {
  const PBServiceCustomerDirectoryGateway();

  RecordModel _customerRecord(Map<String, dynamic> row) {
    final phone = row['phone']?.toString() ?? '';
    return RecordModel.fromJson({
      ...row,
      'id': row['id']?.toString() ?? '',
      'collectionId': '',
      'collectionName': 'users',
      'email': phone.isEmpty ? '' : '$phone@zhirox.local',
      'created': row['created_at']?.toString() ?? '',
      'updated':
          row['updated_at']?.toString() ?? row['created_at']?.toString() ?? '',
    });
  }

  @override
  Future<Map<String, dynamic>> getCustomerPage({
    required String search,
    required String filter,
    required int limit,
    Map<String, dynamic>? cursor,
  }) async {
    if (filter == 'all') {
      return PBService.getCustomerDirectoryPage(
        search: search,
        limit: limit,
        cursor: cursor,
      );
    }

    await PBService.ensureInitialized();
    final params = <String, dynamic>{
      'p_search': search.trim(),
      'p_filter': filter,
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
    if (raw is! Map) {
      throw const FormatException('invalid customer directory page');
    }

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

  @override
  Future<List<RecordModel>> getUsers({
    required String role,
    required String search,
    required String adminId,
  }) {
    return PBService.getUsers(
      role: role,
      search: search.isEmpty ? null : search,
      adminId: adminId.isEmpty ? null : adminId,
    );
  }

  @override
  Future<List<RecordModel>> getPinnedCustomers({required String search}) {
    return PBService.getPinnedCustomers(search: search);
  }

  @override
  Future<Map<String, Map<String, dynamic>>> getInboxRows(
    List<String> customerIds,
  ) {
    return PBService.getCustomerInboxRows(customerIds);
  }

  @override
  Future<void> markFinancialChatRead(
    String customerId, {
    required DateTime readThrough,
  }) {
    return PBService.markFinancialChatRead(
      customerId,
      readThrough: readThrough,
    );
  }
}

class CustomerDirectoryController extends ChangeNotifier {
  CustomerDirectoryController({
    required this.role,
    required this.adminId,
    CustomerDirectoryGateway? gateway,
    this.observeConnectivity = true,
    this.subscribeRealtime = true,
  }) : gateway = gateway ?? const PBServiceCustomerDirectoryGateway();

  static const Map<String, String> filterLabels = {
    'all': 'هەموو',
    'with_debt': 'قەرزدار',
    'debt_free': 'بێ قەرز',
    'active': 'چالاک',
    'inactive': 'ناچالاک',
  };

  final String role;
  final String adminId;
  final CustomerDirectoryGateway gateway;
  final bool observeConnectivity;
  final bool subscribeRealtime;

  List<RecordModel> _users = const [];
  Map<String, double> _balances = const {};
  Set<String> _balanceErrors = const {};
  Map<String, Map<String, dynamic>> _inbox = const {};

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _totalUsers = 0;
  String? _loadError;
  String? _inboxError;
  Map<String, dynamic>? _nextCursor;
  String _filter = 'all';
  String _search = '';
  int _generation = 0;

  StreamSubscription<bool>? _connectivitySub;
  RealtimeChannel? _inboxRealtimeChannel;
  Timer? _searchDebounce;
  Timer? _inboxRealtimeDebounce;
  bool _inboxRefreshInFlight = false;
  bool _inboxRefreshPending = false;
  bool _disposed = false;

  List<RecordModel> get users => _users;
  Map<String, double> get balances => _balances;
  Set<String> get balanceErrors => _balanceErrors;
  Map<String, Map<String, dynamic>> get inbox => _inbox;
  bool get isLoading => _loading;
  bool get isLoadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  int get totalUsers => _totalUsers;
  String? get loadError => _loadError;
  String? get inboxError => _inboxError;
  String get filter => _filter;
  String get search => _search;
  bool get isCustomerDirectory => role == 'customer';

  Future<void> initialize() async {
    if (observeConnectivity) {
      _connectivitySub =
          ConnectivityService.instance.statusStream.listen((online) {
        if (online && !_disposed) {
          unawaited(load(search: _search));
        }
      });
    }
    if (isCustomerDirectory && subscribeRealtime) {
      unawaited(_subscribeInboxRealtime());
    }
    await load();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchDebounce?.cancel();
    _inboxRealtimeDebounce?.cancel();
    _connectivitySub?.cancel();
    final channel = _inboxRealtimeChannel;
    if (channel != null) {
      unawaited(PBService.client.removeChannel(channel));
    }
    super.dispose();
  }

  void scheduleSearch(String value) {
    _searchDebounce?.cancel();
    _search = value.trim();
    _safeNotify();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (_disposed) return;
      unawaited(load(search: _search));
    });
  }

  Future<void> clearSearch() async {
    _searchDebounce?.cancel();
    _search = '';
    await load(search: '');
  }

  Future<void> selectFilter(String value) async {
    if (!filterLabels.containsKey(value) || value == _filter) return;
    _filter = value;
    _safeNotify();
    await load(search: _search);
  }

  Future<void> refresh() => load(search: _search);

  Future<void> loadMore() => load(search: _search, loadMore: true);

  List<RecordModel> _dedupe(Iterable<RecordModel> users) {
    final byId = <String, RecordModel>{};
    final idless = <RecordModel>[];
    for (final user in users) {
      final id = user.id.trim();
      if (id.isEmpty) {
        idless.add(user);
      } else {
        byId[id] = user;
      }
    }
    return <RecordModel>[...byId.values, ...idless];
  }

  Future<void> load({String? search, bool loadMore = false}) async {
    if (_disposed) return;
    if (loadMore && (_loadingMore || !_hasMore)) return;

    final requestedSearch = search?.trim() ?? _search;
    _search = requestedSearch;
    final generation = ++_generation;

    if (loadMore) {
      _loadingMore = true;
    } else {
      _loading = true;
      _nextCursor = null;
    }
    _loadError = null;
    _safeNotify();

    try {
      late List<RecordModel> users;
      Map<String, Map<String, dynamic>>? pageInbox;
      var totalUsers = 0;
      var hasMore = false;
      Map<String, dynamic>? nextCursor;

      if (isCustomerDirectory) {
        final page = await gateway.getCustomerPage(
          search: requestedSearch,
          filter: _filter,
          limit: 60,
          cursor: loadMore ? _nextCursor : null,
        );
        users = List<RecordModel>.from(page['items'] as List);
        pageInbox = Map<String, Map<String, dynamic>>.from(
          page['inbox'] as Map,
        );
        totalUsers = page['totalItems'] as int;
        hasMore = page['hasMore'] == true;
        nextCursor = page['nextCursor'] as Map<String, dynamic>?;

        if (!loadMore && _filter == 'all') {
          final pinned =
              await gateway.getPinnedCustomers(search: requestedSearch);
          if (pinned.isNotEmpty) {
            final pinnedIds = pinned.map((item) => item.id).toSet();
            users = _dedupe([
              ...pinned,
              ...users.where((item) => !pinnedIds.contains(item.id)),
            ]);
          }
        }
      } else {
        users = await gateway.getUsers(
          role: role,
          search: requestedSearch,
          adminId: adminId,
        );
        totalUsers = users.length;
      }

      if (_disposed || generation != _generation) return;

      _totalUsers = totalUsers;
      _hasMore = hasMore;
      _nextCursor = nextCursor;

      if (loadMore) {
        _users = _dedupe([..._users, ...users]);
      } else {
        _users = _dedupe(users);
        _inbox = {};
        _balances = {};
        _balanceErrors = {};
      }

      if (pageInbox != null) {
        final merged = Map<String, Map<String, dynamic>>.from(_inbox)
          ..addAll(pageInbox);
        _inbox = merged;
        final balances = Map<String, double>.from(_balances);
        for (final user in users) {
          final row = pageInbox[user.id];
          balances[user.id] = _number(row?['remaining']);
        }
        _balances = balances;
        _inboxError = null;
      }

      _loading = false;
      _loadingMore = false;
      _safeNotify();

      if (!loadMore && isCustomerDirectory && _users.isNotEmpty) {
        unawaited(refreshInbox(generation: generation));
      }
    } catch (error) {
      if (_disposed || generation != _generation) return;
      final restricted = PBService.isServiceRestrictionError(error);
      if (!loadMore && !restricted) _users = const [];
      _loading = false;
      _loadingMore = false;
      final message = AppHelpers.backendErrorMessage(
        error,
        fallback: 'نەتوانرا لیستی کڕیاران باربکرێت. دووبارە هەوڵ بدە.',
      );
      if (loadMore) {
        _inboxError = message;
      } else {
        _loadError = message;
      }
      _safeNotify();
    }
  }

  Future<void> refreshInbox({int? generation}) async {
    if (_disposed || !isCustomerDirectory) return;
    if (_inboxRefreshInFlight) {
      _inboxRefreshPending = true;
      return;
    }

    final ids = _users
        .map((user) => user.id)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) return;

    _inboxRefreshInFlight = true;
    try {
      final rows = await gateway.getInboxRows(ids);
      if (_disposed || (generation != null && generation != _generation)) {
        return;
      }

      _inbox = Map<String, Map<String, dynamic>>.from(rows);
      final balances = <String, double>{};
      final errors = <String>{};
      for (final user in _users) {
        final row = rows[user.id];
        if (row == null) {
          errors.add(user.id);
        } else {
          balances[user.id] = _number(row['remaining']);
        }
      }
      _balances = balances;
      _balanceErrors = errors;
      _inboxError = null;
      _safeNotify();
    } catch (error) {
      if (_disposed || (generation != null && generation != _generation)) {
        return;
      }
      final restricted = PBService.isServiceRestrictionError(error);
      if (!restricted) {
        _inbox = {};
        _balances = {};
        _balanceErrors = ids.toSet();
      }
      _inboxError = AppHelpers.backendErrorMessage(
        error,
        fallback: 'نەتوانرا پوختە و باڵانسی کڕیاران باربکرێت. دووبارە هەوڵ بدە.',
      );
      _safeNotify();
    } finally {
      _inboxRefreshInFlight = false;
      if (_inboxRefreshPending && !_disposed) {
        _inboxRefreshPending = false;
        unawaited(refreshInbox(generation: _generation));
      }
    }
  }

  void markUnreadOptimistic(String customerId, bool unread) {
    final row = _inbox[customerId];
    if (row == null || row['unread'] == unread) return;
    final updated = Map<String, dynamic>.from(row)..['unread'] = unread;
    _inbox = Map<String, Map<String, dynamic>>.from(_inbox)
      ..[customerId] = updated;
    _safeNotify();
  }

  Future<void> markFinancialChatReadBestEffort(
    String customerId,
    DateTime? readThrough,
  ) async {
    if (readThrough == null) return;
    try {
      await gateway.markFinancialChatRead(
        customerId,
        readThrough: readThrough,
      );
    } catch (_) {
      _scheduleInboxRefresh();
    }
  }

  Future<void> _subscribeInboxRealtime() async {
    try {
      await PBService.ensureInitialized();
      if (_disposed || !isCustomerDirectory) return;
      final previous = _inboxRealtimeChannel;
      if (previous != null) {
        try {
          await PBService.client.removeChannel(previous);
        } catch (_) {}
      }

      final channel = PBService.client
          .channel('customer-directory:${DateTime.now().microsecondsSinceEpoch}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'financial_events',
            callback: (_) => _scheduleInboxRefresh(),
          )
          .subscribe();

      if (_disposed) {
        await PBService.client.removeChannel(channel);
        return;
      }
      _inboxRealtimeChannel = channel;
    } catch (_) {
      // Explicit refresh/reconnect remains available; never fake cached success.
    }
  }

  void _scheduleInboxRefresh() {
    if (_disposed || !isCustomerDirectory) return;
    _inboxRealtimeDebounce?.cancel();
    _inboxRealtimeDebounce = Timer(const Duration(milliseconds: 280), () {
      if (_disposed || _users.isEmpty) return;
      unawaited(refreshInbox(generation: _generation));
    });
  }

  double _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('${value ?? ''}') ?? 0;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }
}