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
            title: 'ژمارەی مۆبایل نییە',
            message: 'ئەم بەکارهێنەرە ژمارەی مۆبایلی نییە.',
            suggestion: 'ژمارەی مۆبایل زیاد بکە بۆ ئەوەی گەڕان، ناسینەوە و ئاگادارکردنەوە ڕێک بێت.',
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
            title: 'admin_id نییە',
            message: 'ئەم بەکارهێنەرە بە هیچ ئەدمین/مارکێتێکەوە نەبەستراوە.',
            suggestion: 'admin_id بۆ ئەم بەکارهێنەرە دیاری بکە تا داتا لە نێوان مارکێتەکان تێکەڵ نەبێت.',
            customerId: user.id,
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
            title: 'قەرزێک admin_id ـی نییە',
            message: 'ئەم قەرزە بە هیچ ئەدمین/مارکێتێکەوە نەبەستراوە.',
            suggestion: 'admin_id بۆ قەرزەکە پڕ بکەوە، یان لە payment ـی داهاتوو backfill بکرێتەوە.',
            debtId: debt.id,
            customerId: customerId,
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
            title: 'قەرز بێ کڕیار',
            message: 'ئەم قەرزە کڕیاری دروستی پێوە نییە.',
            suggestion: 'پەیوەندی customer ـەکە بپشکنە یان قەرزەکە بە کڕیاری ڕاستەوە ببەستەوە.',
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
            title: 'دروستکەری قەرز دیار نییە',
            message: 'created_by بۆ ئەم قەرزە بەتاڵە.',
            suggestion: 'بۆ audit و پاراستنی پارە، باشترە هەموو قەرزێک created_by هەبێت.',
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
            title: 'دۆخی قەرز نادروستە',
            message: 'status ـی ئەم قەرزە نادروستە: $status',
            suggestion: 'status دەبێت pending، partial، یان paid بێت.',
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
            title: 'بڕی قەرز نادروستە',
            message: 'amount یان remaining ناتوانێت کەمتر لە سفر بێت.',
            suggestion: 'بڕەکان بپشکنە و record ـەکە چاک بکە.',
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
            title: 'قەرزی paid ماوەی هەیە',
            message: 'ئەم قەرزە paid ـە، بەڵام remaining ـی زیاتر لە سفرە.',
            suggestion: 'یان status بگۆڕە بۆ partial، یان remaining بکە 0.',
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
            title: 'قەرزی نەدراو ماوەی نییە',
            message: 'ئەم قەرزە pending/partial ـە، بەڵام remaining ـی 0 ـە.',
            suggestion: 'ئەگەر قەرز تەواو دراوەتەوە، status بکە paid.',
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
            title: 'پارەدانەوە admin_id ـی نییە',
            message: 'ئەم پارەدانەوەیە بە هیچ ئەدمین/مارکێتێکەوە نەبەستراوە.',
            suggestion: 'admin_id بۆ payment ـەکە پڕ بکەوە تا ڕاپۆرت و فلتەرکردن ڕاست بێت.',
            paymentId: payment.id,
            debtId: debtId,
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
            title: 'پارەدانەوە بێ قەرز',
            message: 'ئەم پارەدانەوەیە بە قەرزێکی دروستەوە نەبەستراوە.',
            suggestion: 'debt relation ـەکە بپشکنە و بە قەرزی ڕاستەوە ببەستەوە.',
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
            title: 'دروستکەری پارەدانەوە دیار نییە',
            message: 'created_by بۆ ئەم payment ـە بەتاڵە.',
            suggestion: 'بۆ audit و ڕاپۆرتی کارمەند، created_by پێویستە.',
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
            title: 'بڕی پارەدانەوە نادروستە',
            message: 'بڕی payment دەبێت زیاتر لە سفر بێت.',
            suggestion: 'بڕی payment ـەکە بپشکنە و چاکی بکە.',
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
            title: 'ئاگادارکردنەوە admin_id ـی نییە',
            message: 'ئەم ئاگادارکردنەوەیە admin_id ـی نییە.',
            suggestion: 'بۆ فلتەرکردن و tenant isolation، admin_id بۆ notification زیاد بکە.',
            notificationId: notification.id,
            customerId: customerId,
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
            title: 'ئاگادارکردنەوە بێ کڕیار',
            message: 'customer relation ـی ئەم notification ـە بەتاڵە یان نادروستە.',
            suggestion: 'customer relation ـەکە بپشکنە.',
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
            title: 'ناردەری notification دیار نییە',
            message: 'sender بۆ ئەم notification ـە بەتاڵە.',
            suggestion: 'ئەگەر پێویستە، sender بە user ـی ڕاستەوە ببەستەوە.',
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
            title: 'پەیامی notification بەتاڵە',
            message: 'message ـی ئەم notification ـە بەتاڵە.',
            suggestion: 'پەیامی notification ـەکە بپشکنە.',
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
