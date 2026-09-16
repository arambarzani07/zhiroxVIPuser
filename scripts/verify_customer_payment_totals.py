from pathlib import Path

dashboard = Path('lib/screens/customer/customer_dashboard.dart').read_text()
pdf = Path('lib/services/pdf_service.dart').read_text()
assert "_totalPaidAmount = snapshot['totalPaidIqd'] as double" in dashboard
assert 'totalPaid: _totalPaid' in dashboard
assert 'final totalPaid = _totalPaid;' in dashboard
assert 'totalPaid: _totalDebt - _totalRemaining' not in dashboard
assert 'final totalPaid = _totalDebt - _totalRemaining' not in dashboard
assert 'کۆی هەموو پارەدانەوەکان' in pdf
assert 'formatter.format(totalPaid)' in pdf
print('Customer cumulative payment total verification passed.')
