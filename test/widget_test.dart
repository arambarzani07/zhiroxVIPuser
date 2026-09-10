import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/utils/helpers.dart';

void main() {
  group('AppHelpers finance formatting', () {
    test('formats IQD amounts with separators', () {
      expect(AppHelpers.formatCurrency(12500), '12,500 د.ع');
    });

    test('maps debt and user states to Kurdish labels', () {
      expect(AppHelpers.statusName('pending'), 'چاوەڕوانە');
      expect(AppHelpers.statusName('partial'), 'بەشێکی دراوە');
      expect(AppHelpers.statusName('paid'), 'دراوە');
      expect(AppHelpers.roleName('admin'), 'بەڕێوبەر');
      expect(AppHelpers.roleName('employee'), 'کارمەند');
      expect(AppHelpers.roleName('customer'), 'کڕیار');
    });
  });

  group('AppHelpers backend error normalization', () {
    test('normalizes network failures without leaking raw exceptions', () {
      final message = AppHelpers.backendErrorMessage(
        Exception('SocketException: Failed host lookup'),
      );
      expect(
        message,
        'پەیوەندی بە سێرڤەر نەکرا. ئینتەرنێت بپشکنە و دووبارە هەوڵ بدە.',
      );
      expect(message, isNot(contains('SocketException')));
    });

    test('normalizes auth and permission failures', () {
      expect(
        AppHelpers.backendErrorMessage(Exception('401 unauthorized')),
        'دانیشتنەکەت بەسەرچووە. تکایە دووبارە بچۆ ژوورەوە.',
      );
      expect(
        AppHelpers.backendErrorMessage(Exception('403 row-level security')),
        'دەسەڵاتی ئەنجامدانی ئەم کردارەت نییە.',
      );
    });

    test('normalizes duplicate data and keeps unknown failures generic', () {
      expect(
        AppHelpers.backendErrorMessage(Exception('duplicate key value')),
        'ئەم زانیارییە پێشتر تۆمار کراوە.',
      );
      expect(
        AppHelpers.backendErrorMessage(Exception('internal database detail')),
        'کردارەکە سەرکەوتوو نەبوو. دووبارە هەوڵ بدە.',
      );
    });
  });
}
