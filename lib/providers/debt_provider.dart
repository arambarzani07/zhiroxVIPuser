import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/services/pb_service.dart';

class DebtProvider extends ChangeNotifier {
  List<RecordModel> _debts = [];
  List<RecordModel> _payments = [];
  bool _isLoading = false;

  List<RecordModel> get debts => _debts;
  List<RecordModel> get payments => _payments;
  bool get isLoading => _isLoading;

  Future<void> loadDebts({String? customerId, String? status}) async {
    _isLoading = true;
    notifyListeners();

    try {
      _debts = await PBService.getDebts(
        customerId: customerId,
        status: status,
      );
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadPayments({String? debtId}) async {
    _isLoading = true;
    notifyListeners();

    try {
      _payments = await PBService.getPayments(debtId: debtId);
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  Future<RecordModel> addDebt({
    required String customerId,
    required String description,
    required double amount,
    required String dueDate,
    required String createdBy,
  }) async {
    final debt = await PBService.createDebt(
      customerId: customerId,
      description: description,
      amount: amount,
      dueDate: dueDate,
      createdBy: createdBy,
    );
    await loadDebts();
    return debt;
  }

  Future<RecordModel> addPayment({
    required String debtId,
    required double amount,
    String? note,
    required String createdBy,
  }) async {
    final payment = await PBService.createPayment(
      debtId: debtId,
      amount: amount,
      note: note,
      createdBy: createdBy,
    );
    await loadDebts();
    return payment;
  }

  Future<void> removeDebt(String id) async {
    await PBService.deleteDebt(id);
    await loadDebts();
  }
}
