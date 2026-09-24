import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zhirox/services/customer_push_service.dart';
import 'package:zhirox/widgets/customer_push_card.dart';

class FakeCustomerPushGateway implements CustomerPushGateway {
  FakeCustomerPushGateway({
    required this.statuses,
    this.link,
    this.statusError,
    this.revokedCount = 0,
    this.sendResult = const CustomerPushSendResult(
      campaignId: '00000000-0000-0000-0000-000000000999',
      queuedCustomers: 1,
      targetDevices: 1,
      marketName: 'کانی چنار',
    ),
    this.history = const [],
    this.retryResult = const CustomerPushRetryResult(
      outboxId: '00000000-0000-0000-0000-000000000888',
      retryDevices: 1,
      alreadySent: false,
    ),
  });

  final List<CustomerPushStatus> statuses;
  final CustomerPushLink? link;
  final Object? statusError;
  final int revokedCount;
  final CustomerPushSendResult sendResult;
  final List<CustomerPushHistoryItem> history;
  final CustomerPushRetryResult retryResult;

  int loadCalls = 0;
  int createCalls = 0;
  int revokeCalls = 0;
  int sendCalls = 0;
  int historyCalls = 0;
  int retryCalls = 0;
  String? lastMessage;
  String? lastRetryOutboxId;
  bool failFirstLoad = false;

  @override
  Future<CustomerPushOverviewPage> loadOverview({
    String search = '',
    String filter = 'all',
    int limit = 60,
    int offset = 0,
  }) async {
    return const CustomerPushOverviewPage(
      items: [],
      totalCount: 0,
      offset: 0,
      limit: 60,
      hasMore: false,
      filter: 'all',
      summary: CustomerPushOverviewSummary(
        all: 0,
        active: 0,
        inactive: 0,
        failed: 0,
        pending: 0,
      ),
    );
  }

  @override
  Future<CustomerPushStatus> loadStatus(String customerId) async {
    loadCalls++;
    if (failFirstLoad && loadCalls == 1) {
      throw statusError ?? StateError('offline');
    }
    if (statuses.isEmpty) {
      throw StateError('No fake status configured');
    }
    final index =
        (loadCalls - (failFirstLoad ? 2 : 1)).clamp(0, statuses.length - 1);
    return statuses[index];
  }

  @override
  Future<CustomerPushLink> createLink(String customerId) async {
    createCalls++;
    final value = link;
    if (value == null) throw StateError('No link configured');
    return value;
  }

  @override
  Future<List<CustomerPushHistoryItem>> loadHistory(
    String customerId, {
    int limit = 20,
  }) async {
    historyCalls++;
    return history.take(limit).toList(growable: false);
  }

  @override
  Future<CustomerPushRetryResult> retryNotification(
    String customerId,
    String outboxId,
  ) async {
    retryCalls++;
    lastRetryOutboxId = outboxId;
    return CustomerPushRetryResult(
      outboxId: outboxId,
      retryDevices: retryResult.retryDevices,
      alreadySent: retryResult.alreadySent,
    );
  }

  @override
  Future<int> revokeAll(String customerId) async {
    revokeCalls++;
    return revokedCount;
  }

  @override
  Future<CustomerPushSendResult> sendManual(
    String customerId,
    String message,
  ) async {
    sendCalls++;
    lastMessage = message;
    return sendResult;
  }

  @override
  Future<CustomerPushSettings> loadSettings() async =>
      const CustomerPushSettings(overdueIntervalDays: 3);

  @override
  Future<CustomerPushSettings> updateSettings({
    required int overdueIntervalDays,
  }) async =>
      CustomerPushSettings(overdueIntervalDays: overdueIntervalDays);

  @override
  Future<CustomerPushSendResult> broadcastManual(String message) async {
    throw UnimplementedError();
  }
}

Widget _host(CustomerPushGateway gateway) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: CustomerPushCard(
          customerId: 'customer-1',
          gateway: gateway,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('QR button renders permanent onboarding URL', (tester) async {
    final token = 'a' * 64;
    final onboardingUrl = Uri.parse('https://push.zhirox.com/?token=$token');
    final gateway = FakeCustomerPushGateway(
      statuses: const [
        CustomerPushStatus(
          active: false,
          deviceCount: 0,
          activeLinkCount: 1,
        ),
      ],
      link: CustomerPushLink.fromJson({
        'url': onboardingUrl.toString(),
        'expires_at': null,
      }),
    );

    await tester.pumpWidget(_host(gateway));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QR ـی ئاگادارکردنەوە'));
    await tester.pumpAndSettle();

    expect(gateway.createCalls, 1);
    final qrFinder = find.byKey(ValueKey<String>(onboardingUrl.toString()));
    expect(qrFinder, findsOneWidget);
    expect(tester.widget(qrFinder), isA<QrImageView>());
    expect(
      find.text('ئەم لینکە بەردەوام کار دەکات تا بەڕێوەبەر ڕایدەگرێت.'),
      findsOneWidget,
    );
  });

  testWidgets('active link without devices still shows revoke control', (tester) async {
    final gateway = FakeCustomerPushGateway(
      statuses: const [
        CustomerPushStatus(
          active: false,
          deviceCount: 0,
          activeLinkCount: 2,
        ),
      ],
    );

    await tester.pumpWidget(_host(gateway));
    await tester.pumpAndSettle();

    expect(find.text('هەموو لینک و ئامێرەکان ڕابگرە'), findsOneWidget);
    expect(find.text('ناردنی ئاگاداری'), findsNothing);
  });

  testWidgets('active state shows linked device count and manual send control', (tester) async {
    final gateway = FakeCustomerPushGateway(
      statuses: const [
        CustomerPushStatus(
          active: true,
          deviceCount: 3,
          activeLinkCount: 1,
          latestStatus: 'sent',
        ),
      ],
    );

    await tester.pumpWidget(_host(gateway));
    await tester.pumpAndSettle();

    expect(find.text('ئامێری چالاک: 3'), findsOneWidget);
    expect(find.text('ناردنی ئاگاداری'), findsOneWidget);
    expect(find.text('هەموو لینک و ئامێرەکان ڕابگرە'), findsOneWidget);
  });

  testWidgets('manager can send manual notification to linked customer', (tester) async {
    final gateway = FakeCustomerPushGateway(
      statuses: const [
        CustomerPushStatus(
          active: true,
          deviceCount: 2,
          activeLinkCount: 1,
        ),
      ],
      sendResult: const CustomerPushSendResult(
        campaignId: '00000000-0000-0000-0000-000000000999',
        queuedCustomers: 1,
        targetDevices: 2,
        marketName: 'کانی چنار',
      ),
    );

    await tester.pumpWidget(_host(gateway));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ناردنی ئاگاداری'));
    await tester.pumpAndSettle();

    expect(find.text('ئاگاداری بۆ ئەم کڕیارە'), findsOneWidget);
    expect(
      find.text('ناوی ئاگادارکردنەوە خۆکارانە ناوی سوپەرمارکێتەکەیە.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('customer-manual-push-message')),
      'کاڵای نوێ گەیشت.',
    );
    await tester.tap(find.text('ناردن'));
    await tester.pumpAndSettle();

    expect(gateway.sendCalls, 1);
    expect(gateway.lastMessage, 'کاڵای نوێ گەیشت.');
    expect(
      find.text('ئاگاداری بە ناوی کانی چنار بۆ 2 ئامێر ڕیزکرا'),
      findsOneWidget,
    );
  });

  testWidgets('revoke confirms links and devices then refreshes status', (tester) async {
    final gateway = FakeCustomerPushGateway(
      statuses: const [
        CustomerPushStatus(active: true, deviceCount: 2, activeLinkCount: 2),
        CustomerPushStatus(active: false, deviceCount: 0, activeLinkCount: 0),
      ],
      revokedCount: 2,
    );

    await tester.pumpWidget(_host(gateway));
    await tester.pumpAndSettle();
    expect(find.text('ئامێری چالاک: 2'), findsOneWidget);

    await tester.tap(find.text('هەموو لینک و ئامێرەکان ڕابگرە'));
    await tester.pumpAndSettle();
    expect(
      find.text('دڵنیایت لە ڕاگرتنی هەموو QR لینک و ئامێرە چالاکەکان؟'),
      findsOneWidget,
    );

    await tester.tap(find.text('بەڵێ، ڕایانبگرە'));
    await tester.pumpAndSettle();

    expect(gateway.revokeCalls, 1);
    expect(gateway.loadCalls, 2);
    expect(find.text('هێشتا هیچ ئامێرێک پەیوەست نییە'), findsOneWidget);
  });

  testWidgets('gateway error shows retry and retry reloads status', (tester) async {
    final gateway = FakeCustomerPushGateway(
      statuses: const [
        CustomerPushStatus(active: false, deviceCount: 0, activeLinkCount: 0),
      ],
      statusError: StateError('network unavailable'),
    )..failFirstLoad = true;

    await tester.pumpWidget(_host(gateway));
    await tester.pumpAndSettle();

    expect(
      find.text('نەتوانرا دۆخی ئاگادارکردنەوە بخوێندرێتەوە'),
      findsOneWidget,
    );
    expect(find.text('دووبارە هەوڵبدەوە'), findsOneWidget);

    await tester.tap(find.text('دووبارە هەوڵبدەوە'));
    await tester.pumpAndSettle();

    expect(gateway.loadCalls, 2);
    expect(find.text('هێشتا هیچ ئامێرێک پەیوەست نییە'), findsOneWidget);
  });
  testWidgets('history renders delivery state and manager can retry failed push',
      (tester) async {
    final failedId = '00000000-0000-0000-0000-000000000777';
    final gateway = FakeCustomerPushGateway(
      statuses: const [
        CustomerPushStatus(
          active: true,
          deviceCount: 1,
          activeLinkCount: 1,
        ),
      ],
      history: [
        CustomerPushHistoryItem(
          id: failedId,
          eventType: 'payment_created',
          status: 'failed',
          createdAt: DateTime.utc(2026, 9, 18, 8, 30),
          sentCount: 0,
          failedCount: 1,
          expiredCount: 0,
          pendingCount: 0,
          deviceCount: 1,
          attemptCount: 3,
          amount: 2500,
          currency: 'IQD',
        ),
      ],
    );

    await tester.pumpWidget(_host(gateway));
    await tester.pumpAndSettle();

    expect(find.text('مێژووی ئاگادارکردنەوەکان'), findsOneWidget);
    expect(find.text('پارەدانەوە'), findsOneWidget);
    expect(find.text('دووبارە ناردنەوە'), findsOneWidget);

    await tester.tap(find.text('دووبارە ناردنەوە'));
    await tester.pumpAndSettle();

    expect(gateway.retryCalls, 1);
    expect(gateway.lastRetryOutboxId, failedId);
    expect(find.text('دووبارە ناردنەوە بۆ 1 ئامێر ڕیزکرا'), findsOneWidget);
  });

}
