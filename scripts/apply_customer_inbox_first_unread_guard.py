from pathlib import Path

ROOT = Path.cwd()
path = ROOT / 'scripts/verify_online_only.py'
text = path.read_text(encoding='utf-8')

anchor = "if 'DebtProvider' in customer_list_source:\n    fail('Customer list must not own debt/payment mutation logic')\n"
guard = '''# First-unread semantics must avoid both extremes: historical activity from\n# before Inbox launch must not flood users as unread, while the first new\n# activity after the viewer's effective baseline must not be silently hidden.\ninbox_first_unread = ROOT / 'supabase/migrations/20260911100158_baseline_customer_inbox_first_unread.sql'\nif not inbox_first_unread.exists():\n    fail(f'{inbox_first_unread.relative_to(ROOT)}: Customer Inbox first-unread migration must be tracked')\nelse:\n    first_unread_source = inbox_first_unread.read_text(encoding='utf-8')\n    for marker in (\n        'with viewer_baseline as (',\n        "'2026-09-11 09:08:54+00'::timestamptz",\n        'when rd.last_read_at is not null then l.event_at > rd.last_read_at',\n        'else l.event_at > vb.baseline_at',\n        'cross join viewer_baseline vb',\n    ):\n        if marker not in first_unread_source:\n            fail(f'{inbox_first_unread.relative_to(ROOT)}: first-unread marker missing: {marker}')\n    if 'when rd.last_read_at is null then false' in first_unread_source:\n        fail(f'{inbox_first_unread.relative_to(ROOT)}: first activity after baseline must not be forced read')\n\n'''

if 'Customer Inbox first-unread migration must be tracked' not in text:
    count = text.count(anchor)
    if count != 1:
        raise SystemExit(f'first-unread verifier anchor expected once, found {count}')
    text = text.replace(anchor, guard + anchor, 1)

path.write_text(text, encoding='utf-8')
print('Customer Inbox first-unread verifier guard applied.')
