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

print("admin dashboard recent activity verified")
