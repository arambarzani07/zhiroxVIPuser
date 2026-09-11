from pathlib import Path
import os
import re

ROOT = Path(os.environ.get('REPO_ROOT', Path.cwd())).resolve()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected one match, found {count}')
    return text.replace(old, new, 1)


# -----------------------------------------------------------------------------
# PBService: server-side finance snapshot + deterministic composite-cursor page.
# -----------------------------------------------------------------------------
pb_path = ROOT / 'lib/services/pb_service.dart'
pb = pb_path.read_text(encoding='utf-8')
anchor = '''  static Future<List<RecordModel>> getFinancialEvents(String customerId) async {\n    await ensureInitialized();\n    final data = await client\n        .from('financial_events')\n        .select()\n        .eq('customer_id', customerId)\n        .order('created_at', ascending: false)\n        .limit(500);\n    final events = (data as List)\n        .map((row) => _financialEventRecord(\n              Map<String, dynamic>.from(row as Map),\n            ))\n        .toList();\n    return events.reversed.toList(growable: false);\n  }\n\n'''
addition = anchor + r'''  static double _financeDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static RecordModel _debtRecordFromRaw(Map<String, dynamic> row) {
    final items = row['items'];
    final created = row['created_at']?.toString() ?? row['created']?.toString() ?? '';
    final updated = row['updated_at']?.toString() ?? row['updated']?.toString() ?? created;
    return RecordModel.fromJson({
      ...row,
      'id': row['id']?.toString() ?? '',
      'collectionId': '',
      'collectionName': 'debts',
      'customer': row['customer_id']?.toString() ?? row['customer']?.toString() ?? '',
      'receipt_image': row['receipt_image_path']?.toString() ??
          row['receipt_image']?.toString() ??
          '',
      'items': items is String ? items : jsonEncode(items ?? const <dynamic>[]),
      'created': created,
      'updated': updated,
    });
  }

  static RecordModel _paymentRecordFromRaw(
    Map<String, dynamic> row, {
    Map<String, dynamic>? relatedDebt,
  }) {
    final created = row['created_at']?.toString() ?? row['created']?.toString() ?? '';
    final json = <String, dynamic>{
      ...row,
      'id': row['id']?.toString() ?? '',
      'collectionId': '',
      'collectionName': 'payments',
      'debt': row['debt_id']?.toString() ?? row['debt']?.toString() ?? '',
      'created': created,
      'updated': row['updated_at']?.toString() ?? created,
    };
    if (relatedDebt != null) {
      json['expand'] = <String, dynamic>{
        'debt': _debtRecordFromRaw(relatedDebt).toJson(),
      };
    }
    return RecordModel.fromJson(json);
  }

  static Future<Map<String, dynamic>> getCustomerFinanceSnapshot(
    String customerId,
  ) async {
    await ensureInitialized();
    final raw = await client.rpc(
      'get_customer_finance_snapshot',
      params: {'p_customer_id': customerId},
    );
    if (raw is! Map) throw Exception('invalid finance snapshot');
    final data = Map<String, dynamic>.from(raw);
    final openRaw = data['open_debts'];
    final openDebts = <RecordModel>[];
    if (openRaw is List) {
      for (final item in openRaw) {
        if (item is Map) {
          openDebts.add(
            _debtRecordFromRaw(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return {
      'totalDebtIqd': _financeDouble(data['total_debt_iqd']),
      'totalRemainingIqd': _financeDouble(data['total_remaining_iqd']),
      'totalPaidIqd': _financeDouble(data['total_paid_iqd']),
      'openDebtCount': int.tryParse('${data['open_debt_count'] ?? 0}') ?? 0,
      'openDebts': openDebts,
      'complete': data['complete'] == true,
    };
  }

  static Future<Map<String, dynamic>> getCustomerFinancialTimelinePage({
    required String customerId,
    int limit = 50,
    Map<String, dynamic>? cursor,
  }) async {
    await ensureInitialized();
    final params = <String, dynamic>{
      'p_customer_id': customerId,
      'p_limit': limit.clamp(1, 100),
    };
    if (cursor != null) {
      final at = cursor['at']?.toString() ?? '';
      final kind = int.tryParse('${cursor['kind_rank'] ?? ''}');
      final id = cursor['id']?.toString() ?? '';
      if (at.isNotEmpty && kind != null && id.isNotEmpty) {
        params['p_cursor_at'] = at;
        params['p_cursor_kind'] = kind;
        params['p_cursor_id'] = id;
      }
    }

    final raw = await client.rpc(
      'get_customer_financial_timeline_page',
      params: params,
    );
    if (raw is! Map) throw Exception('invalid financial timeline page');
    final data = Map<String, dynamic>.from(raw);
    final debts = <RecordModel>[];
    final payments = <RecordModel>[];
    final financialEvents = <RecordModel>[];
    final rawItems = data['items'];
    if (rawItems is List) {
      for (final rawItem in rawItems) {
        if (rawItem is! Map) continue;
        final item = Map<String, dynamic>.from(rawItem);
        final kind = item['kind']?.toString() ?? '';
        final recordRaw = item['record'];
        if (recordRaw is! Map) continue;
        final record = Map<String, dynamic>.from(recordRaw);
        if (kind == 'debt') {
          debts.add(_debtRecordFromRaw(record));
        } else if (kind == 'payment') {
          Map<String, dynamic>? related;
          final relatedRaw = item['related_debt'];
          if (relatedRaw is Map) {
            related = Map<String, dynamic>.from(relatedRaw);
          }
          payments.add(
            _paymentRecordFromRaw(record, relatedDebt: related),
          );
        } else if (kind == 'system') {
          financialEvents.add(_financialEventRecord(record));
        }
      }
    }

    final nextRaw = data['next_cursor'];
    return {
      'debts': debts,
      'payments': payments,
      'financialEvents': financialEvents,
      'hasMore': data['has_more'] == true,
      'nextCursor': nextRaw is Map
          ? Map<String, dynamic>.from(nextRaw)
          : null,
      'loadedCount': rawItems is List ? rawItems.length : 0,
    };
  }

  static Future<List<RecordModel>> getAllCustomerDebtsLive(
    String customerId,
  ) async {
    await ensureInitialized();
    const pageSize = 500;
    var offset = 0;
    final records = <RecordModel>[];
    while (true) {
      final data = await client
          .from('debts')
          .select()
          .eq('customer_id', customerId)
          .order('created_at', ascending: false)
          .range(offset, offset + pageSize - 1);
      final rows = (data as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
      records.addAll(rows.map(_debtRecordFromRaw));
      if (rows.length < pageSize) break;
      offset += pageSize;
    }
    return records;
  }

'''
pb = replace_once(pb, anchor, addition, 'PBService finance pagination insertion')
pb_path.write_text(pb, encoding='utf-8')

# -----------------------------------------------------------------------------
# Customer profile: snapshot/open debt state + cursor timeline loading.
# -----------------------------------------------------------------------------
profile_path = ROOT / 'lib/screens/shared/user_profile_screen.dart'
profile = profile_path.read_text(encoding='utf-8')

profile = replace_once(profile, '''  List<RecordModel> _debts = [];\n  List<RecordModel> _payments = [];\n  List<RecordModel> _financialEvents = [];\n''', '''  // Timeline records contain only server pages already loaded into Financial Chat.\n  List<RecordModel> _debts = [];\n  List<RecordModel> _payments = [];\n  List<RecordModel> _financialEvents = [];\n  // Payment actions need all currently-open debts, not the historical timeline.\n  List<RecordModel> _openDebts = [];\n  double _financeTotalDebtIqd = 0;\n  double _financeTotalRemainingIqd = 0;\n  double _financeTotalPaidIqd = 0;\n  bool _financeSummaryComplete = false;\n  bool _financialTimelineHasMore = false;\n  Map<String, dynamic>? _financialTimelineCursor;\n  bool _financialHistoryLoading = false;\n  bool _financialFilterHydrating = false;\n  String? _financialHistoryError;\n''', 'profile pagination state')

old_load = re.search(r'''  Future<void> _loadData\(\) async \{.*?\n  \}\n\n  Future<void> _subscribeFinancialRealtime''', profile, re.S)
if not old_load:
    raise SystemExit('profile _loadData block not found')
new_load = r'''  Future<void> _loadData() async {
    if (!mounted || _loadInFlight) return;
    _loadInFlight = true;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final user = await PBService.getUser(widget.userId);
      final role = user.getStringValue('role');

      List<RecordModel> debts = [];
      List<RecordModel> payments = [];
      List<RecordModel> financialEvents = [];
      List<RecordModel> openDebts = [];
      var totalDebtIqd = 0.0;
      var totalRemainingIqd = 0.0;
      var totalPaidIqd = 0.0;
      var summaryComplete = false;
      var timelineHasMore = false;
      Map<String, dynamic>? timelineCursor;
      Map<String, double> employeeStats = {};

      if (role == 'customer') {
        final customerData = await Future.wait<Map<String, dynamic>>([
          PBService.getCustomerFinanceSnapshot(widget.userId),
          PBService.getCustomerFinancialTimelinePage(
            customerId: widget.userId,
            limit: 50,
          ),
        ]);
        final snapshot = customerData[0];
        final page = customerData[1];
        debts = List<RecordModel>.from(page['debts'] as List? ?? const []);
        payments = List<RecordModel>.from(page['payments'] as List? ?? const []);
        financialEvents = List<RecordModel>.from(
          page['financialEvents'] as List? ?? const [],
        );
        openDebts = List<RecordModel>.from(
          snapshot['openDebts'] as List? ?? const [],
        );
        totalDebtIqd = (snapshot['totalDebtIqd'] as num?)?.toDouble() ?? 0;
        totalRemainingIqd =
            (snapshot['totalRemainingIqd'] as num?)?.toDouble() ?? 0;
        totalPaidIqd = (snapshot['totalPaidIqd'] as num?)?.toDouble() ?? 0;
        summaryComplete = snapshot['complete'] == true;
        timelineHasMore = page['hasMore'] == true;
        timelineCursor = page['nextCursor'] is Map
            ? Map<String, dynamic>.from(page['nextCursor'] as Map)
            : null;
      } else if (role == 'employee') {
        employeeStats = await PBService.getEmployeeStats(widget.userId);
      }

      if (!mounted) return;
      setState(() {
        _user = user;
        _debts = debts;
        _payments = payments;
        _financialEvents = financialEvents;
        _openDebts = openDebts;
        _financeTotalDebtIqd = totalDebtIqd;
        _financeTotalRemainingIqd = totalRemainingIqd;
        _financeTotalPaidIqd = totalPaidIqd;
        _financeSummaryComplete = summaryComplete;
        _financialTimelineHasMore = timelineHasMore;
        _financialTimelineCursor = timelineCursor;
        _financialHistoryError = null;
        _financialHistoryLoading = false;
        _financialFilterHydrating = false;
        _employeeStats = employeeStats;
        _nameController.text = user.getStringValue('name');
        _phoneController.text = user.getStringValue('phone');

        if (role == 'employee') {
          _canAddCustomers = user.getBoolValue('can_add_customers');
          _canSetDebtLimit = user.getBoolValue('can_set_debt_limit');
          _canSetDueDate = user.getBoolValue('can_set_due_date');
          _canEditDebts = user.getBoolValue('can_edit_debts');
          _canSendNotifications = user.getBoolValue('can_send_notifications');
        }

        _isLoading = false;
        _loadError = null;
      });
      if (role == 'customer' && _customerSection == 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _jumpToLatest(animated: false);
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _user = null;
        _debts = [];
        _payments = [];
        _financialEvents = [];
        _openDebts = [];
        _financeTotalDebtIqd = 0;
        _financeTotalRemainingIqd = 0;
        _financeTotalPaidIqd = 0;
        _financeSummaryComplete = false;
        _financialTimelineHasMore = false;
        _financialTimelineCursor = null;
        _financialHistoryError = null;
        _employeeStats = {};
        _isLoading = false;
        _loadError =
            'نەتوانرا زانیارییەکانی پروفایل باربکرێن. پەیوەندی ئینتەرنێت بپشکنە.';
      });
    } finally {
      _loadInFlight = false;
    }
  }

  Future<void> _subscribeFinancialRealtime'''
profile = profile[:old_load.start()] + new_load + profile[old_load.end():]

old_refresh = re.search(r'''  Future<void> _refreshFinancialData\(\{.*?\n  \}\n\n  void _jumpToLatest''', profile, re.S)
if not old_refresh:
    raise SystemExit('profile _refreshFinancialData block not found')
new_refresh = r'''  Future<void> _refreshFinancialData({
    bool autoJump = false,
    bool showError = false,
  }) async {
    if (!mounted) return;
    if (_financialRefreshInFlight) {
      _financialRefreshPending = true;
      _financialAutoJumpPending = _financialAutoJumpPending || autoJump;
      return;
    }

    _financialRefreshInFlight = true;
    try {
      final customerData = await Future.wait<Map<String, dynamic>>([
        PBService.getCustomerFinanceSnapshot(widget.userId),
        PBService.getCustomerFinancialTimelinePage(
          customerId: widget.userId,
          limit: 50,
        ),
      ]);
      final snapshot = customerData[0];
      final page = customerData[1];
      if (!mounted) return;
      setState(() {
        _debts = List<RecordModel>.from(page['debts'] as List? ?? const []);
        _payments = List<RecordModel>.from(page['payments'] as List? ?? const []);
        _financialEvents = List<RecordModel>.from(
          page['financialEvents'] as List? ?? const [],
        );
        _openDebts = List<RecordModel>.from(
          snapshot['openDebts'] as List? ?? const [],
        );
        _financeTotalDebtIqd =
            (snapshot['totalDebtIqd'] as num?)?.toDouble() ?? 0;
        _financeTotalRemainingIqd =
            (snapshot['totalRemainingIqd'] as num?)?.toDouble() ?? 0;
        _financeTotalPaidIqd =
            (snapshot['totalPaidIqd'] as num?)?.toDouble() ?? 0;
        _financeSummaryComplete = snapshot['complete'] == true;
        _financialTimelineHasMore = page['hasMore'] == true;
        _financialTimelineCursor = page['nextCursor'] is Map
            ? Map<String, dynamic>.from(page['nextCursor'] as Map)
            : null;
        _financialHistoryError = null;
      });
      if (_hasFinancialFilters && _financialTimelineHasMore) {
        unawaited(_hydrateFinancialHistoryForFilters());
      }
      if (autoJump && _customerSection == 1) {
        _jumpToLatest();
      }
    } catch (e) {
      if (showError && mounted) {
        AppHelpers.showSnackBar(
          context,
          AppHelpers.backendErrorMessage(
            e,
            fallback: 'نەتوانرا چاتی دارایی نوێ بکرێتەوە. دووبارە هەوڵ بدە.',
          ),
          isError: true,
        );
      }
    } finally {
      _financialRefreshInFlight = false;
      if (_financialRefreshPending && mounted) {
        final pendingAutoJump = _financialAutoJumpPending;
        _financialRefreshPending = false;
        _financialAutoJumpPending = false;
        Future<void>.delayed(const Duration(milliseconds: 80), () async {
          if (mounted) {
            await _refreshFinancialData(autoJump: pendingAutoJump);
          }
        });
      }
    }
  }

  List<RecordModel> _mergeFinancialRecords(
    List<RecordModel> current,
    List<RecordModel> incoming,
  ) {
    final byId = <String, RecordModel>{for (final item in current) item.id: item};
    for (final item in incoming) {
      byId[item.id] = item;
    }
    return byId.values.toList(growable: false);
  }

  Future<bool> _loadOlderFinancialHistory({
    bool preserveScroll = true,
    bool showError = true,
  }) async {
    if (!mounted || !_financialTimelineHasMore) return true;
    if (_financialHistoryLoading || _financialTimelineCursor == null) return false;

    final hadScroll = preserveScroll && _profileScrollController.hasClients;
    final oldPixels = hadScroll ? _profileScrollController.position.pixels : 0.0;
    final oldMax = hadScroll ? _profileScrollController.position.maxScrollExtent : 0.0;
    setState(() {
      _financialHistoryLoading = true;
      _financialHistoryError = null;
    });

    try {
      final page = await PBService.getCustomerFinancialTimelinePage(
        customerId: widget.userId,
        limit: 50,
        cursor: _financialTimelineCursor,
      );
      if (!mounted) return false;
      setState(() {
        _debts = _mergeFinancialRecords(
          _debts,
          List<RecordModel>.from(page['debts'] as List? ?? const []),
        );
        _payments = _mergeFinancialRecords(
          _payments,
          List<RecordModel>.from(page['payments'] as List? ?? const []),
        );
        _financialEvents = _mergeFinancialRecords(
          _financialEvents,
          List<RecordModel>.from(page['financialEvents'] as List? ?? const []),
        );
        _financialTimelineHasMore = page['hasMore'] == true;
        _financialTimelineCursor = page['nextCursor'] is Map
            ? Map<String, dynamic>.from(page['nextCursor'] as Map)
            : null;
        _financialHistoryError = null;
      });

      if (hadScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_profileScrollController.hasClients) return;
          final position = _profileScrollController.position;
          final delta = position.maxScrollExtent - oldMax;
          final target = (oldPixels + delta)
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble();
          _profileScrollController.jumpTo(target);
        });
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      final message = AppHelpers.backendErrorMessage(
        e,
        fallback: 'نەتوانرا مامەڵە کۆنەکان باربکرێن. دووبارە هەوڵ بدە.',
      );
      setState(() => _financialHistoryError = message);
      if (showError) {
        AppHelpers.showSnackBar(context, message, isError: true);
      }
      return false;
    } finally {
      if (mounted) setState(() => _financialHistoryLoading = false);
    }
  }

  Future<bool> _ensureAllFinancialHistoryLoaded({
    bool showError = true,
  }) async {
    var pages = 0;
    while (mounted && _financialTimelineHasMore) {
      if (pages++ > 10000) return false;
      final loaded = await _loadOlderFinancialHistory(
        preserveScroll: false,
        showError: showError,
      );
      if (!loaded) return false;
    }
    return mounted;
  }

  bool get _hasFinancialFilters =>
      _financialSearchController.text.trim().isNotEmpty ||
      _financialDateRange != null ||
      _financialTypeFilter != 'all';

  Future<void> _hydrateFinancialHistoryForFilters() async {
    if (!mounted || !_hasFinancialFilters || !_financialTimelineHasMore) return;
    if (_financialFilterHydrating) return;
    setState(() {
      _financialFilterHydrating = true;
      _financialHistoryError = null;
    });
    try {
      await _ensureAllFinancialHistoryLoaded(showError: false);
    } finally {
      if (mounted) setState(() => _financialFilterHydrating = false);
    }
  }

  void _jumpToLatest'''
profile = profile[:old_refresh.start()] + new_refresh + profile[old_refresh.end():]

# Summary card must come from the server aggregate, not a partial timeline page.
profile = replace_once(profile, '''  List<Widget> _buildCustomerBody() {\n    final summary = AppHelpers.debtSummaryInIqd(_debts);\n    final totalDebt = summary.totalDebt;\n    final totalRemaining = summary.totalRemaining;\n    final totalPaid = summary.totalPaid;\n    final totalsComplete = summary.complete;\n''', '''  List<Widget> _buildCustomerBody() {\n    final totalDebt = _financeTotalDebtIqd;\n    final totalRemaining = _financeTotalRemainingIqd;\n    final totalPaid = _financeTotalPaidIqd;\n    final totalsComplete = _financeSummaryComplete;\n''', 'customer body server summary')

profile = replace_once(profile, '''              onPressed: totalsComplete\n                  ? () => _generateAccountStatement(\n                        totalDebt: totalDebt,\n                        totalRemaining: totalRemaining,\n                        totalPaid: totalPaid,\n                      )\n                  : _showIncompleteCurrencySummaryMessage,\n''', '''              onPressed: totalsComplete\n                  ? _generateCurrentFinancialStatement\n                  : _showIncompleteCurrencySummaryMessage,\n''', 'overview statement action')

# Timeline payment relation may reference a debt outside the loaded page.
profile = replace_once(profile, '''          relatedDebt: debtsById[payment.getStringValue('debt')],\n''', '''          relatedDebt: debtsById[payment.getStringValue('debt')] ??\n              AppHelpers.expandedRecord(payment, 'debt'),\n''', 'payment relation fallback')

# Filter activation must hydrate all pages before showing supposedly-global results.
profile = replace_once(profile, '''    if (!mounted || picked == null) return;\n    setState(() => _financialDateRange = picked);\n''', '''    if (!mounted || picked == null) return;\n    setState(() => _financialDateRange = picked);\n    unawaited(_hydrateFinancialHistoryForFilters());\n''', 'date filter hydration')

profile = replace_once(profile, '''    final hasFilters = _financialSearchController.text.trim().isNotEmpty ||\n        _financialDateRange != null ||\n        _financialTypeFilter != 'all';\n''', '''    final hasFilters = _hasFinancialFilters;\n''', 'tools filter getter')

profile = replace_once(profile, '''          onSelected: (_) => setState(() => _financialTypeFilter = value),\n''', '''          onSelected: (_) {\n            setState(() => _financialTypeFilter = value);\n            unawaited(_hydrateFinancialHistoryForFilters());\n          },\n''', 'type filter hydration')

profile = replace_once(profile, '''          controller: _financialSearchController,\n          onChanged: (_) => setState(() {}),\n''', '''          controller: _financialSearchController,\n          onChanged: (_) {\n            setState(() {});\n            unawaited(_hydrateFinancialHistoryForFilters());\n          },\n''', 'search hydration')

# Add explicit loading/retry state for global filters.
empty_anchor = '''  Widget _buildCustomerChatTimelineCard({\n'''
loading_widget = r'''  Widget _buildFinancialHistoryLoadingState(bool isDark) {
    final error = _financialHistoryError;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE9EDF3),
        ),
      ),
      child: Column(
        children: [
          if (error == null)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.3),
            )
          else
            const Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 28),
          const SizedBox(height: 9),
          Text(
            error ?? 'بۆ گەڕان و فلتەری تەواو، مێژووی کۆنتر لە سێرڤەر بار دەکرێت...',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppDarkColors.textSecondary
                  : const Color(0xFF667085),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 7),
            TextButton.icon(
              onPressed: _financialFilterHydrating
                  ? null
                  : () => unawaited(_hydrateFinancialHistoryForFilters()),
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('دووبارە هەوڵ بدە'),
            ),
          ],
        ],
      ),
    );
  }

'''
profile = replace_once(profile, empty_anchor, loading_widget + empty_anchor, 'history loading widget')

# Timeline header + rows understand partial history and expose Load older.
profile = replace_once(profile, '''    final allTimelineItems = _buildTimelineItems();\n    final timelineItems = _filterFinancialTimeline(allTimelineItems);\n    final runningBalances = _financialRunningBalances(allTimelineItems);\n    final renderEntries = _buildFinancialChatRenderEntries(timelineItems);\n    final totalsComplete = AppHelpers.debtSummaryInIqd(_debts).complete;\n''', '''    final allTimelineItems = _buildTimelineItems();\n    final timelineItems = _filterFinancialTimeline(allTimelineItems);\n    final runningBalances = _financialRunningBalances(allTimelineItems);\n    final hasFilters = _hasFinancialFilters;\n    final waitingForFullFilterHistory = hasFilters &&\n        (_financialTimelineHasMore || _financialFilterHydrating);\n    final renderEntries = _buildFinancialChatRenderEntries(\n      waitingForFullFilterHistory\n          ? const <_ProfileTimelineItem>[]\n          : timelineItems,\n    );\n    final totalsComplete = _financeSummaryComplete;\n''', 'timeline pagination vars')

profile = replace_once(profile, '''                              '${timelineItems.length}/${allTimelineItems.length} مامەڵە • قەرز و پارەدانەوە لە یەک مێژوودا',\n''', '''                              _financialTimelineHasMore && !hasFilters\n                                  ? '${allTimelineItems.length}+ مامەڵەی نوێ بارکراوە • مێژووی کۆنتر هەیە'\n                                  : '${timelineItems.length}/${allTimelineItems.length} مامەڵە • قەرز و پارەدانەوە لە یەک مێژوودا',\n''', 'timeline count label')

profile = replace_once(profile, '''            const SizedBox(height: 12),\n            if (timelineItems.isEmpty)\n              allTimelineItems.isEmpty\n                  ? _buildEmptyTimelineState(isDark)\n                  : _buildFilteredTimelineEmptyState(isDark),\n''', '''            const SizedBox(height: 12),\n            if (!hasFilters && _financialTimelineHasMore) ...[\n              OutlinedButton.icon(\n                onPressed: _financialHistoryLoading\n                    ? null\n                    : () => _loadOlderFinancialHistory(),\n                icon: _financialHistoryLoading\n                    ? const SizedBox(\n                        width: 16,\n                        height: 16,\n                        child: CircularProgressIndicator(strokeWidth: 2),\n                      )\n                    : const Icon(Icons.history_rounded, size: 18),\n                label: Text(\n                  _financialHistoryLoading\n                      ? 'بارکردنی مامەڵە کۆنەکان...'\n                      : 'مامەڵە کۆنەکان باربکە',\n                ),\n              ),\n              const SizedBox(height: 10),\n            ],\n            if (waitingForFullFilterHistory)\n              _buildFinancialHistoryLoadingState(isDark)\n            else if (timelineItems.isEmpty)\n              allTimelineItems.isEmpty\n                  ? _buildEmptyTimelineState(isDark)\n                  : _buildFilteredTimelineEmptyState(isDark),\n''', 'load older/filter history header')

# Open debts drive payment UI, not the historical timeline page.
profile = replace_once(profile, '''    final hasOutstandingDebt =\n        _debts.any((debt) => debt.getDoubleValue('remaining') > 0);\n''', '''    final hasOutstandingDebt = _openDebts.isNotEmpty;\n''', 'composer open debt state')
profile = replace_once(profile, '''      debts: _debts,\n''', '''      debts: _openDebts,\n''', 'payment flow open debts')

# Export/search must hydrate all pages before applying local filters.
profile = replace_once(profile, '''  Future<void> _generateFilteredFinancialChatStatement() async {\n    final allItems = _buildTimelineItems();\n''', '''  Future<void> _generateFilteredFinancialChatStatement() async {\n    final hydrated = await _ensureAllFinancialHistoryLoaded(showError: true);\n    if (!hydrated || !mounted) return;\n    final allItems = _buildTimelineItems();\n''', 'filtered PDF hydrate history')

# Account statement intentionally fetches every debt only when requested.
old_current_statement = re.search(r'''  Future<void> _generateCurrentFinancialStatement\(\) async \{.*?\n  \}\n\n  Future<void> _generateAccountStatement\(\{.*?\n  \}\n''', profile, re.S)
if not old_current_statement:
    raise SystemExit('current/account statement block not found')
new_current_statement = r'''  Future<void> _generateCurrentFinancialStatement() async {
    if (!_financeSummaryComplete) {
      _showIncompleteCurrencySummaryMessage();
      return;
    }
    try {
      final fullDebts = await PBService.getAllCustomerDebtsLive(widget.userId);
      if (!mounted) return;
      await _generateAccountStatement(
        debts: fullDebts,
        totalDebt: _financeTotalDebtIqd,
        totalRemaining: _financeTotalRemainingIqd,
        totalPaid: _financeTotalPaidIqd,
      );
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'کەشف حیساب دروست نەکرا. دووبارە هەوڵ بدە.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _generateAccountStatement({
    required List<RecordModel> debts,
    required double totalDebt,
    required double totalRemaining,
    required double totalPaid,
  }) async {
    final auth = context.read<AuthProvider>();
    final customerName = _user?.getStringValue('name') ?? '';

    try {
      await PdfService.generateCustomerStatement(
        activeDebts: debts,
        customerName: customerName,
        marketName: auth.marketName,
        adminName: auth.userName,
        adminPhone: auth.user?.getStringValue('phone') ?? '',
        totalDebt: totalDebt,
        totalRemaining: totalRemaining,
        totalPaid: totalPaid,
      );
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(context, AppHelpers.backendErrorMessage(e), isError: true);
      }
    }
  }
'''
profile = profile[:old_current_statement.start()] + new_current_statement + profile[old_current_statement.end():]

# Debt limit uses authoritative snapshot summary.
profile = replace_once(profile, '''    final debtSummary = AppHelpers.debtSummaryInIqd(_debts);\n    final totalRemaining = debtSummary.totalRemaining;\n    final totalsComplete = debtSummary.complete;\n''', '''    final totalRemaining = _financeTotalRemainingIqd;\n    final totalsComplete = _financeSummaryComplete;\n''', 'debt limit snapshot')

profile_path.write_text(profile, encoding='utf-8')

# -----------------------------------------------------------------------------
# CI verifier: protect server pagination and forbid returning to 500-record load.
# -----------------------------------------------------------------------------
verify_path = ROOT / 'scripts/verify_online_only.py'
verify = verify_path.read_text(encoding='utf-8')
marker = '''# Financial Chat Phase 4 must remain live-only and keep its integrated search,\n'''
block = r'''# Financial Chat long-history performance must stay server-paginated. Initial
# customer load uses one aggregate/open-debt snapshot plus a deterministic
# 50-item composite-cursor timeline page; filters hydrate all pages explicitly.
for marker in (
    'getCustomerFinanceSnapshot',
    'getCustomerFinancialTimelinePage',
    "'get_customer_finance_snapshot'",
    "'get_customer_financial_timeline_page'",
    "'p_cursor_at'",
    "'p_cursor_kind'",
    "'p_cursor_id'",
    'getAllCustomerDebtsLive',
):
    if marker not in pb:
        fail(f'lib/services/pb_service.dart: Financial Chat pagination marker missing: {marker}')
for marker in (
    '_openDebts',
    '_financialTimelineHasMore',
    '_financialTimelineCursor',
    '_loadOlderFinancialHistory',
    '_ensureAllFinancialHistoryLoaded',
    '_hydrateFinancialHistoryForFilters',
    'مامەڵە کۆنەکان باربکە',
):
    if marker not in profile:
        fail(f'lib/screens/shared/user_profile_screen.dart: Financial Chat pagination marker missing: {marker}')
load_data_match = re.search(
    r'Future<void>\s+_loadData\(\)\s+async\s*\{(.*?)(?=\s*Future<void>\s+_subscribeFinancialRealtime)',
    profile,
    re.S,
)
if not load_data_match:
    fail('lib/screens/shared/user_profile_screen.dart: _loadData pagination implementation not found')
else:
    load_body = load_data_match.group(1)
    for forbidden in ('PBService.getDebts(', 'PBService.getPayments(', 'PBService.getFinancialEvents('):
        if forbidden in load_body:
            fail(f'lib/screens/shared/user_profile_screen.dart: initial customer load must not bulk-load history: {forbidden}')
    for required in ('PBService.getCustomerFinanceSnapshot', 'PBService.getCustomerFinancialTimelinePage', 'limit: 50'):
        if required not in load_body:
            fail(f'lib/screens/shared/user_profile_screen.dart: initial paginated load marker missing: {required}')

'''
verify = replace_once(verify, marker, block + marker, 'pagination verifier block')
verify_path.write_text(verify, encoding='utf-8')

print('Financial Chat server pagination patch applied.')
