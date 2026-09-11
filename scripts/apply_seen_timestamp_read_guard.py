from pathlib import Path

ROOT = Path.cwd()
pb_path = ROOT / 'lib/services/pb_service.dart'
ui_path = ROOT / 'lib/screens/shared/user_list_screen.dart'
verifier_path = ROOT / 'scripts/verify_online_only.py'

pb = pb_path.read_text(encoding='utf-8')
ui = ui_path.read_text(encoding='utf-8')
verifier = verifier_path.read_text(encoding='utf-8')


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    return source.replace(old, new, 1)

if 'required DateTime readThrough' not in pb:
    pb = replace_once(
        pb,
        '''  static Future<void> markFinancialChatRead(\n    String customerId, {\n    DateTime? readThrough,\n  }) async {\n''',
        '''  static Future<void> markFinancialChatRead(\n    String customerId, {\n    required DateTime readThrough,\n  }) async {\n''',
        'required seen timestamp',
    )
    pb = replace_once(
        pb,
        "        'p_read_through': readThrough?.toUtc().toIso8601String(),\n",
        "        'p_read_through': readThrough.toUtc().toIso8601String(),\n",
        'non-null read-through serialization',
    )

helper_marker = '''  Future<void> _markFinancialChatReadBestEffort(\n    String customerId,\n    DateTime? readThrough,\n  ) async {\n'''
if '    if (readThrough == null) return;\n    try {\n      await PBService.markFinancialChatRead(' not in ui:
    ui = replace_once(
        ui,
        helper_marker + '    try {\n',
        helper_marker + '    if (readThrough == null) return;\n    try {\n',
        'skip unobserved read receipt',
    )

anchor = '''if violations:\n    print('ONLINE-ONLY POLICY FAILED')\n'''
guard = '''# A read receipt must never advance without a concrete activity timestamp that\n# the viewer actually observed. Null timestamps are fail-closed in both app and DB.\nseen_read_migration = ROOT / 'supabase/migrations/20260911095127_require_seen_timestamp_for_financial_chat_read.sql'\nif not seen_read_migration.exists():\n    fail(f'{seen_read_migration.relative_to(ROOT)}: seen-timestamp read migration must be tracked')\nelse:\n    seen_read_source = seen_read_migration.read_text(encoding='utf-8')\n    for marker in (\n        'where p_read_through is not null',\n        'least(p_read_through, now())',\n        'greatest(',\n    ):\n        if marker not in seen_read_source:\n            fail(f'{seen_read_migration.relative_to(ROOT)}: fail-closed read marker missing: {marker}')\nfor marker in ('required DateTime readThrough', 'readThrough.toUtc().toIso8601String()'):\n    if marker not in pb:\n        fail(f'lib/services/pb_service.dart: required read-through marker missing: {marker}')\nif 'if (readThrough == null) return;' not in customer_list_source:\n    fail('lib/screens/shared/user_list_screen.dart: missing null read-through fail-closed guard')\n\n\n'''
if 'seen-timestamp read migration must be tracked' not in verifier:
    verifier = replace_once(verifier, anchor, guard + anchor, 'seen timestamp verifier')

pb_path.write_text(pb, encoding='utf-8')
ui_path.write_text(ui, encoding='utf-8')
verifier_path.write_text(verifier, encoding='utf-8')
print('Seen-timestamp financial read guard applied.')
