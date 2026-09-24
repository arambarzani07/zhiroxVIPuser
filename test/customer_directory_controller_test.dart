import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/features/customers/customer_directory_controller.dart';

RecordModel record(String id, String name) => RecordModel.fromJson({
      'id': id,
      'collectionId': '',
      'collectionName': 'users',
      'name': name,
      'phone': '07500000000',
      'role': 'customer',
      'approved': true,
      'active': true,
      'created': '2026-09-24T00:00:00Z',
      'updated': '2026-09-24T00:00:00Z',
    });

class FakeDirectoryGateway implements CustomerDirectoryGateway {
  String lastFilter = 'all';
  String lastSearch = '';
  int customerPageCalls = 0;
  int inboxCalls = 0;
  final List<String> markedRead = [];

  @override
  Future<Map<String, dynamic>> getCustomerPage({
    required String search,
    required String filter,
    required int limit,
    Map<String, dynamic>? cursor,
  }) async {
    customerPageCalls++;
    lastFilter = filter;
    lastSearch = search;

    if (filter == 'with_debt') {
      return {
        'items': [record('debt-only', 'قەرزدار')],
        'inbox': <String, Map<String, dynamic>>{
          'debt-only': {
            'customer_id': 'debt-only',
            'remaining': 9000,
            'open_debt_count': 1,
            'unread': false,
          },
        },
        'totalItems': 1,
        'hasMore': false,
        'nextCursor': null,
      };
    }

    if (cursor != null) {
      return {
        'items': [record('c', 'سێ')],
        'inbox': <String, Map<String, dynamic>>{
          'c': {
            'customer_id': 'c',
            'remaining': 3000,
            'open_debt_count': 1,
            'unread': false,
          },
        },
        'totalItems': 4,
        'hasMore': false,
        'nextCursor': null,
      };
    }

    return {
      'items': [record('a', 'یەک'), record('b', 'دوو')],
      'inbox': <String, Map<String, dynamic>>{
        'a': {
          'customer_id': 'a',
          'remaining': 1000,
          'open_debt_count': 1,
          'unread': true,
        },
        'b': {
          'customer_id': 'b',
          'remaining': 0,
          'open_debt_count': 0,
          'unread': false,
        },
      },
      'totalItems': 4,
      'hasMore': true,
      'nextCursor': <String, dynamic>{
        'created_at': '2026-09-23T00:00:00Z',
        'id': 'b',
      },
    };
  }

  @override
  Future<List<RecordModel>> getPinnedCustomers({required String search}) async {
    return [record('p', 'پین'), record('b', 'دوو')];
  }

  @override
  Future<Map<String, Map<String, dynamic>>> getInboxRows(
    List<String> customerIds,
  ) async {
    inboxCalls++;
    return {
      for (final id in customerIds)
        id: {
          'customer_id': id,
          'remaining': id == 'p' ? 7000 : (id == 'a' ? 1000 : 0),
          'open_debt_count': id == 'p' || id == 'a' ? 1 : 0,
          'last_activity_at': '2026-09-24T10:00:00Z',
          'last_kind': 'debt',
          'last_amount': 1000,
          'last_preview': 'مامەڵە',
          'last_event_type': 'debt_created',
          'unread': id == 'a',
        },
    };
  }

  @override
  Future<List<RecordModel>> getUsers({
    required String role,
    required String search,
    required String adminId,
  }) async {
    return [record('employee', 'کارمەند')];
  }

  @override
  Future<void> markFinancialChatRead(
    String customerId, {
    required DateTime readThrough,
  }) async {
    markedRead.add(customerId);
  }
}

void main() {
  test('customer controller merges pinned rows and paginates without duplicates',
      () async {
    final gateway = FakeDirectoryGateway();
    final controller = CustomerDirectoryController(
      role: 'customer',
      adminId: 'admin',
      gateway: gateway,
      observeConnectivity: false,
      subscribeRealtime: false,
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(controller.users.map((e) => e.id).toList(), ['p', 'b', 'a']);
    expect(controller.totalUsers, 4);
    expect(controller.hasMore, isTrue);
    expect(controller.balances['p'], 7000);
    expect(controller.inbox['a']?['unread'], isTrue);

    await controller.loadMore();

    expect(controller.users.map((e) => e.id).toList(), ['p', 'b', 'a', 'c']);
    expect(controller.hasMore, isFalse);
  });

  test('filter and search are owned by controller state', () async {
    final gateway = FakeDirectoryGateway();
    final controller = CustomerDirectoryController(
      role: 'customer',
      adminId: 'admin',
      gateway: gateway,
      observeConnectivity: false,
      subscribeRealtime: false,
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.selectFilter('with_debt');

    expect(controller.filter, 'with_debt');
    expect(gateway.lastFilter, 'with_debt');
    expect(controller.users.single.id, 'debt-only');

    controller.scheduleSearch('  ئارام  ');
    await Future<void>.delayed(const Duration(milliseconds: 360));

    expect(controller.search, 'ئارام');
    expect(gateway.lastSearch, 'ئارام');
  });

  test('unread state is optimistic and read acknowledgement uses gateway',
      () async {
    final gateway = FakeDirectoryGateway();
    final controller = CustomerDirectoryController(
      role: 'customer',
      adminId: 'admin',
      gateway: gateway,
      observeConnectivity: false,
      subscribeRealtime: false,
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(controller.inbox['a']?['unread'], isTrue);
    controller.markUnreadOptimistic('a', false);
    expect(controller.inbox['a']?['unread'], isFalse);

    await controller.markFinancialChatReadBestEffort(
      'a',
      DateTime.utc(2026, 9, 24, 10),
    );
    expect(gateway.markedRead, ['a']);
  });
}
