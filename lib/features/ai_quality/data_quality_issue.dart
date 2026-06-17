enum DataQualitySeverity {
  info,
  warning,
  critical,
}

enum DataQualityIssueType {
  missingAdminId,
  missingCustomer,
  missingDebt,
  missingCreator,
  missingPhone,
  invalidDebtStatus,
  invalidRemainingAmount,
  paidDebtHasRemaining,
  unpaidDebtHasNoRemaining,
  orphanPayment,
  orphanNotification,
  duplicateSuspicion,
  dataMismatch,
}

class DataQualityIssue {
  final String id;
  final DataQualityIssueType type;
  final DataQualitySeverity severity;

  /// PocketBase collection name, for example: users, debts, payments, notifications.
  final String collection;

  /// Related PocketBase record id.
  final String? recordId;

  /// Human-readable title shown in the UI.
  final String title;

  /// Detailed explanation shown in the UI.
  final String message;

  /// Suggested safe action for the manager/admin.
  final String suggestion;

  /// Optional related customer id.
  final String? customerId;

  /// Optional related debt id.
  final String? debtId;

  /// Optional related payment id.
  final String? paymentId;

  /// Optional related notification id.
  final String? notificationId;

  /// Whether this issue can be auto-fixed later.
  /// For now we keep everything read-only and manual.
  final bool canAutoFix;

  const DataQualityIssue({
    required this.id,
    required this.type,
    required this.severity,
    required this.collection,
    required this.title,
    required this.message,
    required this.suggestion,
    this.recordId,
    this.customerId,
    this.debtId,
    this.paymentId,
    this.notificationId,
    this.canAutoFix = false,
  });

  bool get isCritical => severity == DataQualitySeverity.critical;
  bool get isWarning => severity == DataQualitySeverity.warning;
  bool get isInfo => severity == DataQualitySeverity.info;

  String get severityLabel {
    switch (severity) {
      case DataQualitySeverity.critical:
        return 'مەترسیدار';
      case DataQualitySeverity.warning:
        return 'ئاگاداری';
      case DataQualitySeverity.info:
        return 'زانیاری';
    }
  }

  String get typeLabel {
    switch (type) {
      case DataQualityIssueType.missingAdminId:
        return 'admin_id نییە';
      case DataQualityIssueType.missingCustomer:
        return 'کڕیار نییە';
      case DataQualityIssueType.missingDebt:
        return 'قەرز نییە';
      case DataQualityIssueType.missingCreator:
        return 'دروستکەر نییە';
      case DataQualityIssueType.missingPhone:
        return 'ژمارەی مۆبایل نییە';
      case DataQualityIssueType.invalidDebtStatus:
        return 'دۆخی قەرز نادروستە';
      case DataQualityIssueType.invalidRemainingAmount:
        return 'بڕی ماوە نادروستە';
      case DataQualityIssueType.paidDebtHasRemaining:
        return 'قەرزی paid ماوەی هەیە';
      case DataQualityIssueType.unpaidDebtHasNoRemaining:
        return 'قەرزی نەدراو ماوەی نییە';
      case DataQualityIssueType.orphanPayment:
        return 'پارەدانەوە بێ قەرز';
      case DataQualityIssueType.orphanNotification:
        return 'ئاگادارکردنەوە بێ پەیوەندی';
      case DataQualityIssueType.duplicateSuspicion:
        return 'گومانی دووبارەبوونەوە';
      case DataQualityIssueType.dataMismatch:
        return 'داتا یەکناگرێتەوە';
    }
  }

  DataQualityIssue copyWith({
    String? id,
    DataQualityIssueType? type,
    DataQualitySeverity? severity,
    String? collection,
    String? recordId,
    String? title,
    String? message,
    String? suggestion,
    String? customerId,
    String? debtId,
    String? paymentId,
    String? notificationId,
    bool? canAutoFix,
  }) {
    return DataQualityIssue(
      id: id ?? this.id,
      type: type ?? this.type,
      severity: severity ?? this.severity,
      collection: collection ?? this.collection,
      recordId: recordId ?? this.recordId,
      title: title ?? this.title,
      message: message ?? this.message,
      suggestion: suggestion ?? this.suggestion,
      customerId: customerId ?? this.customerId,
      debtId: debtId ?? this.debtId,
      paymentId: paymentId ?? this.paymentId,
      notificationId: notificationId ?? this.notificationId,
      canAutoFix: canAutoFix ?? this.canAutoFix,
    );
  }
}
