from pathlib import Path
import re

ROOT = Path.cwd()
ui_path = ROOT / 'lib/screens/shared/user_list_screen.dart'
verifier_path = ROOT / 'scripts/verify_online_only.py'
text = ui_path.read_text(encoding='utf-8')
verifier = verifier_path.read_text(encoding='utf-8')


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    return source.replace(old, new, 1)


if 'Timer? _customerSearchDebounce;' not in text:
    text = replace_once(
        text,
        '  Timer? _inboxRealtimeDebounce;\n',
        '  Timer? _inboxRealtimeDebounce;\n'
        '  Timer? _customerSearchDebounce;\n'
        '  bool _inboxRefreshInFlight = false;\n'
        '  bool _inboxRefreshPending = false;\n',
        'state fields',
    )

if '    _customerSearchDebounce?.cancel();\n' not in text:
    text = replace_once(
        text,
        '  void dispose() {\n    _inboxRealtimeDebounce?.cancel();\n',
        '  void dispose() {\n    _inboxRealtimeDebounce?.cancel();\n    _customerSearchDebounce?.cancel();\n',
        'dispose debounce',
    )

loader_pattern = re.compile(
    r"  Future<void> _loadCustomerInboxInBackground\(.*?(?=\n  Future<void> _subscribeCustomerInboxRealtime\(\) async \{)",
    re.S,
)
loader = loader_pattern.search(text)
if not loader:
    raise SystemExit('Customer Inbox loader not found')
if 'if (_inboxRefreshInFlight)' not in loader.group(0):
    new_loader = '''  Future<void> _loadCustomerInboxInBackground(\n    List<RecordModel> users, {\n    int? generation,\n  }) async {\n    if (_inboxRefreshInFlight) {\n      _inboxRefreshPending = true;\n      return;\n    }\n\n    final ids = users.map((user) => user.id).where((id) => id.isNotEmpty).toList();\n    if (ids.isEmpty) return;\n    _inboxRefreshInFlight = true;\n    try {\n      final rows = await PBService.getCustomerInboxRows(ids);\n      if (!mounted || (generation != null && generation != _loadGeneration)) return;\n      final sorted = List<RecordModel>.from(_users);\n      DateTime? activityFor(String id) =>\n          DateTime.tryParse(rows[id]?['last_activity_at']?.toString() ?? '');\n      sorted.sort((a, b) {\n        final aAt = activityFor(a.id);\n        final bAt = activityFor(b.id);\n        if (aAt == null && bAt == null) {\n          return a.getStringValue('name').compareTo(b.getStringValue('name'));\n        }\n        if (aAt == null) return 1;\n        if (bAt == null) return -1;\n        return bAt.compareTo(aAt);\n      });\n      setState(() {\n        _customerInbox\n          ..clear()\n          ..addAll(rows);\n        _balances.clear();\n        _balanceErrors.clear();\n        for (final user in _users) {\n          final row = rows[user.id];\n          if (row == null) {\n            _balanceErrors.add(user.id);\n            continue;\n          }\n          _balances[user.id] = (row['remaining'] as num?)?.toDouble() ??\n              double.tryParse('${row['remaining'] ?? ''}') ??\n              0;\n        }\n        _users = sorted;\n        _inboxError = null;\n      });\n    } catch (_) {\n      if (!mounted || (generation != null && generation != _loadGeneration)) return;\n      setState(() {\n        _customerInbox.clear();\n        _balances.clear();\n        _balanceErrors\n          ..clear()\n          ..addAll(ids);\n        _inboxError = 'نەتوانرا پوختەی چاتی کڕیاران باربکرێت';\n        debugPrint(_inboxError);\n      });\n    } finally {\n      _inboxRefreshInFlight = false;\n      if (_inboxRefreshPending && mounted) {\n        _inboxRefreshPending = false;\n        final currentUsers = List<RecordModel>.from(_users);\n        if (currentUsers.isNotEmpty) {\n          unawaited(\n            _loadCustomerInboxInBackground(\n              currentUsers,\n              generation: _loadGeneration,\n            ),\n          );\n        }\n      }\n    }\n  }\n'''
    text = text[:loader.start()] + new_loader + text[loader.end():]

schedule_method = '''  void _scheduleCustomerSearch(String value) {\n    _customerSearchDebounce?.cancel();\n    final query = value.trim();\n    if (mounted) setState(() {});\n    _customerSearchDebounce = Timer(const Duration(milliseconds: 300), () {\n      if (!mounted) return;\n      unawaited(_loadUsers(search: query));\n    });\n  }\n\n'''
if schedule_method not in text:
    text = replace_once(
        text,
        '  Future<void> _subscribeCustomerInboxRealtime() async {\n',
        schedule_method + '  Future<void> _subscribeCustomerInboxRealtime() async {\n',
        'search scheduler',
    )

if 'onChanged: _scheduleCustomerSearch,' not in text:
    text = replace_once(
        text,
        '                          onChanged: (value) => _loadUsers(search: value),\n',
        '                          onChanged: _scheduleCustomerSearch,\n',
        'search onChanged',
    )

new_clear = '''                                    onPressed: () {\n                                      _customerSearchDebounce?.cancel();\n                                      _searchController.clear();\n                                      _loadUsers();\n                                    },\n'''
if new_clear not in text:
    text = replace_once(
        text,
        '''                                    onPressed: () {\n                                      _searchController.clear();\n                                      _loadUsers();\n                                    },\n''',
        new_clear,
        'clear search',
    )

mark_helper = '''  Future<void> _markFinancialChatReadBestEffort(String customerId) async {\n    try {\n      await PBService.markFinancialChatRead(customerId);\n    } catch (_) {\n      if (mounted) _scheduleCustomerInboxRefresh();\n    }\n  }\n\n'''
if mark_helper not in text:
    text = replace_once(
        text,
        '  Future<void> _openUserProfile(RecordModel user) async {\n',
        mark_helper + '  Future<void> _openUserProfile(RecordModel user) async {\n',
        'mark read helper',
    )

open_pattern = re.compile(
    r"  Future<void> _openUserProfile\(RecordModel user\) async \{.*?(?=\n  @override\n  Widget build)",
    re.S,
)
open_match = open_pattern.search(text)
if not open_match:
    raise SystemExit('openUserProfile method not found')
open_block = open_match.group(0)
if 'unawaited(_markFinancialChatReadBestEffort(user.id));' not in open_block:
    old_call = '      unawaited(PBService.markFinancialChatRead(user.id));\n'
    if open_block.count(old_call) != 1:
        raise SystemExit(f'openUserProfile mark-read call count: {open_block.count(old_call)}')
    open_block = open_block.replace(
        old_call,
        '      unawaited(_markFinancialChatReadBestEffort(user.id));\n',
        1,
    )
    text = text[:open_match.start()] + open_block + text[open_match.end():]

anchor = "if '_showPaymentDialog(RecordModel user)' in customer_list_source:\n    fail('Customer list must not duplicate payment recording outside Financial Chat')\n"
guard = '''\n# Customer Inbox must batch summaries and avoid request storms from text search\n# or realtime financial-event bursts.\nfor marker in (\n    'PBService.getCustomerInboxRows(ids)',\n    'Timer? _customerSearchDebounce;',\n    '_scheduleCustomerSearch',\n    'Duration(milliseconds: 300)',\n    '_inboxRefreshInFlight',\n    '_inboxRefreshPending',\n    '_markFinancialChatReadBestEffort',\n):\n    if marker not in customer_list_source:\n        fail(f'lib/screens/shared/user_list_screen.dart: Customer Inbox performance marker missing: {marker}')\nif 'onChanged: (value) => _loadUsers(search: value)' in customer_list_source:\n    fail('lib/screens/shared/user_list_screen.dart: customer search must not query on every keypress')\nfor marker in ('getCustomerInboxRows(', 'markFinancialChatRead('):\n    if marker not in pb:\n        fail(f'lib/services/pb_service.dart: Customer Inbox RPC marker missing: {marker}')\n\ninbox_schema = ROOT / 'supabase/migrations/20260911090854_add_financial_chat_inbox.sql'\ninbox_grants = ROOT / 'supabase/migrations/20260911093112_harden_financial_chat_inbox_grants.sql'\nfor migration_path in (inbox_schema, inbox_grants):\n    if not migration_path.exists():\n        fail(f'{migration_path.relative_to(ROOT)}: Customer Inbox migration must be tracked')\nif inbox_grants.exists():\n    grants_source = inbox_grants.read_text(encoding='utf-8')\n    for marker in (\n        'revoke all on table public.financial_chat_reads from anon;',\n        'grant select, insert, update on table public.financial_chat_reads to authenticated;',\n        'revoke execute on function public.get_customer_inbox_rows(uuid[]) from public, anon;',\n        'revoke execute on function public.mark_financial_chat_read(uuid) from public, anon;',\n    ):\n        if marker not in grants_source:\n            fail(f'{inbox_grants.relative_to(ROOT)}: least-privilege marker missing: {marker}')\n'''
if guard not in verifier:
    verifier = replace_once(verifier, anchor, anchor + guard, 'verifier guard')

ui_path.write_text(text, encoding='utf-8')
verifier_path.write_text(verifier, encoding='utf-8')
print('Customer Inbox performance hardening v2 applied.')
