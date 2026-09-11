from pathlib import Path

ROOT = Path.cwd()
ui_path = ROOT / 'lib/screens/shared/user_list_screen.dart'
pb_path = ROOT / 'lib/services/pb_service.dart'
verifier_path = ROOT / 'scripts/verify_online_only.py'

ui = ui_path.read_text(encoding='utf-8')
pb = pb_path.read_text(encoding='utf-8')
verifier = verifier_path.read_text(encoding='utf-8')


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    return source.replace(old, new, 1)

old_pb = '''  static Future<void> markFinancialChatRead(String customerId) async {\n    await ensureInitialized();\n    await client.rpc(\n      'mark_financial_chat_read',\n      params: {'p_customer_id': customerId},\n    );\n  }\n'''
new_pb = '''  static Future<void> markFinancialChatRead(\n    String customerId, {\n    DateTime? readThrough,\n  }) async {\n    await ensureInitialized();\n    await client.rpc(\n      'mark_financial_chat_read_through',\n      params: {\n        'p_customer_id': customerId,\n        'p_read_through': readThrough?.toUtc().toIso8601String(),\n      },\n    );\n  }\n'''
if "'mark_financial_chat_read_through'" not in pb:
    pb = replace_once(pb, old_pb, new_pb, 'PBService read-through RPC')

old_helper = '''  Future<void> _markFinancialChatReadBestEffort(String customerId) async {\n    try {\n      await PBService.markFinancialChatRead(customerId);\n    } catch (_) {\n      if (mounted) _scheduleCustomerInboxRefresh();\n    }\n  }\n'''
new_helper = '''  Future<void> _markFinancialChatReadBestEffort(\n    String customerId,\n    DateTime? readThrough,\n  ) async {\n    try {\n      await PBService.markFinancialChatRead(\n        customerId,\n        readThrough: readThrough,\n      );\n    } catch (_) {\n      if (mounted) _scheduleCustomerInboxRefresh();\n    }\n  }\n'''
if 'DateTime? readThrough' not in ui:
    ui = replace_once(ui, old_helper, new_helper, 'best-effort read-through helper')

old_open = '''    if (widget.role == 'customer') {\n      final row = _customerInbox[user.id];\n      if (row != null && row['unread'] == true) {\n        setState(() => row['unread'] = false);\n      }\n      unawaited(_markFinancialChatReadBestEffort(user.id));\n    }\n'''
new_open = '''    if (widget.role == 'customer') {\n      final row = _customerInbox[user.id];\n      final readThrough = DateTime.tryParse(\n        row?['last_activity_at']?.toString() ?? '',\n      );\n      if (row != null && row['unread'] == true) {\n        setState(() => row['unread'] = false);\n      }\n      unawaited(_markFinancialChatReadBestEffort(user.id, readThrough));\n    }\n'''
if '_markFinancialChatReadBestEffort(user.id, readThrough)' not in ui:
    ui = replace_once(ui, old_open, new_open, 'profile-open read-through timestamp')

old_quick = '                        unawaited(PBService.markFinancialChatRead(user.id));\n'
new_quick = '''                        unawaited(\n                          _markFinancialChatReadBestEffort(\n                            user.id,\n                            DateTime.tryParse(\n                              inbox?['last_activity_at']?.toString() ?? '',\n                            ),\n                          ),\n                        );\n'''
if old_quick in ui:
    ui = replace_once(ui, old_quick, new_quick, 'quick-payment read-through timestamp')

anchor = '''if violations:\n    print('ONLINE-ONLY POLICY FAILED')\n'''
guard = '''# Customer Inbox read receipts must be bounded by the last activity actually\n# observed by the viewer. Marking through server now() can swallow a new event\n# that arrives between tapping a chat and the read-receipt RPC completing.\nread_receipt_migration = ROOT / 'supabase/migrations/20260911094437_mark_financial_chat_read_through_timestamp.sql'\nif not read_receipt_migration.exists():\n    fail(f'{read_receipt_migration.relative_to(ROOT)}: race-safe read-receipt migration must be tracked')\nelse:\n    read_receipt_source = read_receipt_migration.read_text(encoding='utf-8')\n    for marker in (\n        'mark_financial_chat_read_through',\n        'greatest(',\n        'least(coalesce(p_read_through, now()), now())',\n        'revoke all on function public.mark_financial_chat_read_through(uuid, timestamptz) from public, anon;',\n    ):\n        if marker not in read_receipt_source:\n            fail(f'{read_receipt_migration.relative_to(ROOT)}: read-receipt marker missing: {marker}')\nfor marker in (\n    "'mark_financial_chat_read_through'",\n    'DateTime? readThrough',\n    "'p_read_through'",\n):\n    if marker not in pb:\n        fail(f'lib/services/pb_service.dart: race-safe read-receipt marker missing: {marker}')\nfor marker in (\n    '_markFinancialChatReadBestEffort(user.id, readThrough)',\n    "inbox?['last_activity_at']",\n):\n    if marker not in customer_list_source:\n        fail(f'lib/screens/shared/user_list_screen.dart: bounded read-receipt marker missing: {marker}')\nif 'PBService.markFinancialChatRead(user.id)' in customer_list_source:\n    fail('lib/screens/shared/user_list_screen.dart: unbounded read receipt must not return')\n\n\n'''
if 'race-safe read-receipt migration must be tracked' not in verifier:
    verifier = replace_once(verifier, anchor, guard + anchor, 'read-receipt verifier guard')

ui_path.write_text(ui, encoding='utf-8')
pb_path.write_text(pb, encoding='utf-8')
verifier_path.write_text(verifier, encoding='utf-8')
print('Financial Chat read-receipt race fix applied.')
