from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
profile_path = ROOT / 'lib/screens/shared/user_profile_screen.dart'
verifier_path = ROOT / 'scripts/verify_online_only.py'

profile = profile_path.read_text(encoding='utf-8')

class_anchor = """  bool get isPayment => kind == 'payment';
  bool get isSystem => kind == 'system';
}


class _UserProfileScreenState extends State<UserProfileScreen> {
"""
class_replacement = """  bool get isPayment => kind == 'payment';
  bool get isSystem => kind == 'system';
}

class _FinancialChatRenderEntry {
  final _ProfileTimelineItem? item;
  final DateTime? separatorDate;
  final int timelineIndex;

  const _FinancialChatRenderEntry.item(
    _ProfileTimelineItem this.item,
    this.timelineIndex,
  ) : separatorDate = null;

  const _FinancialChatRenderEntry.separator(
    DateTime this.separatorDate,
    this.timelineIndex,
  ) : item = null;

  bool get isSeparator => separatorDate != null;
}

class _UserProfileScreenState extends State<UserProfileScreen> {
"""
if class_anchor not in profile:
    raise SystemExit('Financial Chat render-entry class anchor not found')
profile = profile.replace(class_anchor, class_replacement, 1)

method_start = profile.index('  Widget _buildCustomerChatTimelineCard({')
method_end = profile.index('  Widget _buildChatSummaryValue({', method_start)
new_method = r'''  Widget _buildCustomerChatTimelineCard({
    required double totalDebt,
    required double totalRemaining,
    required double totalPaid,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allTimelineItems = _buildTimelineItems();
    final timelineItems = _filterFinancialTimeline(allTimelineItems);
    final runningBalances = _financialRunningBalances(allTimelineItems);
    final renderEntries = _buildFinancialChatRenderEntries(timelineItems);
    final totalsComplete = AppHelpers.debtSummaryInIqd(_debts).complete;
    final health = _debtHealth(totalRemaining, totalDebt);

    Widget buildHeader() {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: isDark ? AppDarkColors.card : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFE7ECF3),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.forum_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'چاتی دارایی',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? AppDarkColors.textPrimary
                                    : const Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${timelineItems.length}/${allTimelineItems.length} مامەڵە • قەرز و پارەدانەوە لە یەک مێژوودا',
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
                      IconButton(
                        tooltip: 'نوێکردنەوە',
                        onPressed: _financialRefreshInFlight
                            ? null
                            : () => _refreshFinancialData(showError: true),
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildChatSummaryValue(
                        label: 'قەرز',
                        value: totalsComplete ? totalDebt : double.nan,
                        color: Colors.orange,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 7),
                      _buildChatSummaryValue(
                        label: 'دراوە',
                        value: totalsComplete ? totalPaid : double.nan,
                        color: Colors.green,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 7),
                      _buildChatSummaryValue(
                        label: 'ماوە',
                        value: totalsComplete ? totalRemaining : double.nan,
                        color: totalsComplete && totalRemaining > 0
                            ? Colors.red
                            : Colors.green,
                        isDark: isDark,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildFinancialChatTools(
                    totalDebt: totalDebt,
                    totalRemaining: totalRemaining,
                    totalPaid: totalPaid,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            if (totalsComplete)
              _buildDebtHealthStrip(
                label: health.$1,
                color: health.$2,
                totalRemaining: totalRemaining,
                totalPaid: totalPaid,
              )
            else
              _buildCurrencySummaryWarning(compact: true),
            const SizedBox(height: 12),
            if (timelineItems.isEmpty)
              allTimelineItems.isEmpty
                  ? _buildEmptyTimelineState(isDark)
                  : _buildFilteredTimelineEmptyState(isDark),
          ],
        ),
      );
    }

    // One virtualized sliver owns both the Financial Chat header and the
    // timeline rows. Unlike spreading a List<Widget> into a Column, this only
    // builds message bubbles close to the viewport and keeps long histories
    // responsive without changing search/filter/realtime semantics.
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == 0) return buildHeader();
          if (index == renderEntries.length + 1) {
            return const SizedBox(height: 8);
          }

          final entry = renderEntries[index - 1];
          final child = entry.isSeparator
              ? _buildChatDaySeparator(entry.separatorDate!)
              : entry.item!.isSystem
                  ? _buildFinancialSystemMessage(entry.item!)
                  : _buildTimelineBubble(
                      entry.item!,
                      entry.timelineIndex,
                      balanceAfter:
                          runningBalances[_timelineLedgerKey(entry.item!)],
                    );
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: child,
          );
        },
        childCount: renderEntries.length + 2,
        addAutomaticKeepAlives: false,
      ),
    );
  }

'''
profile = profile[:method_start] + new_method + profile[method_end:]

messages_start = profile.index('  List<Widget> _buildFinancialChatMessages(')
messages_end = profile.index('  Widget _buildChatDaySeparator(DateTime date) {', messages_start)
new_entries_method = r'''  List<_FinancialChatRenderEntry> _buildFinancialChatRenderEntries(
    List<_ProfileTimelineItem> timelineItems,
  ) {
    final entries = <_FinancialChatRenderEntry>[];
    DateTime? previousDay;

    for (var index = 0; index < timelineItems.length; index++) {
      final item = timelineItems[index];
      final day = DateTime(item.date.year, item.date.month, item.date.day);
      if (previousDay == null || day != previousDay) {
        entries.add(_FinancialChatRenderEntry.separator(item.date, index));
        previousDay = day;
      }
      entries.add(_FinancialChatRenderEntry.item(item, index));
    }
    return entries;
  }

'''
profile = profile[:messages_start] + new_entries_method + profile[messages_end:]
profile_path.write_text(profile, encoding='utf-8')

verifier = verifier_path.read_text(encoding='utf-8')
verifier_anchor = """if 'getFinancialEvents(String customerId)' not in pb:
    fail('lib/services/pb_service.dart: Financial Chat audit reader missing')


# Financial Chat Phase 4 must remain live-only and keep its integrated search,
"""
verifier_replacement = """if 'getFinancialEvents(String customerId)' not in pb:
    fail('lib/services/pb_service.dart: Financial Chat audit reader missing')

# Long Financial Chat histories must stay virtualized. Building every message
# bubble eagerly inside a Column causes large customer ledgers to jank/freeze.
for marker in (
    '_FinancialChatRenderEntry',
    '_buildFinancialChatRenderEntries',
    'SliverChildBuilderDelegate',
    'addAutomaticKeepAlives: false',
):
    if marker not in profile:
        fail(f'lib/screens/shared/user_profile_screen.dart: Financial Chat virtualization marker missing: {marker}')
if '_buildFinancialChatMessages(' in profile:
    fail('lib/screens/shared/user_profile_screen.dart: eager Financial Chat message widget list must not return')


# Financial Chat Phase 4 must remain live-only and keep its integrated search,
"""
if verifier_anchor not in verifier:
    raise SystemExit('Verifier Financial Chat anchor not found')
verifier = verifier.replace(verifier_anchor, verifier_replacement, 1)
verifier_path.write_text(verifier, encoding='utf-8')

print('Financial Chat virtualization patch applied.')
