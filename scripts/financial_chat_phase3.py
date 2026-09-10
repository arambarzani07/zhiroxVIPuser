from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise SystemExit(f'{label} marker not found')


# ---------- PBService: live audit event reader ----------
pb_path = Path('lib/services/pb_service.dart')
pb = pb_path.read_text()
if 'getFinancialEvents(' not in pb:
    marker = '  // ==================== Stats ====================\n'
    addition = r'''  static RecordModel _financialEventRecord(Map<String, dynamic> row) {
    final created = row['created_at']?.toString() ?? '';
    return RecordModel.fromJson({
      ...row,
      'id': row['id']?.toString() ?? '',
      'collectionId': '',
      'collectionName': 'financial_events',
      'created': created,
      'updated': created,
    });
  }

  static Future<List<RecordModel>> getFinancialEvents(String customerId) async {
    await ensureInitialized();
    final data = await client
        .from('financial_events')
        .select()
        .eq('customer_id', customerId)
        .order('created_at', ascending: true)
        .limit(500);
    return (data as List)
        .map((row) => _financialEventRecord(
              Map<String, dynamic>.from(row as Map),
            ))
        .toList();
  }

'''
    if marker not in pb:
        raise SystemExit('PBService stats marker not found')
    pb = pb.replace(marker, addition + marker, 1)
    pb_path.write_text(pb)


# ---------- User profile: realtime Financial Chat ----------
path = Path('lib/screens/shared/user_profile_screen.dart')
text = path.read_text()

if "package:supabase_flutter/supabase_flutter.dart" not in text:
    text = replace_once(
        text,
        "import 'package:pocketbase/pocketbase.dart';\n",
        "import 'package:pocketbase/pocketbase.dart';\nimport 'package:supabase_flutter/supabase_flutter.dart';\n",
        'supabase import',
    )

text = replace_once(
    text,
    "  bool get isPayment => kind == 'payment';\n",
    "  bool get isPayment => kind == 'payment';\n  bool get isSystem => kind == 'system';\n",
    'timeline system getter',
)

text = replace_once(
    text,
    "  List<RecordModel> _payments = [];\n",
    "  List<RecordModel> _payments = [];\n  List<RecordModel> _financialEvents = [];\n",
    'financial events state',
)

text = replace_once(
    text,
    "  bool _loadInFlight = false;\n",
    "  bool _loadInFlight = false;\n  bool _financialRefreshInFlight = false;\n  bool _financialRefreshPending = false;\n  bool _financialAutoJumpPending = false;\n",
    'financial refresh flags',
)

text = replace_once(
    text,
    "  String? _loadError;\n",
    "  String? _loadError;\n  bool _hasNewFinancialActivity = false;\n",
    'new activity flag',
)

text = replace_once(
    text,
    "  StreamSubscription<bool>? _connectivitySub;\n",
    "  StreamSubscription<bool>? _connectivitySub;\n  final ScrollController _profileScrollController = ScrollController();\n  RealtimeChannel? _financialRealtimeChannel;\n  Timer? _financialRealtimeDebounce;\n",
    'realtime fields',
)

text = replace_once(
    text,
    "    _loadData();\n    _connectivitySub = ConnectivityService.instance.statusStream.listen((online) {\n",
    "    _loadData();\n    WidgetsBinding.instance.addPostFrameCallback((_) {\n      if (mounted) unawaited(_subscribeFinancialRealtime());\n    });\n    _connectivitySub = ConnectivityService.instance.statusStream.listen((online) {\n",
    'init realtime subscription',
)

text = replace_once(
    text,
    "  void dispose() {\n    _connectivitySub?.cancel();\n",
    "  void dispose() {\n    _financialRealtimeDebounce?.cancel();\n    final financialChannel = _financialRealtimeChannel;\n    if (financialChannel != null) {\n      unawaited(PBService.client.removeChannel(financialChannel));\n    }\n    _profileScrollController.dispose();\n    _connectivitySub?.cancel();\n",
    'dispose realtime resources',
)

text = replace_once(
    text,
    "      List<RecordModel> payments = [];\n      Map<String, double> employeeStats = {};\n",
    "      List<RecordModel> payments = [];\n      List<RecordModel> financialEvents = [];\n      Map<String, double> employeeStats = {};\n",
    'load financial event local',
)

text = replace_once(
    text,
    "          PBService.getPayments(customerId: widget.userId),\n        ]);\n        debts = customerData[0];\n        payments = customerData[1];\n",
    "          PBService.getPayments(customerId: widget.userId),\n          PBService.getFinancialEvents(widget.userId),\n        ]);\n        debts = customerData[0];\n        payments = customerData[1];\n        financialEvents = customerData[2];\n",
    'initial financial event load',
)

text = replace_once(
    text,
    "        _payments = payments;\n        _employeeStats = employeeStats;\n",
    "        _payments = payments;\n        _financialEvents = financialEvents;\n        _employeeStats = employeeStats;\n",
    'assign financial events',
)

text = replace_once(
    text,
    "        _payments = [];\n        _employeeStats = {};\n",
    "        _payments = [];\n        _financialEvents = [];\n        _employeeStats = {};\n",
    'clear financial events',
)

if 'Future<void> _subscribeFinancialRealtime() async' not in text:
    anchor = '  Future<void> _toggleActive() async {\n'
    methods = r'''  Future<void> _subscribeFinancialRealtime() async {
    try {
      await PBService.ensureInitialized();
      if (!mounted) return;

      final previous = _financialRealtimeChannel;
      if (previous != null) {
        try {
          await PBService.client.removeChannel(previous);
        } catch (_) {}
      }

      final channel = PBService.client
          .channel(
            'financial-chat:${widget.userId}:${DateTime.now().microsecondsSinceEpoch}',
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'financial_events',
            callback: (payload) {
              final raw = payload.newRecord.isNotEmpty
                  ? payload.newRecord
                  : payload.oldRecord;
              if (raw['customer_id']?.toString() != widget.userId) return;
              _handleFinancialRealtimeEvent();
            },
          )
          .subscribe();

      if (!mounted) {
        try {
          await PBService.client.removeChannel(channel);
        } catch (_) {}
        return;
      }
      _financialRealtimeChannel = channel;
    } catch (_) {
      // Reconnect and explicit manual refresh remain available if realtime
      // cannot be established. Never make live data look successfully cached.
    }
  }

  bool get _isNearFinancialEnd {
    if (!_profileScrollController.hasClients) return false;
    final position = _profileScrollController.position;
    return position.maxScrollExtent - position.pixels < 150;
  }

  void _handleFinancialRealtimeEvent() {
    if (!mounted) return;
    final autoJump = _customerSection == 1 && _isNearFinancialEnd;
    if (!autoJump && !_hasNewFinancialActivity) {
      setState(() => _hasNewFinancialActivity = true);
    }

    _financialRealtimeDebounce?.cancel();
    _financialRealtimeDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      unawaited(_refreshFinancialData(autoJump: autoJump));
    });
  }

  Future<void> _refreshFinancialData({
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
      final customerData = await Future.wait<List<RecordModel>>([
        PBService.getDebts(customerId: widget.userId),
        PBService.getPayments(customerId: widget.userId),
        PBService.getFinancialEvents(widget.userId),
      ]);
      if (!mounted) return;
      setState(() {
        _debts = customerData[0];
        _payments = customerData[1];
        _financialEvents = customerData[2];
      });
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

  void _jumpToLatest({bool animated = true}) {
    if (!mounted) return;
    if (_hasNewFinancialActivity) {
      setState(() => _hasNewFinancialActivity = false);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_profileScrollController.hasClients) return;
      final target = _profileScrollController.position.maxScrollExtent;
      if (animated) {
        unawaited(
          _profileScrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          ),
        );
      } else {
        _profileScrollController.jumpTo(target);
      }
    });
  }

'''
    if anchor not in text:
        raise SystemExit('toggle active anchor not found')
    text = text.replace(anchor, methods + anchor, 1)

text = replace_once(
    text,
    "      body: CustomScrollView(\n        slivers: [\n",
    "      body: CustomScrollView(\n        controller: _profileScrollController,\n        slivers: [\n",
    'profile scroll controller',
)

if 'floatingActionButton: _isCustomer &&' not in text:
    marker = "      bottomNavigationBar: _isCustomer &&\n"
    fab = r'''      floatingActionButton: _isCustomer &&
              _customerSection == 1 &&
              _hasNewFinancialActivity
          ? FloatingActionButton.extended(
              onPressed: _jumpToLatest,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              label: const Text('مامەڵەی نوێ'),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
'''
    if marker not in text:
        raise SystemExit('bottom navigation anchor not found')
    text = text.replace(marker, fab + marker, 1)

text = replace_once(
    text,
    "                      setState(() => _customerSection = index);\n",
    "                      setState(() => _customerSection = index);\n                      if (index == 1) {\n                        WidgetsBinding.instance.addPostFrameCallback((_) {\n                          if (mounted) _jumpToLatest(animated: false);\n                        });\n                      }\n",
    'chat tab jump',
)

text = replace_once(
    text,
    "                        onPressed: _loadInFlight ? null : _loadData,\n",
    "                        onPressed: _financialRefreshInFlight\n                            ? null\n                            : () => _refreshFinancialData(showError: true),\n",
    'chat refresh action',
)

old_items = r'''      for (final payment in _payments)
        _ProfileTimelineItem(
          kind: 'payment',
          record: payment,
          relatedDebt: debtsById[payment.getStringValue('debt')],
          date: _timelineDate(payment),
        ),
    ];
'''
new_items = r'''      for (final payment in _payments)
        _ProfileTimelineItem(
          kind: 'payment',
          record: payment,
          relatedDebt: debtsById[payment.getStringValue('debt')],
          date: _timelineDate(payment),
        ),
      for (final event in _financialEvents)
        if (const <String>{
          'debt_updated',
          'debt_deleted',
          'payment_updated',
          'payment_deleted',
        }.contains(event.getStringValue('event_type')))
          _ProfileTimelineItem(
            kind: 'system',
            record: event,
            date: _timelineDate(event),
          ),
    ];
'''
text = replace_once(text, old_items, new_items, 'audit events in timeline')

text = replace_once(
    text,
    "      widgets.add(_buildTimelineBubble(item, index));\n",
    "      widgets.add(\n        item.isSystem\n            ? _buildFinancialSystemMessage(item)\n            : _buildTimelineBubble(item, index),\n      );\n",
    'system message renderer',
)

if 'Widget _buildFinancialSystemMessage(' not in text:
    anchor = '  Widget _buildFinancialChatComposer(AuthProvider auth, bool isDark) {\n'
    method = r'''  Widget _buildFinancialSystemMessage(_ProfileTimelineItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final record = item.record;
    final type = record.getStringValue('event_type');
    final actor = record.getStringValue('actor_name').trim();
    final amount = record.getDoubleValue('amount');
    final currency = record.getStringValue('currency').isEmpty
        ? 'IQD'
        : record.getStringValue('currency');
    final amountText = amount > 0
        ? AppHelpers.formatCurrencyWithType(amount, currency)
        : '';

    final (icon, message) = switch (type) {
      'debt_deleted' => (
          Icons.delete_outline_rounded,
          amountText.isEmpty ? 'قەرزێک سڕایەوە' : 'قەرزی $amountText سڕایەوە',
        ),
      'payment_updated' => (
          Icons.edit_note_rounded,
          'پارەدانەوە دەستکاری کرا',
        ),
      'payment_deleted' => (
          Icons.remove_circle_outline_rounded,
          amountText.isEmpty
              ? 'پارەدانەوەیەک سڕایەوە'
              : 'پارەدانەوەی $amountText سڕایەوە',
        ),
      _ => (Icons.edit_outlined, 'قەرز دەستکاری کرا'),
    };

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 18),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.055)
              : const Color(0xFFF2F4F7),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isDark
                  ? AppDarkColors.textSecondary
                  : const Color(0xFF667085),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                actor.isEmpty ? message : '$message • $actor',
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppDarkColors.textSecondary
                      : const Color(0xFF667085),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              DateFormat('HH:mm').format(item.date),
              style: TextStyle(
                fontSize: 9.5,
                color: isDark
                    ? AppDarkColors.textSecondary
                    : const Color(0xFF98A2B3),
              ),
            ),
          ],
        ),
      ),
    );
  }

'''
    if anchor not in text:
        raise SystemExit('financial composer anchor not found')
    text = text.replace(anchor, method + anchor, 1)

text = replace_once(
    text,
    "    if (result == true && mounted) {\n      await _loadData();\n    }\n",
    "    if (result == true && mounted) {\n      await _refreshFinancialData(autoJump: true);\n    }\n",
    'add debt refresh',
)

text = replace_once(
    text,
    "    if (mounted) await _loadData();\n  }\n\n  Future<void> _showFinancialPaymentSheet",
    "    if (mounted) await _refreshFinancialData();\n  }\n\n  Future<void> _showFinancialPaymentSheet",
    'timeline drilldown refresh',
)

text = replace_once(
    text,
    "                                  await _loadData();\n                                } catch (e) {\n",
    "                                  await _refreshFinancialData(autoJump: true);\n                                } catch (e) {\n",
    'payment success refresh',
)

path.write_text(text)

# ---------- Permanent source guard ----------
verify_path = Path('scripts/verify_online_only.py')
verify = verify_path.read_text()
if 'Financial Chat realtime/audit markers' not in verify:
    insert_before = "\n\nif violations:\n"
    guard = r'''

# Financial Chat realtime/audit markers: business history remains server-backed
# and new activity must arrive through Supabase realtime, never a local cache.
profile = (LIB / 'screens/shared/user_profile_screen.dart').read_text(encoding='utf-8')
for marker in (
    'PBService.getFinancialEvents',
    "table: 'financial_events'",
    '_hasNewFinancialActivity',
    '_jumpToLatest',
    '_buildFinancialSystemMessage',
):
    if marker not in profile:
        fail(f'lib/screens/shared/user_profile_screen.dart: Financial Chat marker missing: {marker}')
if 'getFinancialEvents(String customerId)' not in pb:
    fail('lib/services/pb_service.dart: Financial Chat audit reader missing')
'''
    if insert_before not in verify:
        raise SystemExit('verifier final marker not found')
    verify = verify.replace(insert_before, guard + insert_before, 1)
    verify_path.write_text(verify)
