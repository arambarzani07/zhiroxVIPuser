import 'package:pocketbase/pocketbase.dart';

import 'data_quality_issue.dart';

class DataQualityChecker {
  const DataQualityChecker();

  List<DataQualityIssue> analyze({
    required List<RecordModel> users,
    required List<RecordModel> debts,
    required List<RecordModel> payments,
    required List<RecordModel> notifications,
  }) {
    final issues = <DataQualityIssue>[];

    issues.addAll(_checkUsers(users));
    issues.addAll(_checkDebts(debts, users));
    issues.addAll(_checkPayments(payments, debts));
    issues.addAll(_checkNotifications(notifications, users));

    return issues;
  }

  List<DataQualityIssue> _checkUsers(List<RecordModel> users) {
    final issues = <DataQualityIssue>[];

    for (final user in users) {
      final role = user.getStringValue('role');
      final phone = user.getStringValue('phone');
      final adminId = user.getStringValue('admin_id');

      if (phone.trim().isEmpty) {
        issues.add(
          DataQualityIssue(
            id: 'user_missing_phone_${user.id}',
            type: DataQualityIssueType.missingPhone,
            severity: DataQualitySeverity.warning,
            collection: 'users',
            recordId: user.id,
            title: 'ژمارەی مۆبایل تەواو نییە',
            message: 'ئەم کڕیار/بەکارهێنەرە ژمارەی مۆبایلی تۆمارنەکراوە.',
            suggestion:
                'ژمارەی مۆبایل زیاد بکە بۆ ئەوەی گەڕان، ناسینەوە و ئاگادارکردنەوەکان ڕێک بێت.',
            customerId: user.id,
          ),
        );
      }

      if (role != 'admin' && role != 'owner' && adminId.trim().isEmpty) {
        issues.add(
          DataQualityIssue(
            id: 'user_missing_admin_${user.id}',
            type: DataQualityIssueType.missingAdminId,
            severity: DataQualitySeverity.critical,
            collection: 'users',
            recordId: user.id,
            title: 'کڕیارێک بە مارکێتەکەوە نەبەستراوەتەوە',
            message:
                'ئەم کڕیار/بەکارهێنەرە لە داتای کۆنە و پەیوەندی مارکێتی بۆ دیاری نەکراوە.',
            suggestion:
                'لە پلانی ڕێکخستنەوەدا ئەم داتایە بە سەلامەتی بە مارکێتەکەوە دەبەسترێتەوە؛ هیچ زانیارییەک ناسڕدرێتەوە.',
            customerId: user.id,
            canAutoFix: true,
          ),
        );
      }
    }

    return issues;
  }

  List<DataQualityIssue> _checkDebts(
    List<RecordModel> debts,
    List<RecordModel> users,
  ) {
    final issues = <DataQualityIssue>[];
    final userIds = users.map((e) => e.id).toSet();

    for (final debt in debts) {
      final customerId = debt.getStringValue('customer');
      final createdBy = debt.getStringValue('created_by');
      final adminId = debt.getStringValue('admin_id');
      final status = debt.getStringValue('status');
      final amount = debt.getDoubleValue('amount');
      final remaining = debt.getDoubleValue('remaining');

      if (adminId.trim().isEmpty) {
        issues.add(
          DataQualityIssue(
            id: 'debt_missing_admin_${debt.id}',
            type: DataQualityIssueType.missingAdminId,
            severity: DataQualitySeverity.critical,
            collection: 'debts',
            recordId: debt.id,
            title: 'قەرزێکی کۆن بە مارکێتەکەوە نەبەستراوەتەوە',
            message:
                'ئەم قەرزە لە داتای کۆنە و پێویستی بە ڕێکخستنەوەی سەلامەت هەیە.',
            suggestion:
                'لە پلانی ڕێکخستنەوەدا ئەم قەرزە بە مارکێتەکەوە دەبەسترێتەوە؛ هیچ بڕی قەرزێک ناگۆڕدرێت و ناسڕدرێتەوە.',
            debtId: debt.id,
            customerId: customerId,
            canAutoFix: true,
          ),
        );
      }

      if (customerId.trim().isEmpty || !userIds.contains(customerId)) {
        issues.add(
          DataQualityIssue(
            id: 'debt_missing_customer_${debt.id}',
            type: DataQualityIssueType.missingCustomer,
            severity: DataQualitySeverity.critical,
            collection: 'debts',
            recordId: debt.id,
            title: 'قەرزێک بە کڕیارەکەوە نەبەستراوەتەوە',
            message: 'ئەم قەرزە کڕیاری دروستی پێوە نییە یان کڕیارەکە نەدۆزرایەوە.',
            suggestion:
                'پێویستە ئەم قەرزە بە کڕیاری ڕاستەوە ببەسترێتەوە بۆ ئەوەی کەشف حساب و ڕاپۆرتەکان ڕاست بن.',
            debtId: debt.id,
            customerId: customerId,
          ),
        );
      }

      if (createdBy.trim().isEmpty) {
        issues.add(
          DataQualityIssue(
            id: 'debt_missing_creator_${debt.id}',
            type: DataQualityIssueType.missingCreator,
            severity: DataQualitySeverity.warning,
            collection: 'debts',
            recordId: debt.id,
            title: 'تۆمارکەری قەرز دیار نییە',
            message: 'ئەم قەرزە دیار نییە لەلایەن کێوە تۆمارکراوە.',
            suggestion:
                'بۆ پاراستنی پارە و ڕاپۆرتی کارمەندان، باشترە تۆمارکەری هەموو قەرزێک دیار بێت.',
            debtId: debt.id,
            customerId: customerId,
          ),
        );
      }

      if (!_isValidDebtStatus(status)) {
        issues.add(
          DataQualityIssue(
            id: 'debt_invalid_status_${debt.id}',
            type: DataQualityIssueType.invalidDebtStatus,
            severity: DataQualitySeverity.critical,
            collection: 'debts',
            recordId: debt.id,
            title: 'دۆخی قەرز پێویستی بە ڕێکخستنەوە هەیە',
            message: 'دۆخی ئەم قەرزە لەگەڵ ڕێکخستنی سیستەم ناگونجێت.',
            suggestion:
                'دۆخی قەرزەکە بپشکنە و بیکە بە یەکێک لە دۆخە ڕاستەکان: چاوەڕوان، بەشێک دراوە، یان تەواو دراوە.',
            debtId: debt.id,
            customerId: customerId,
          ),
        );
      }

      if (amount < 0 || remaining < 0) {
        issues.add(
          DataQualityIssue(
            id: 'debt_invalid_amount_${debt.id}',
            type: DataQualityIssueType.invalidRemainingAmount,
            severity: DataQualitySeverity.critical,
            collection: 'debts',
            recordId: debt.id,
            title: 'بڕی قەرز پێویستی بە پشکنین هەیە',
            message: 'بڕی قەرز یان بڕی ماوە نابێت کەمتر لە سفر بێت.',
            suggestion:
                'بڕەکانی ئەم قەرزە بپشکنە بۆ ئەوەی کۆی قەرز و کەشف حساب ڕاست بمێنن.',
            debtId: debt.id,
            customerId: customerId,
          ),
        );
      }

      if (status == 'paid' && remaining > 0) {
        issues.add(
          DataQualityIssue(
            id: 'paid_debt_has_remaining_${debt.id}',
            type: DataQualityIssueType.paidDebtHasRemaining,
            severity: DataQualitySeverity.critical,
            collection: 'debts',
            recordId: debt.id,
            title: 'قەرزی تەواوکراو هێشتا ماوەی هەیە',
            message:
                'ئەم قەرزە وەک تەواو دراوە نیشان دراوە، بەڵام هێشتا بڕی ماوەی هەیە.',
            suggestion:
                'یان دۆخەکە بگۆڕە بۆ بەشێک دراوە، یان ئەگەر تەواو دراوەتەوە بڕی ماوە بکە سفر.',
            debtId: debt.id,
            customerId: customerId,
          ),
        );
      }

      if ((status == 'pending' || status == 'partial') && remaining <= 0) {
        issues.add(
          DataQualityIssue(
            id: 'unpaid_debt_has_no_remaining_${debt.id}',
            type: DataQualityIssueType.unpaidDebtHasNoRemaining,
            severity: DataQualitySeverity.warning,
            collection: 'debts',
            recordId: debt.id,
            title: 'قەرزەکە تەواوە بەڵام دۆخەکە نەگۆڕاوە',
            message: 'ئەم قەرزە هیچ بڕی ماوەی نییە، بەڵام هێشتا وەک قەرزی کراوە نیشان دەدرێت.',
            suggestion:
                'ئەگەر قەرزەکە تەواو دراوەتەوە، دۆخەکە بکە بە تەواو دراوە.',
            debtId: debt.id,
            customerId: customerId,
          ),
        );
      }
    }

    return issues;
  }

  List<DataQualityIssue> _checkPayments(
    List<RecordModel> payments,
    List<RecordModel> debts,
  ) {
    final issues = <DataQualityIssue>[];
    final debtIds = debts.map((e) => e.id).toSet();

    for (final payment in payments) {
      final debtId = payment.getStringValue('debt');
      final createdBy = payment.getStringValue('created_by');
      final adminId = payment.getStringValue('admin_id');
      final amount = payment.getDoubleValue('amount');

      if (adminId.trim().isEmpty) {
        issues.add(
          DataQualityIssue(
            id: 'payment_missing_admin_${payment.id}',
            type: DataQualityIssueType.missingAdminId,
            severity: DataQualitySeverity.critical,
            collection: 'payments',
            recordId: payment.id,
            title: 'پارەدانەوەیەکی کۆن بە مارکێتەکەوە نەبەستراوەتەوە',
            message:
                'ئەم پارەدانەوەیە لە داتای کۆنە و پێویستی بە ڕێکخستنەوەی سەلامەت هەیە.',
            suggestion:
                'لە پلانی ڕێکخستنەوەدا ئەم پارەدانەوەیە بە مارکێتەکەوە دەبەسترێتەوە؛ بڕی پارەدانەوە ناگۆڕدرێت.',
            paymentId: payment.id,
            debtId: debtId,
            canAutoFix: true,
          ),
        );
      }

      if (debtId.trim().isEmpty || !debtIds.contains(debtId)) {
        issues.add(
          DataQualityIssue(
            id: 'payment_orphan_${payment.id}',
            type: DataQualityIssueType.orphanPayment,
            severity: DataQualitySeverity.critical,
            collection: 'payments',
            recordId: payment.id,
            title: 'پارەدانەوەیەک بە قەرزەکەوە نەبەستراوەتەوە',
            message:
                'ئەم پارەدانەوەیە بە قەرزێکی دروستەوە نەبەستراوە، بۆیە لە کەشف حسابدا کێشە دروست دەکات.',
            suggestion:
                'پێویستە ئەم پارەدانەوەیە بە قەرزی ڕاستەوە ببەسترێتەوە بۆ ئەوەی ماوە و ڕاپۆرتەکان ڕاست بن.',
            paymentId: payment.id,
            debtId: debtId,
          ),
        );
      }

      if (createdBy.trim().isEmpty) {
        issues.add(
          DataQualityIssue(
            id: 'payment_missing_creator_${payment.id}',
            type: DataQualityIssueType.missingCreator,
            severity: DataQualitySeverity.warning,
            collection: 'payments',
            recordId: payment.id,
            title: 'تۆمارکەری پارەدانەوە دیار نییە',
            message: 'ئەم پارەدانەوەیە دیار نییە لەلایەن کێوە تۆمارکراوە.',
            suggestion:
                'بۆ ڕاپۆرتی کارمەندان و پاراستنی پارە، باشترە تۆمارکەری هەموو پارەدانەوەیەک دیار بێت.',
            paymentId: payment.id,
            debtId: debtId,
          ),
        );
      }

      if (amount <= 0) {
        issues.add(
          DataQualityIssue(
            id: 'payment_invalid_amount_${payment.id}',
            type: DataQualityIssueType.invalidRemainingAmount,
            severity: DataQualitySeverity.critical,
            collection: 'payments',
            recordId: payment.id,
            title: 'بڕی پارەدانەوە پێویستی بە پشکنین هەیە',
            message: 'بڕی پارەدانەوە دەبێت زیاتر لە سفر بێت.',
            suggestion: 'بڕی ئەم پارەدانەوەیە بپشکنە بۆ ئەوەی ڕاپۆرت و ماوەکان ڕاست بمێنن.',
            paymentId: payment.id,
            debtId: debtId,
          ),
        );
      }
    }

    return issues;
  }

  List<DataQualityIssue> _checkNotifications(
    List<RecordModel> notifications,
    List<RecordModel> users,
  ) {
    final issues = <DataQualityIssue>[];
    final userIds = users.map((e) => e.id).toSet();

    for (final notification in notifications) {
      final customerId = notification.getStringValue('customer');
      final sender = notification.getStringValue('sender');
      final adminId = notification.getStringValue('admin_id');
      final message = notification.getStringValue('message');

      if (adminId.trim().isEmpty) {
        issues.add(
          DataQualityIssue(
            id: 'notification_missing_admin_${notification.id}',
            type: DataQualityIssueType.missingAdminId,
            severity: DataQualitySeverity.warning,
            collection: 'notifications',
            recordId: notification.id,
            title: 'ئاگادارکردنەوەیەکی کۆن پێویستی بە ڕێکخستنەوە هەیە',
            message:
                'ئەم ئاگادارکردنەوەیە لە داتای کۆنە و بە مارکێتەکەوە نەبەستراوەتەوە.',
            suggestion:
                'لە پلانی ڕێکخستنەوەدا بە سەلامەتی بە مارکێتەکەوە دەبەسترێتەوە.',
            notificationId: notification.id,
            customerId: customerId,
            canAutoFix: true,
          ),
        );
      }

      if (customerId.trim().isEmpty || !userIds.contains(customerId)) {
        issues.add(
          DataQualityIssue(
            id: 'notification_orphan_customer_${notification.id}',
            type: DataQualityIssueType.orphanNotification,
            severity: DataQualitySeverity.warning,
            collection: 'notifications',
            recordId: notification.id,
            title: 'ئاگادارکردنەوە بە کڕیارەکەوە نەبەستراوەتەوە',
            message: 'ئەم ئاگادارکردنەوەیە کڕیاری دروستی پێوە نییە.',
            suggestion: 'ئەگەر پێویستە، ئەم ئاگادارکردنەوەیە بە کڕیاری ڕاستەوە ببەستەوە.',
            notificationId: notification.id,
            customerId: customerId,
          ),
        );
      }

      if (sender.trim().isEmpty) {
        issues.add(
          DataQualityIssue(
            id: 'notification_missing_sender_${notification.id}',
            type: DataQualityIssueType.missingCreator,
            severity: DataQualitySeverity.info,
            collection: 'notifications',
            recordId: notification.id,
            title: 'ناردەری ئاگادارکردنەوە دیار نییە',
            message: 'دیار نییە ئەم ئاگادارکردنەوەیە لەلایەن کێوە نێردراوە.',
            suggestion: 'ئەمە زۆرجار مەترسی نییە، بەڵام بۆ ڕاپۆرتی وردتر دەتوانرێت ڕێکبخرێت.',
            notificationId: notification.id,
            customerId: customerId,
          ),
        );
      }

      if (message.trim().isEmpty) {
        issues.add(
          DataQualityIssue(
            id: 'notification_empty_message_${notification.id}',
            type: DataQualityIssueType.dataMismatch,
            severity: DataQualitySeverity.warning,
            collection: 'notifications',
            recordId: notification.id,
            title: 'پەیامی ئاگادارکردنەوە بەتاڵە',
            message: 'ئەم ئاگادارکردنەوەیە هیچ پەیامێکی تێدا نییە.',
            suggestion: 'پەیامەکە بپشکنە یان ئەگەر پێویست نەبوو لە ڕاپۆرتی پشتیوانی جیا بکرێتەوە.',
            notificationId: notification.id,
            customerId: customerId,
          ),
        );
      }
    }

    return issues;
  }

  bool _isValidDebtStatus(String status) {
    return status == 'pending' || status == 'partial' || status == 'paid';
  }
}
