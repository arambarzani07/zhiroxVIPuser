#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

required = [
    ROOT / 'supabase/functions/customer-push/index.ts',
    ROOT / 'supabase/functions/customer-push-admin/index.ts',
    ROOT / 'supabase/functions/customer-push-worker/index.ts',
    ROOT / 'supabase/functions/customer-push-events/index.ts',
    ROOT / 'lib/services/customer_push_service.dart',
    ROOT / 'lib/widgets/customer_push_card.dart',
]
for path in required:
    assert path.exists(), f'missing {path.relative_to(ROOT)}'

config = (ROOT / 'supabase/config.toml').read_text()
for section in ('customer-push', 'customer-push-worker'):
    pattern = rf'\[functions\.{re.escape(section)}\]\s*\n\s*verify_jwt\s*=\s*false\b'
    assert re.search(pattern, config), f'{section} must explicitly use verify_jwt = false'

flutter_text = '\n'.join(
    path.read_text(errors='ignore') for path in (ROOT / 'lib').rglob('*.dart')
)
for name in (
    'VAPID_PRIVATE_KEY',
    'CUSTOMER_PUSH_WORKER_SECRET',
    'CUSTOMER_PUSH_RATE_LIMIT_SALT',
):
    assert name not in flutter_text, f'server secret leaked to Flutter: {name}'

events_text = (
    ROOT / 'supabase/functions/customer-push-events/index.ts'
).read_text(errors='ignore')
for guard in ('legacy_import_links', 'daftar_sync_seen'):
    assert guard in events_text, f'missing debt import/sync exclusion guard: {guard}'

payment_text = (
    ROOT / 'supabase/functions/record-payment/index.ts'
).read_text(errors='ignore')
assert 'payment_created' in payment_text, 'record-payment does not enqueue payment_created'
assert (
    'enqueue_customer_push_event_service' in payment_text
), 'record-payment does not use customer push outbox RPC'

push_migration = ROOT / 'supabase/migrations/20260917013000_customer_qr_web_push.sql'
assert push_migration.exists(), 'customer push migration missing'
push_schema = push_migration.read_text(errors='ignore')

outbox_match = re.search(
    r'create\s+table\s+public\.notification_outbox\s*\((.*?)\);',
    push_schema,
    re.IGNORECASE | re.DOTALL,
)
assert outbox_match is not None, 'notification_outbox schema missing'
outbox_schema = outbox_match.group(1)
assert re.search(
    r"event_type\s+text\s+not\s+null\s+check\s*\(\s*event_type\s+in\s*\(\s*'debt_created'\s*,\s*'payment_created'\s*\)\s*\)",
    outbox_schema,
    re.IGNORECASE | re.DOTALL,
), 'push outbox event_type must be limited to debt_created/payment_created'

for forbidden in ('debt_updated', 'payment_updated', 'debt_deleted', 'payment_deleted'):
    assert forbidden not in outbox_schema, f'unsupported Web Push event type allowed: {forbidden}'

web = ROOT / 'customer-push-web'
for name in ('index.html', 'app.js', 'sw.js', 'manifest.webmanifest', '_headers'):
    assert (web / name).exists(), f'missing customer push web asset: {name}'

app_js = (web / 'app.js').read_text(errors='ignore')
assert (
    'https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/customer-push'
    in app_js
), 'customer push PWA must use the Supabase JSON API'
for secret_name in (
    'SUPABASE_SERVICE_ROLE_KEY',
    'VAPID_PRIVATE_KEY',
    'CUSTOMER_PUSH_WORKER_SECRET',
    'CUSTOMER_PUSH_RATE_LIMIT_SALT',
):
    assert secret_name not in app_js, f'server secret leaked to customer push PWA: {secret_name}'
assert "action: 'portal'" in app_js, 'customer push link must expose the read-only customer portal'

portal_migrations = '\n'.join(
    path.read_text(errors='ignore')
    for path in (ROOT / 'supabase' / 'migrations').glob('*_customer_push_portal.sql')
)
assert 'read_customer_push_portal_service' in portal_migrations, 'customer portal RPC missing'
assert 'device_secret_hash' in portal_migrations, 'installed portal must authenticate with device secret'

sw_js = (web / 'sw.js').read_text(errors='ignore')
assert 'customer_id' not in sw_js, 'service worker must not expose customer_id'
assert "clients.openWindow('/')" in sw_js, 'notification clicks must open the generic PWA root'

manifest = (web / 'manifest.webmanifest').read_text(errors='ignore')
assert re.search(r'"scope"\s*:\s*"/"', manifest), 'PWA scope must be /'
assert re.search(r'"start_url"\s*:\s*"/"', manifest), 'PWA start_url must be /'

headers = (web / '_headers').read_text(errors='ignore')
assert 'Referrer-Policy: no-referrer' in headers
assert 'Cache-Control: no-store' in headers
assert 'https://hsoyfbtpvwfmjokudznx.supabase.co' in headers
assert 'Service-Worker-Allowed: /' in headers

print('customer push policy verified')
