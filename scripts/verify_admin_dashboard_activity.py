#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
dashboard = (ROOT / 'lib/screens/admin/admin_dashboard.dart').read_text(errors='ignore')

assert "debt_detail_screen.dart" in dashboard, "admin dashboard must import DebtDetailScreen"
assert "_recentActivityFilter = 'debt'" in dashboard, "recent activity must default to the debt tab"
assert "'قەرزەکان'" in dashboard and "'پارەدانەوەکان'" in dashboard, "recent activity must expose debt/payment buttons"
assert "event_type" in dashboard and "_recentActivityFilter" in dashboard, "recent activity list must filter by event type"
assert "DebtDetailScreen(" in dashboard and "debtId:" in dashboard, "debt activity tap must open debt details"
assert "onTap:" in dashboard, "debt activity card must be tappable"


assert "_sumRecentActivityByCurrency" in dashboard, "dashboard must total recent activity by currency"
assert "'کۆی قەرزە تازەکان'" in dashboard, "dashboard must show the recent debt total"
assert "'کۆی پارەدانەوە تازەکان'" in dashboard, "dashboard must show the recent payment total"
assert "debtActivityTotals" in dashboard and "paymentActivityTotals" in dashboard, "dashboard must compute separate debt/payment totals"
assert "'IQD'" in dashboard and "'USD'" in dashboard, "recent activity totals must keep IQD and USD separate"

print("admin dashboard recent activity verified")
