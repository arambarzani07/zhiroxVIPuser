from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


# PBService: defensively enforce the same rolling 24h window and ordering on
# the client, so stale snapshots cannot leak older/non-financial activity.
pb_path = Path('lib/services/pb_service.dart')
pb = pb_path.read_text()
pb = replace_once(
    pb,
    "import 'package:zhirox/services/supabase_compat.dart';",
    "import 'package:zhirox/services/dashboard_recent_activity.dart';\nimport 'package:zhirox/services/supabase_compat.dart';",
    'PBService import',
)
pb = replace_once(
    pb,
    """    final recent = <RecordModel>[];
    if (data['recent_activity'] is List) {
      for (final item in data['recent_activity'] as List) {
        if (item is Map) {
          recent.add(_dashboardDebtRecord(Map<String, dynamic>.from(item)));
        }
      }
    }
""",
    """    final recentRows = <Map<String, dynamic>>[];
    if (data['recent_activity'] is List) {
      for (final item in data['recent_activity'] as List) {
        if (item is Map) {
          recentRows.add(Map<String, dynamic>.from(item));
        }
      }
    }
    final recent = filterAndSortRecentDashboardActivity(recentRows)
        .map(_dashboardDebtRecord)
        .toList(growable: false);
""",
    'PBService recent activity normalization',
)
pb_path.write_text(pb)


# Admin dashboard: pin dashboard chrome and recent-activity heading. Only the
# activity list receives vertical scroll gestures.
dash_path = Path('lib/screens/admin/admin_dashboard.dart')
dash = dash_path.read_text()
dash = replace_once(
    dash,
    """    return RefreshIndicator(
      onRefresh: _loadStats,
      child: CustomScrollView(
        slivers: [
""",
    """    return Column(
      children: [
""",
    'dashboard outer scroll',
)
dash = replace_once(
    dash,
    """          // ───── Gradient Header with Stats ─────
          SliverToBoxAdapter(
            child: Container(
""",
    """        // ───── Gradient Header with Stats (fixed) ─────
        Container(
""",
    'dashboard gradient wrapper',
)

recent_marker = '\n\n\n          // ───── Recent Activity Header ─────'
marker_index = dash.find(recent_marker)
if marker_index < 0:
    raise SystemExit('recent activity marker not found')
# Remove the trailing SliverToBoxAdapter close that wrapped the gradient.
prefix = dash[:marker_index]
wrapper_close = '\n          ),'
close_index = prefix.rfind(wrapper_close)
if close_index < 0:
    raise SystemExit('gradient sliver wrapper close not found')
prefix = prefix[:close_index] + prefix[close_index + len(wrapper_close):]
dash = prefix + dash[marker_index:]

recent_start = dash.index('          // ───── Recent Activity Header ─────')
next_method = dash.index('\n  Future<void> _showReportMenu', recent_start)
recent_block = """        // ───── Recent Activity Header (fixed) ─────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Row(
            children: [
              Icon(
                Icons.history,
                size: 18,
                color: isDark
                    ? AppDarkColors.textSecondary
                    : Colors.black54,
              ),
              const SizedBox(width: 8),
              Text(
                'چالاکییە تازەکان',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? AppDarkColors.textPrimary
                      : Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppDarkColors.cardBorder
                      : Colors.grey[200],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${recentActivity.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : Colors.grey[600],
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '٢٤ کاتژمێر',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppDarkColors.textSecondary
                      : const Color(0xFF98A2B3),
                ),
              ),
            ],
          ),
        ),

        // Only this list scrolls; the dashboard header and section title stay fixed.
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadStats,
            child: recentActivity.isEmpty
                ? ListView(
                    key: const PageStorageKey('dashboard-recent-activity-empty'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 32,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          'لە ٢٤ کاتژمێری ڕابردوودا هیچ چالاکیەک نییە',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    key: const PageStorageKey('dashboard-recent-activity-list'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    itemCount: recentActivity.length,
                    itemBuilder: (context, index) =>
                        _buildActivityCard(recentActivity[index], index),
                  ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
"""
dash = dash[:recent_start] + recent_block + dash[next_method:]

activity_method_start = dash.index('  Widget _buildActivityCard(')
class_close = dash.rfind('\n}')
if class_close <= activity_method_start:
    raise SystemExit('activity card/class boundary not found')
activity_method = """  Widget _buildActivityCard(RecordModel activity, int index) {
    final customer = AppHelpers.expandedRecord(activity, 'customer');
    final createdBy = AppHelpers.expandedRecord(activity, 'created_by');

    final amount = activity.getDoubleValue('amount');
    final date = activity.getStringValue('created');
    final currency = activity.getStringValue('currency').isEmpty
        ? 'IQD'
        : activity.getStringValue('currency');
    final eventType = activity.getStringValue('event_type');
    final isPayment = eventType == 'payment';
    final isByEmployee = createdBy?.getStringValue('role') == 'employee';
    final creatorName = createdBy?.getStringValue('name') ?? '';
    final customerName =
        customer?.getStringValue('name') ?? 'کڕیار سڕدراوەتەوە';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isPayment ? Colors.green.shade600 : AppColors.primary;
    final activityLabel = isPayment ? 'پارەدانەوە' : 'قەرز';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE9EDF3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isPayment
                  ? Icons.payments_outlined
                  : Icons.receipt_long_outlined,
              color: accent,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppDarkColors.textPrimary
                              : const Color(0xFF344054),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        activityLabel,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (isByEmployee && creatorName.isNotEmpty) creatorName,
                    AppHelpers.formatDate(date),
                  ].join('  •  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : const Color(0xFF98A2B3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            AppHelpers.formatCurrencyWithType(
              amount,
              currency,
              showConversion: false,
            ),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: isPayment
                  ? accent
                  : (isDark
                        ? AppDarkColors.textPrimary
                        : const Color(0xFF101828)),
            ),
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }
"""
dash = dash[:activity_method_start] + activity_method + dash[class_close:]
dash_path.write_text(dash)
