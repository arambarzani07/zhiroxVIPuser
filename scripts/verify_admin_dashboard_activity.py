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


build_start = dashboard.index('Widget _buildNewDashboard')
build_end = dashboard.index('Future<void> _showReportMenu', build_start)
build_block = dashboard[build_start:build_end]
assert 'CustomScrollView(' in build_block and 'SliverList' in build_block, "dashboard must scroll as one page so every section remains reachable"

header_start = dashboard.index('Widget _buildHeaderStat')
header_end = dashboard.index('Map<String, double> _sumRecentActivityByCurrency', header_start)
header_block = dashboard[header_start:header_end]
assert 'height: 82' not in header_block, "dashboard header cards must grow with their content"
assert 'TextOverflow.ellipsis' not in header_block, "dashboard header values and labels must stay fully visible"

total_start = dashboard.index('Widget _buildRecentActivityTotalCard')
total_end = dashboard.index('Widget _buildRecentActivityFilterButton', total_start)
total_block = dashboard[total_start:total_end]
assert 'TextOverflow.ellipsis' not in total_block, "recent activity total cards must not clip totals or labels"

activity_start = dashboard.index('Widget _buildActivityCard')
activity_block = dashboard[activity_start:]
assert 'TextOverflow.ellipsis' not in activity_block, "recent activity rows must show customer, date and amount without clipping"

assert 'static const BoxConstraints _compactDialogConstraints' in dashboard, "admin dialogs must use compact content-sized constraints"
assert dashboard.count('constraints: _compactDialogConstraints') >= 2, "phone and password dialogs must both use compact constraints"
assert 'scrollable: true' in dashboard, "admin dialogs must remain compact but scroll safely when content grows"

print("admin dashboard recent activity verified")
