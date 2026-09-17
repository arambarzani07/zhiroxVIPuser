import 'package:flutter/foundation.dart';

/// Dispatches the push side-effect after a debt has already been persisted.
///
/// Push delivery is intentionally best-effort: a notification outage must
/// never turn a successfully-created financial record into a failed action.
/// The caller may await this helper safely because delivery errors are caught.
Future<void> enqueueDebtPushBestEffort({
  required String debtId,
  required Future<void> Function(String debtId) invoke,
  void Function(Object error)? onError,
}) async {
  final normalizedDebtId = debtId.trim();
  if (normalizedDebtId.isEmpty) return;

  try {
    await invoke(normalizedDebtId);
  } catch (error) {
    onError?.call(error);
    debugPrint('Debt push enqueue deferred: $error');
  }
}
