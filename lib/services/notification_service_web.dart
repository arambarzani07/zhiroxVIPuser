class NotificationService {
  static Future<void> init() async {}

  static Future<bool> requestPermission() async => true;

  static Future<bool> isPermissionGranted() async => true;

  static Future<void> show({
    required String title,
    required String body,
    int id = 0,
  }) async {}

  static Future<void> showDebtCreated({
    required String customerName,
    required String amount,
    required String employeeName,
  }) async {}

  static Future<void> showDueReminder({
    required String customerName,
    required String amount,
    required String dueDate,
  }) async {}
}
