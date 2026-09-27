import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/features/customers/customer_directory_controller.dart';
import 'package:zhirox/features/customers/customer_directory_snapshot.dart';

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

  @override
  Future<Map<String, dynamic>> getAdvancedCustomerPage({
    required String search,
    required Set<String> filters,
    required String sort,
    required int limit,
    required int amount,
    required int days,
    Map<String, dynamic>? cursor,
  }) => getCustomerPage(
    search: search,
    filter: filters.isEmpty ? 'all' : filters.join(','),
    limit: limit, cursor: cursor,
  );

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

class FakeSnapshotStore implements CustomerDirectorySnapshotStore {
  FakeSnapshotStore(this.preview);
  final CustomerDirectorySnapshot preview;
  CustomerDirectorySnapshot? saved;
  @override
  Future<CustomerDirectorySnapshot?> read(String userId, String tenantId) async =>
      userId == 'viewer' && tenantId == 'admin' ? preview : null;
  @override
  Future<void> write(String userId, String tenantId,
      CustomerDirectorySnapshot snapshot) async { saved = snapshot; }
  @override
  Future<void> clear(String userId, String tenantId) async { saved = null; }
}

class DelayedDirectoryGateway extends FakeDirectoryGateway {
  final completer = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> getCustomerPage({
    required String search, required String filter, required int limit,
    Map<String, dynamic>? cursor,
  }) => completer.future;
}

void main() {
  test('protected preview is shown before a live directory response', () async {
    final oldTime = DateTime.now().subtract(const Duration(minutes: 2));
    final store = FakeSnapshotStore(CustomerDirectorySnapshot(
      users: [record('saved', 'پێشوو')],
      inbox: {'saved': {'remaining': 42}},
      totalItems: 1, hasMore: false, nextCursor: null,
      updatedAt: oldTime,
    ));
    final gateway = DelayedDirectoryGateway();
    final controller = CustomerDirectoryController(
      role: 'customer', adminId: 'admin', snapshotUserId: 'viewer',
      gateway: gateway, snapshotStore: store,
      observeConnectivity: false, subscribeRealtime: false,
    );
    addTearDown(controller.dispose);
    final pending = controller.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(controller.users.single.id, 'saved');
    expect(controller.showingSnapshot, isTrue);
    expect(controller.lastUpdatedAt, oldTime);
    expect(controller.isLoading, isTrue);

    gateway.completer.complete({
      'items': [record('live', 'نوێ')],
      'inbox': <String, Map<String, dynamic>>{'live': {'remaining': 55}},
      'totalItems': 1, 'hasMore': false, 'nextCursor': null,
    });
    await pending;
    expect(controller.users.single.id, 'live');
    expect(controller.showingSnapshot, isFalse);
    expect(controller.isLoading, isFalse);
    expect(controller.lastUpdatedAt!.isAfter(oldTime), isTrue);
    expect(store.saved?.users.single.id, 'live');
  });

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
    await controller.selectFilters({'with_debt'});

    expect(controller.filters, {'with_debt'});
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
