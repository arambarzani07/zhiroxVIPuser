import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/models/record_model.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';

void main() {
  group('Zhirox production configuration', () {
    test('uses the expected Supabase project', () {
      expect(SupabaseConfig.url, startsWith('https://'));
      expect(SupabaseConfig.url, contains('zfuvnczdqifihsnrhqzj'));
      expect(SupabaseConfig.publishableKey, isNotEmpty);
      expect(SupabaseConfig.publishableKey, startsWith('sb_publishable_'));
    });

    test('has a non-empty application version', () {
      expect(AppConfig.appVersion, isNotEmpty);
    });
  });

  group('Customer phone identity', () {
    test('normalizes common Iraqi mobile formats deterministically', () {
      const expected = '9647501234567';
      expect(PBService.normalizePhone('0750 123 4567'), expected);
      expect(PBService.normalizePhone('7501234567'), expected);
      expect(PBService.normalizePhone('+964 750 123 4567'), expected);
      expect(PBService.normalizePhone('00964 750 123 4567'), expected);
    });

    test('maps phone to the private Supabase Auth identity', () {
      expect(
        PBService.phoneIdentity('07501234567'),
        '9647501234567@zhirox.app',
      );
    });

    test('rejects malformed mobile identities before authentication', () {
      expect(() => PBService.phoneIdentity('1234'), throwsA(isA<String>()));
      expect(() => PBService.phoneIdentity('0750123'), throwsA(isA<String>()));
    });
  });

  group('Application-owned RecordModel', () {
    test('parses typed values without PocketBase', () {
      final record = RecordModel.fromJson({
        'id': 'customer-1',
        'created': '2026-09-10T08:00:00Z',
        'approved': true,
        'remaining': 125000,
        'count': '4',
      });

      expect(record.id, 'customer-1');
      expect(record.getBoolValue('approved'), isTrue);
      expect(record.getDoubleValue('remaining'), 125000.0);
      expect(record.getIntValue('count'), 4);
    });

    test('preserves expanded records through JSON round-trip', () {
      final record = RecordModel.fromJson({
        'id': 'debt-1',
        'description': 'تاقیکردنەوە',
        'expand': {
          'customer': [
            {'id': 'customer-1', 'name': 'کڕیار'},
          ],
        },
      });

      expect(record.expand['customer'], hasLength(1));
      expect(record.expand['customer']!.first.id, 'customer-1');

      final restored = RecordModel.fromJson(record.toJson());
      expect(restored.expand['customer']!.first.getStringValue('name'), 'کڕیار');
    });

    test('does not synthesize missing security-sensitive values', () {
      final record = RecordModel.fromJson({'id': 'customer-1'});
      expect(record.getStringValue('role'), isEmpty);
      expect(record.getBoolValue('approved'), isFalse);
      expect(record.getDoubleValue('debt_limit'), 0);
    });
  });
}
