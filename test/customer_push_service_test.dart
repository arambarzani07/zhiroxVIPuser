import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/services/customer_push_service.dart';

void main() {
  test('push status parses active link count', () {
    final status = CustomerPushStatus.fromJson({
      'active': true,
      'device_count': 2,
      'active_link_count': 3,
      'latest_status': 'sent',
      'latest_at': '2026-09-17T00:00:00Z',
    });

    expect(status.active, isTrue);
    expect(status.deviceCount, 2);
    expect(status.activeLinkCount, 3);
    expect(status.hasActiveLink, isTrue);
    expect(status.latestStatus, 'sent');
    expect(status.latestAt, DateTime.parse('2026-09-17T00:00:00Z'));
  });

  test('push status rejects malformed success payloads', () {
    expect(
      () => CustomerPushStatus.fromJson({
        'active': 'yes',
        'device_count': 2,
        'active_link_count': 1,
        'latest_status': null,
        'latest_at': null,
      }),
      throwsFormatException,
    );
    expect(
      () => CustomerPushStatus.fromJson({
        'active': false,
        'device_count': 0,
        'active_link_count': -1,
        'latest_status': null,
        'latest_at': null,
      }),
      throwsFormatException,
    );
  });

  test('push link accepts a permanent onboarding URL with null expiry', () {
    final link = CustomerPushLink.fromJson({
      'url': 'https://push.zhirox.com/?token=${'a' * 64}',
      'expires_at': null,
    });

    expect(link.url.isAbsolute, isTrue);
    expect(link.url.queryParameters['token'], 'a' * 64);
    expect(link.expiresAt, isNull);
  });

  test('service sends exact admin actions and parses permanent replies', () async {
    final calls = <Map<String, dynamic>>[];
    final service = CustomerPushService(
      invoker: (body) async {
        calls.add(Map<String, dynamic>.from(body));
        switch (body['action']) {
          case 'status':
            return {
              'active': true,
              'device_count': 3,
              'active_link_count': 2,
              'latest_status': 'sent',
              'latest_at': '2026-09-17T00:00:00Z',
            };
          case 'create_link':
            return {
              'url': 'https://push.zhirox.com/?token=${'b' * 64}',
              'expires_at': null,
            };
          case 'revoke_all':
            return {'revoked_count': 3};
        }
        throw StateError('unexpected action');
      },
    );

    final status = await service.loadStatus('customer-1');
    final link = await service.createLink('customer-1');
    final revoked = await service.revokeAll('customer-1');

    expect(status.deviceCount, 3);
    expect(status.activeLinkCount, 2);
    expect(link.url.queryParameters['token'], 'b' * 64);
    expect(link.expiresAt, isNull);
    expect(revoked, 3);
    expect(calls, [
      {'action': 'status', 'customer_id': 'customer-1'},
      {'action': 'create_link', 'customer_id': 'customer-1'},
      {'action': 'revoke_all', 'customer_id': 'customer-1'},
    ]);
  });

  test('service rejects malformed admin success payloads', () async {
    final service = CustomerPushService(
      invoker: (_) async => {'revoked_count': 'three'},
    );

    await expectLater(service.revokeAll('customer-1'), throwsFormatException);
  });
}
