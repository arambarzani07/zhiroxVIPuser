import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
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

  group('Currency-safe debt summaries', () {
    RecordModel debt({
      required String id,
      required double amount,
      required double remaining,
      required String currency,
      double rate = 0,
    }) {
      return RecordModel.fromJson({
        'id': id,
        'collectionId': '',
        'collectionName': 'debts',
        'amount': amount,
        'remaining': remaining,
        'currency': currency,
        'dollar_rate': rate,
      });
    }

    test('normalizes mixed IQD and USD using the historical debt rate', () {
      final summary = AppHelpers.debtSummaryInIqd([
        debt(id: 'iqd', amount: 100000, remaining: 60000, currency: 'IQD'),
        debt(id: 'usd', amount: 50, remaining: 20, currency: 'USD', rate: 1500),
      ]);
      expect(summary.complete, isTrue);
      expect(summary.totalDebt, 175000);
      expect(summary.totalRemaining, 90000);
      expect(summary.totalPaid, 85000);
    });

    test('fails closed when a USD debt has no valid historical rate', () {
      final summary = AppHelpers.debtSummaryInIqd([
        debt(id: 'usd-no-rate', amount: 50, remaining: 20, currency: 'USD'),
      ]);
      expect(summary.complete, isFalse);
    });
  });

}
