import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/debt_balance.dart';

class DashboardStatsSafeService {
  static PocketBase get _pb => PBService.pb;

  static String _safe(String value) {
    return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  }

  static Future<Map<String, dynamic>> getStats({required String adminId}) async {
    final safeAdminId = _safe(adminId);

    final customersResult = await _pb.collection('users').getList(
          filter: 'role="customer" && approved=true && admin_id="$safeAdminId"',
          perPage: 1,
        );

    final pendingRequestsResult = await _pb.collection('users').getList(
          filter: 'role="customer" && approved=false && admin_id="$safeAdminId"',
          perPage: 1,
        );

    final debtsResult = await _pb.collection('debts').getList(
          filter: 'customer.admin_id="$safeAdminId" && is_deleted=false',
          sort: '-created',
          perPage: 500,
          expand: 'customer,created_by',
        );

    final debts = DebtBalance.visible(debtsResult.items).toList();
    final visibleDebtIds = debts.map((debt) => debt.id).toSet();

    final paymentsResult = await _pb.collection('payments').getList(
          filter: 'debt.customer.admin_id="$safeAdminId"',
          perPage: 500,
          expand: 'debt,created_by,debt.customer',
        );

    final payments = paymentsResult.items.where((payment) {
      return visibleDebtIds.contains(payment.getStringValue('debt'));
    }).toList();

    final totalDebt = debts.fold<double>(0, (sum, debt) => sum + DebtBalance.amount(debt));
    final totalRemaining = DebtBalance.totalRemaining(debts);
    final totalPayments = payments.fold<double>(0, (sum, payment) => sum + payment.getDoubleValue('amount'));
    final pendingDebts = DebtBalance.activeCount(debts);
    final recentActivity = debts.take(5).toList();

    return {
      'totalCustomers': customersResult.totalItems,
      'totalDebt': totalDebt,
      'totalRemaining': totalRemaining,
      'totalPayments': totalPayments,
      'pendingDebts': pendingDebts,
      'pendingRequests': pendingRequestsResult.totalItems,
      'recentActivity': recentActivity,
    };
  }
}
