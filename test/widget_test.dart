import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/utils/constants.dart';

void main() {
  group('Zhirox configuration', () {
    test('uses the expected Supabase project', () {
      expect(SupabaseConfig.url, startsWith('https://'));
      expect(SupabaseConfig.url, contains('zfuvnczdqifihsnrhqzj'));
      expect(SupabaseConfig.publishableKey, isNotEmpty);
    });

    test('has a non-empty application version', () {
      expect(AppConfig.appVersion, isNotEmpty);
    });
  });
}
