import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/services/pb_service.dart';

/// Action-only debt facade.
///
/// ZHIROX is online-only, so this provider intentionally does not retain
/// debt/payment lists or silently reuse stale in-memory data after a failed
/// server refresh. Screens own their live query state and show explicit errors.
class DebtProvider extends ChangeNotifier {
  Future<RecordModel> addDebt({
    required String customerId,
    required String description,
    required double amount,
    required String dueDate,
    required String createdBy,
  }) {
    return PBService.createDebt(
      customerId: customerId,
      description: description,
      amount: amount,
      dueDate: dueDate,
      createdBy: createdBy,
    );
  }

  Future<RecordModel> addPayment({
    required String debtId,
    required double amount,
    String? note,
    required String createdBy,
  }) {
    return PBService.createPayment(
      debtId: debtId,
      amount: amount,
      note: note,
      createdBy: createdBy,
    );
  }

  Future<void> removeDebt(String id) {
    return PBService.deleteDebt(id);
  }
}
