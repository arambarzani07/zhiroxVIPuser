import 'package:flutter/material.dart';
import 'package:zhirox/models/record_model.dart';
import 'package:zhirox/services/pb_service.dart';

/// Read-only debt state for the customer application.
///
/// Debt/payment mutations belong to C-Panel. Keeping this provider read-only
/// prevents privileged write flows from being exposed through customer state.
class DebtProvider extends ChangeNotifier {
  List<RecordModel> _debts = const [];
  List<RecordModel> _payments = const [];
  bool _isLoading = false;
  String? _error;

  List<RecordModel> get debts => List.unmodifiable(_debts);
  List<RecordModel> get payments => List.unmodifiable(_payments);
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadDebts({required String customerId, String? status}) async {
    if (customerId.isEmpty) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _debts = await PBService.getDebts(
        customerId: customerId,
        status: status,
      );
    } catch (_) {
      _error = 'قەرزەکان بار نەبوون';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadPayments({required String debtId}) async {
    if (debtId.isEmpty) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _payments = await PBService.getPayments(debtId: debtId);
    } catch (_) {
      _error = 'پارەدانەوەکان بار نەبوون';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clear() {
    _debts = const [];
    _payments = const [];
    _error = null;
    notifyListeners();
  }
}
