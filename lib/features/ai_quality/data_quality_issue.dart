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

  /// Internal collection name from PocketBase.
  /// Keep this technical value for code only.
  /// Do not show it directly to the manager UI.
  final String collection;

  /// Internal record id for support/debug only.
  /// Should stay hidden from normal manager UI.
  final String? recordId;

  /// Manager-friendly title shown in the UI.
  final String title;

  /// Manager-friendly explanation shown in the UI.
  final String message;

  /// Safe suggested action for the manager.
  final String suggestion;

  final String? customerId;
  final String? debtId;
  final String? paymentId;
  final String? notificationId;

  /// Whether this issue may be safely fixed later by a controlled repair flow.
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

  /// Label suitable for market managers.
  String get severityLabel {
    switch (severity) {
      case DataQualitySeverity.critical:
        return 'گرنگ';
      case DataQualitySeverity.warning:
        return 'ئاگاداری';
      case DataQualitySeverity.info:
        return 'زانیاری';
    }
  }

  /// Manager-friendly issue label.
  /// No technical database field names should appear here.
  String get typeLabel {
    switch (type) {
      case DataQualityIssueType.missingAdminId:
        return 'پەیوەندی مارکێت نییە';
      case DataQualityIssueType.missingCustomer:
        return 'کڕیار دیار نییە';
      case DataQualityIssueType.missingDebt:
        return 'قەرز دیار نییە';
      case DataQualityIssueType.missingCreator:
        return 'تۆمارکەر دیار نییە';
      case DataQualityIssueType.missingPhone:
        return 'ژمارەی مۆبایل تەواو نییە';
      case DataQualityIssueType.invalidDebtStatus:
        return 'دۆخی قەرز پێویستی بە ڕێکخستنەوە هەیە';
      case DataQualityIssueType.invalidRemainingAmount:
        return 'بڕی پارە پێویستی بە پشکنین هەیە';
      case DataQualityIssueType.paidDebtHasRemaining:
        return 'قەرزی تەواوکراو هێشتا ماوەی هەیە';
      case DataQualityIssueType.unpaidDebtHasNoRemaining:
        return 'قەرزەکە تەواوە بەڵام دۆخەکە نەگۆڕاوە';
      case DataQualityIssueType.orphanPayment:
        return 'پارەدانەوە بە قەرزەکەوە نەبەستراوەتەوە';
      case DataQualityIssueType.orphanNotification:
        return 'ئاگادارکردنەوە بە کڕیارەکەوە نەبەستراوەتەوە';
      case DataQualityIssueType.duplicateSuspicion:
        return 'گومانی دووبارەبوونەوە';
      case DataQualityIssueType.dataMismatch:
        return 'داتا پێویستی بە پشکنین هەیە';
    }
  }

  /// Manager-friendly collection label.
  /// Use this instead of showing users/debts/payments/notifications.
  String get collectionLabel {
    switch (collection) {
      case 'users':
        return 'کڕیار و بەکارهێنەر';
      case 'debts':
        return 'قەرزەکان';
      case 'payments':
        return 'پارەدانەوەکان';
      case 'notifications':
        return 'ئاگادارکردنەوەکان';
      default:
        return 'داتای مارکێت';
    }
  }

  /// Short manager-friendly repair wording.
  String get safeActionLabel {
    switch (type) {
      case DataQualityIssueType.missingAdminId:
        return 'ڕێکخستنەوەی پەیوەندی مارکێت';
      case DataQualityIssueType.missingCustomer:
        return 'بەستنەوەی کڕیار';
      case DataQualityIssueType.missingDebt:
      case DataQualityIssueType.orphanPayment:
        return 'بەستنەوەی قەرز';
      case DataQualityIssueType.missingCreator:
        return 'دیاریکردنی تۆمارکەر';
      case DataQualityIssueType.missingPhone:
        return 'تەواوکردنی ژمارەی مۆبایل';
      case DataQualityIssueType.invalidDebtStatus:
      case DataQualityIssueType.paidDebtHasRemaining:
      case DataQualityIssueType.unpaidDebtHasNoRemaining:
        return 'ڕێکخستنەوەی دۆخی قەرز';
      case DataQualityIssueType.invalidRemainingAmount:
        return 'پشکنینی بڕی پارە';
      case DataQualityIssueType.orphanNotification:
        return 'بەستنەوەی ئاگادارکردنەوە';
      case DataQualityIssueType.duplicateSuspicion:
        return 'پشکنینی دووبارەبوونەوە';
      case DataQualityIssueType.dataMismatch:
        return 'پشکنینی داتا';
    }
  }

  /// Whether this issue is usually related to old imported/legacy data.
  bool get isLikelyOldDataIssue {
    switch (type) {
      case DataQualityIssueType.missingAdminId:
      case DataQualityIssueType.missingCreator:
      case DataQualityIssueType.orphanPayment:
      case DataQualityIssueType.orphanNotification:
        return true;
      default:
        return false;
    }
  }

  /// Main manager message for grouped/summary screens.
  String get managerSummary {
    if (isLikelyOldDataIssue) {
      return 'ئەمە زۆرجار لە داتای کۆن ڕوودەدات و بە پلانی ڕێکخستنەوەی سەلامەت چارەسەر دەکرێت.';
    }

    switch (severity) {
      case DataQualitySeverity.critical:
        return 'ئەم خاڵە پێویستی بە پشکنینی خێرا هەیە بۆ ئەوەی داتا ڕێک بمێنێت.';
      case DataQualitySeverity.warning:
        return 'ئەم خاڵە پێویستی بە ئاگاداری و ڕێکخستنەوە هەیە.';
      case DataQualitySeverity.info:
        return 'ئەم خاڵە تەنها زانیارییە و بۆ باشترکردنی ڕێکخستنی داتایە.';
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
