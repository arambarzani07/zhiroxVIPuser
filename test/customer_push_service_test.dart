import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/services/customer_push_service.dart';

void main() {
  test('push status parses server response', () {
    final status = CustomerPushStatus.fromJson({
      'active': true,
      'device_count': 2,
      'latest_status': 'sent',
      'latest_at': '2026-09-17T00:00:00Z',
    });

    expect(status.active, isTrue);
    expect(status.deviceCount, 2);
    expect(status.latestStatus, 'sent');
    expect(status.latestAt, DateTime.parse('2026-09-17T00:00:00Z'));
  });

  test('push status rejects malformed success payloads', () {
    expect(
      () => CustomerPushStatus.fromJson({
        'active': 'yes',
        'device_count': 2,
        'latest_status': null,
        'latest_at': null,
      }),
      throwsFormatException,
    );
    expect(
      () => CustomerPushStatus.fromJson({
        'active': false,
        'device_count': -1,
        'latest_status': null,
        'latest_at': null,
      }),
      throwsFormatException,
    );
  });

  test('push link parses an absolute onboarding URL and expiry', () {
    final link = CustomerPushLink.fromJson({
      'url': 'https://example.test/functions/v1/customer-push?token=${'a' * 64}',
      'expires_at': '2026-09-17T00:15:00Z',
    });

    expect(link.url.isAbsolute, isTrue);
    expect(link.url.queryParameters['token'], 'a' * 64);
    expect(link.expiresAt, DateTime.parse('2026-09-17T00:15:00Z'));
  });

  test('service sends exact admin actions and parses replies', () async {
    final calls = <Map<String, dynamic>>[];
    final service = CustomerPushService(
      invoker: (body) async {
        calls.add(Map<String, dynamic>.from(body));
        switch (body['action']) {
          case 'status':
            return {
              'active': true,
              'device_count': 3,
              'latest_status': 'sent',
              'latest_at': '2026-09-17T00:00:00Z',
            };
          case 'create_link':
            return {
              'url': 'https://example.test/functions/v1/customer-push?token=${'b' * 64}',
              'expires_at': '2026-09-17T00:15:00Z',
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
    expect(link.url.queryParameters['token'], 'b' * 64);
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
