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
  });

  final List<CustomerPushStatus> statuses;
  final CustomerPushLink? link;
  final Object? statusError;
  final int revokedCount;

  int loadCalls = 0;
  int createCalls = 0;
  int revokeCalls = 0;
  bool failFirstLoad = false;

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
  Future<int> revokeAll(String customerId) async {
    revokeCalls++;
    return revokedCount;
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
  });

  testWidgets('active state shows linked device count', (tester) async {
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
    expect(find.text('هەموو لینک و ئامێرەکان ڕابگرە'), findsOneWidget);
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
}
