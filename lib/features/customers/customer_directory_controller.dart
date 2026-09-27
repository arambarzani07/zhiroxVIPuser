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

  Future<Map<String, dynamic>> getSortedCustomerPage({
    required String search,
    required String filter,
    required String sort,
    required int limit,
    Map<String, dynamic>? cursor,
  }) => getCustomerPage(
    search: search,
    filter: filter,
    limit: limit,
    cursor: cursor,
  );

  Future<Map<String, dynamic>> getAdvancedCustomerPage({
    required String search,
    required Set<String> filters,
    required String sort,
    required int limit,
    required int amount,
    required int days,
    Map<String, dynamic>? cursor,
  }) => getSortedCustomerPage(
    search: search, filter: filters.join(','), sort: sort,
    limit: limit, cursor: cursor,
  );

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
    return _decodeCustomerPage(raw);
  }

  @override
  Future<Map<String, dynamic>> getSortedCustomerPage({
    required String search,
    required String filter,
    required String sort,
    required int limit,
    Map<String, dynamic>? cursor,
  }) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'get_customer_directory_page_sorted',
      params: {
        'p_search': search.trim(),
        'p_filter': filter,
        'p_sort': sort,
        'p_limit': limit.clamp(1, 100),
        'p_offset': int.tryParse('${cursor?['offset'] ?? 0}') ?? 0,
      },
    );
    return _decodeCustomerPage(raw);
  }

  @override
  Future<Map<String, dynamic>> getAdvancedCustomerPage({
    required String search,
    required Set<String> filters,
    required String sort,
    required int limit,
    required int amount,
    required int days,
    Map<String, dynamic>? cursor,
  }) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'get_customer_directory_page_advanced',
      params: {
        'p_search': search.trim(),
        'p_filter': filters.isEmpty ? 'all' : filters.join(','),
        'p_sort': sort,
        'p_limit': limit.clamp(1, 100),
        'p_offset': int.tryParse('${cursor?['offset'] ?? 0}') ?? 0,
        'p_amount': amount,
        'p_days': days,
      },
    );
    return _decodeCustomerPage(raw);
  }

  Map<String, dynamic> _decodeCustomerPage(dynamic raw) {
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
        final user = PBService.profileRecord(row);
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

  static const Map<String, String> sortLabels = {
    'last_activity_desc': 'دوایین مامەڵە سەرەتا',
    'last_activity_asc': 'کۆنترین دوا مامەڵە سەرەتا',
    'newest': 'نوێترین کڕیار',
    'oldest': 'کۆنترین کڕیار',
    'last_debt_newest': 'دوایین قەرز سەرەتا',
    'last_debt_oldest': 'کۆنترین دوا قەرز سەرەتا',
    'last_payment_newest': 'دوایین پارەدانەوە سەرەتا',
    'last_payment_oldest': 'کۆنترین دوا پارەدانەوە سەرەتا',
    'first_activity_newest': 'نوێترین یەکەم مامەڵە',
    'first_activity_oldest': 'کۆنترین یەکەم مامەڵە',
    'profile_updated_newest': 'نوێترین گۆڕانی پرۆفایل',
    'days_since_activity_high': 'زۆرترین ڕۆژ بەبێ مامەڵە',
    'days_since_activity_low': 'کەمترین ڕۆژ بەبێ مامەڵە',
    'days_since_payment_high': 'زۆرترین ڕۆژ بەبێ پارەدانەوە',
    'days_since_payment_low': 'کەمترین ڕۆژ بەبێ پارەدانەوە',
    'name_asc': 'ناو: ئەلف بۆ یێ',
    'name_desc': 'ناو: یێ بۆ ئەلف',
    'balance_high': 'گەورەترین قەرزی ماوە',
    'balance_low': 'بچووکترین قەرزی ماوە',
    'loan_total_high': 'زۆرترین کۆی قەرزی وەرگیراو',
    'loan_total_low': 'کەمترین کۆی قەرزی وەرگیراو',
    'open_count_high': 'زۆرترین قەرزی کراوە',
    'open_count_low': 'کەمترین قەرزی کراوە',
    'last_debt_amount_high': 'بەرزترین بڕی دوا قەرز',
    'last_debt_amount_low': 'نزمترین بڕی دوا قەرز',
    'max_debt_high': 'گەورەترین مامەڵەی قەرز',
    'max_debt_low': 'بچووکترین گەورەترین قەرز',
    'month_loan_high': 'زۆرترین قەرزی ئەم مانگە',
    'avg_debt_high': 'بەرزترین تێکڕای قەرز',
    'avg_debt_low': 'نزمترین تێکڕای قەرز',
    'payment_total_high': 'زۆرترین کۆی پارەدانەوە',
    'payment_total_low': 'کەمترین کۆی پارەدانەوە',
    'last_payment_amount_high': 'بەرزترین دوا پارەدانەوە',
    'last_payment_amount_low': 'نزمترین دوا پارەدانەوە',
    'max_payment_high': 'گەورەترین مامەڵەی پارەدانەوە',
    'max_payment_low': 'بچووکترین گەورەترین پارەدانەوە',
    'month_payment_high': 'زۆرترین پارەدانەوەی ئەم مانگە',
    'avg_payment_high': 'بەرزترین تێکڕای پارەدانەوە',
    'avg_payment_low': 'نزمترین تێکڕای پارەدانەوە',
    'payment_ratio_high': 'زۆرترین ڕێژەی پارەدانەوە',
    'payment_ratio_low': 'کەمترین ڕێژەی پارەدانەوە',
    'transaction_count_high': 'زۆرترین مامەڵە',
    'transaction_count_low': 'کەمترین مامەڵە',
  };
  static const Map<String, String> filterLabels = {
    'all': 'هەموو کڕیاران',
    'with_debt': 'قەرزدار',
    'debt_free': 'بێ قەرز',
    'overdue': 'قەرزی دواکەوتوو',
    'fully_paid': 'قەرزی بە تەواوی دراوە',
    'partially_paid': 'بەشێک لە قەرزی دراوە',
    'paid_with_debt': 'پارەدانەوەی هەیە و قەرزدارە',
    'debt_no_payment': 'قەرزدارە و پارەی نەداوە',
    'multiple_open_debts': 'زیاتر لە یەک قەرزی کراوە',
    'more_than_3_open': 'زیاتر لە ٣ قەرزی کراوە',
    'no_open_debt': 'هیچ قەرزی کراوەی نییە',
    'balance_over_100k': 'قەرزی ماوەی سەروو ١٠٠ هەزار',
    'balance_over_1m': 'قەرزی ماوەی سەروو ١ ملیۆن',
    'balance_over_amount': 'قەرزی ماوەی سەروو بڕی دیاریکراو',
    'balance_under_amount': 'قەرزی ماوەی خوار بڕی دیاریکراو',
    'debt_growth_month': 'قەرزی ئەم مانگە زیاتر لە پارەدانەوەیە',
    'debt_decrease_month': 'پارەدانەوەی ئەم مانگە زیاتر لە قەرزە',
    'has_payment': 'پارەدانەوەی هەیە',
    'no_payment': 'هەرگیز پارەی نەداوەتەوە',
    'today_payment': 'پارەدانەوەی ئەمڕۆ',
    'payment_week': 'پارەدانەوەی ٧ ڕۆژی ڕابردوو',
    'payment_this_month': 'پارەدانەوەی ئەم مانگە',
    'no_payment_this_month': 'بێ پارەدانەوەی ئەم مانگە',
    'no_payment_30': 'بێ پارەدانەوە بۆ ٣٠ ڕۆژ',
    'payment_within_days': 'پارەدانەوە لە ماوەی دیاریکراو',
    'payment_outside_days': 'بێ پارەدانەوە لە ماوەی دیاریکراو',
    'active': 'هەژماری چالاک',
    'inactive': 'هەژماری ناچالاک',
    'no_transactions': 'بێ مامەڵە',
    'today_activity': 'مامەڵەی ئەمڕۆ',
    'today_debt': 'قەرزی نوێی ئەمڕۆ',
    'new_this_month': 'کڕیاری نوێی ئەم مانگە',
    'no_debt_this_month': 'بێ قەرزی نوێی ئەم مانگە',
    'inactive_30': 'بێ مامەڵە بۆ ٣٠ ڕۆژ',
    'inactive_90': 'بێ مامەڵە بۆ ٩٠ ڕۆژ',
    'activity_within_days': 'مامەڵە لە ماوەی دیاریکراو',
    'activity_outside_days': 'بێ مامەڵە لە ماوەی دیاریکراو',
    'both_week': 'قەرز و پارەدانەوە لە ٧ ڕۆژدا',
    'one_transaction': 'تەنها یەک مامەڵە',
    'last_debt': 'دوا مامەڵەی قەرز',
    'last_payment': 'دوا مامەڵەی پارەدانەوە',
    'last_payment_after_debt': 'دوا پارەدانەوە دوای دوا قەرز',
    'last_debt_after_payment': 'دوا قەرز دوای دوا پارەدانەوە',
    'vip': 'کڕیاری VIP',
    'no_phone': 'بێ ژمارە تەلەفۆن',
    'has_phone': 'ژمارە تەلەفۆنی هەیە',
    'missing_names': 'ناوی باوک یان باپیری نییە',
    'incomplete_profile': 'زانیاریی ناتەواو',
    'duplicate_name': 'ناوی دووبارە',
    'duplicate_phone': 'ژمارەی دووبارە',
    'has_note': 'تێبینیی هەیە',
    'loan_only': 'تەنها قەرزی هەیە',
    'payment_only': 'تەنها پارەدانەوەی هەیە',
    'currency_iqd': 'مامەڵەی دینار',
    'currency_usd': 'مامەڵەی دۆلار',
    'both_currencies': 'هەردوو دراوەکە',
  };
  static const Map<String, List<String>> filterGroups = {
    'هەموو': ['all'],
    'قەرز': ['with_debt', 'debt_free', 'overdue', 'fully_paid', 'partially_paid', 'paid_with_debt', 'debt_no_payment', 'multiple_open_debts', 'more_than_3_open', 'no_open_debt', 'balance_over_100k', 'balance_over_1m', 'balance_over_amount', 'balance_under_amount', 'debt_growth_month', 'debt_decrease_month'],
    'پارەدانەوە': ['has_payment', 'no_payment', 'today_payment', 'payment_week', 'payment_this_month', 'no_payment_this_month', 'no_payment_30', 'payment_within_days', 'payment_outside_days'],
    'چالاکی و کات': ['active', 'inactive', 'no_transactions', 'today_activity', 'today_debt', 'new_this_month', 'no_debt_this_month', 'inactive_30', 'inactive_90', 'activity_within_days', 'activity_outside_days', 'both_week', 'one_transaction', 'last_debt', 'last_payment', 'last_payment_after_debt', 'last_debt_after_payment'],
    'زانیاری': ['vip', 'no_phone', 'has_phone', 'missing_names', 'incomplete_profile', 'duplicate_name', 'duplicate_phone', 'has_note'],
    'جۆری مامەڵە': ['loan_only', 'payment_only', 'currency_iqd', 'currency_usd', 'both_currencies'],
  };
  static const Map<String, List<String>> sortGroups = {
    'کات': ['last_activity_desc', 'last_activity_asc', 'newest', 'oldest', 'last_debt_newest', 'last_debt_oldest', 'last_payment_newest', 'last_payment_oldest', 'first_activity_newest', 'first_activity_oldest', 'profile_updated_newest', 'days_since_activity_high', 'days_since_activity_low', 'days_since_payment_high', 'days_since_payment_low'],
    'ناو': ['name_asc', 'name_desc'],
    'قەرز': ['balance_high', 'balance_low', 'loan_total_high', 'loan_total_low', 'open_count_high', 'open_count_low', 'last_debt_amount_high', 'last_debt_amount_low', 'max_debt_high', 'max_debt_low', 'month_loan_high', 'avg_debt_high', 'avg_debt_low'],
    'پارەدانەوە': ['payment_total_high', 'payment_total_low', 'last_payment_amount_high', 'last_payment_amount_low', 'max_payment_high', 'max_payment_low', 'month_payment_high', 'avg_payment_high', 'avg_payment_low', 'payment_ratio_high', 'payment_ratio_low'],
    'ژمارە': ['transaction_count_high', 'transaction_count_low'],
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
  Set<String> _filters = {};
  String _sort = 'last_activity_desc';
  int _amount = 100000;
  int _days = 30;
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
  Set<String> get filters => Set.unmodifiable(_filters);
  int get amount => _amount;
  int get days => _days;
  String get sort => _sort;
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

  Future<void> selectFilters(Set<String> values, {int? amount, int? days}) async {
    final selected = values.where((v) => v != 'all' && filterLabels.containsKey(v)).toSet();
    final nextAmount = (amount ?? _amount).clamp(1, 1000000000000);
    final nextDays = (days ?? _days).clamp(1, 3650);
    if (setEquals(selected, _filters) && nextAmount == _amount && nextDays == _days) return;
    _filters = selected;
    _amount = nextAmount;
    _days = nextDays;
    _safeNotify();
    await load(search: _search);
  }

  Future<void> selectSort(String value) async {
    if (!sortLabels.containsKey(value) || value == _sort) return;
    _sort = value;
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
        final page = await gateway.getAdvancedCustomerPage(
          search: requestedSearch,
          filters: _filters,
          sort: _sort,
          limit: 60,
          amount: _amount,
          days: _days,
          cursor: loadMore ? _nextCursor : null,
        );
        users = List<RecordModel>.from(page['items'] as List);
        pageInbox = Map<String, Map<String, dynamic>>.from(
          page['inbox'] as Map,
        );
        totalUsers = page['totalItems'] as int;
        hasMore = page['hasMore'] == true;
        nextCursor = page['nextCursor'] as Map<String, dynamic>?;

        if (!loadMore && _filters.isEmpty && _sort == 'newest') {
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