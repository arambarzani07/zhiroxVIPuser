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
      if (!loadMore) _users = const [];
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
      _inbox = {};
      _balances = {};
      _balanceErrors = ids.toSet();
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
      // Explicit refresh/reconnect remains available. Never fake cached success.
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
