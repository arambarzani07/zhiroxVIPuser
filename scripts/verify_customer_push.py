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

permanent_migration = ROOT / 'supabase/migrations/20260917194000_permanent_customer_push_links.sql'
assert permanent_migration.exists(), 'permanent customer push link migration missing'
permanent_schema = permanent_migration.read_text(errors='ignore')
assert re.search(
    r'alter\s+table\s+public\.customer_push_link_tokens\s+alter\s+column\s+expires_at\s+drop\s+not\s+null',
    permanent_schema,
    re.IGNORECASE | re.DOTALL,
), 'permanent links must allow NULL expiry'
assert re.search(
    r'update\s+public\.customer_push_link_tokens\s+set\s+expires_at\s*=\s*null',
    permanent_schema,
    re.IGNORECASE | re.DOTALL,
), 'legacy active links must be migrated to no expiry'
assert 'active_link_count' in permanent_schema, 'push status must expose active_link_count'
assert 'expires_at > now()' not in permanent_schema, 'permanent link RPCs must not enforce expiry'
assert 'v_link.expires_at <= now()' not in permanent_schema, 'redeem must not enforce expiry'
assert 'and link.used_at is null' not in permanent_schema.lower(), 'inspect must not consume links once used'
assert 'set used_at = now()' not in permanent_schema.lower(), 'redeem must not consume a permanent link'

admin_text = (ROOT / 'supabase/functions/customer-push-admin/index.ts').read_text(errors='ignore')
assert '90 * 24 * 60 * 60 * 1000' not in admin_text, 'customer push links must not auto-expire after 90 days'
assert 'expires_at: null' in admin_text or 'expires_at: null,' in admin_text, 'admin API must return null expiry for permanent links'

card_text = (ROOT / 'lib/widgets/customer_push_card.dart').read_text(errors='ignore')
assert '١٥ خولەک' not in card_text, 'manager UI must not claim a permanent QR expires in 15 minutes'
assert 'ئەم لینکە بەردەوام کار دەکات تا بەڕێوەبەر ڕایدەگرێت.' in card_text, 'manager UI must explain permanent-link behavior'

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
assert 'ماوەکەی تەواو بووە' not in app_js, 'permanent-link PWA must not describe links as expired'
assert 'QR ـێکی نوێ دروست بکە و دووبارە هەوڵ بدە' not in app_js, 'retry errors must not imply permanent links need replacement'
assert 'ئەم لینکە بەردەست نییە یان ڕاگیراوە.' in app_js, 'PWA must describe unavailable links as revoked/unavailable'

portal_migrations = '\n'.join(
    path.read_text(errors='ignore')
    for path in (ROOT / 'supabase' / 'migrations').glob('*_customer_push_portal.sql')
)
assert 'read_customer_push_portal_service' in portal_migrations, 'customer portal RPC missing'
assert 'device_secret_hash' in portal_migrations, 'installed portal must authenticate with device secret'

sw_js = (web / 'sw.js').read_text(errors='ignore')
assert 'customer_id' not in sw_js, 'service worker must not expose customer_id'
assert 'self.clients.matchAll' in sw_js, 'notification clicks must reuse an open customer portal'
assert 'customerPortal.navigate(target)' in sw_js, 'notification clicks must refresh the customer portal'
assert 'self.clients.openWindow(target)' in sw_js, 'notification clicks must open the portal when closed'
assert 'portalUrl(data.url)' in sw_js, 'notification payload URL must be honored safely'

manifest = (web / 'manifest.webmanifest').read_text(errors='ignore')
assert re.search(r'"scope"\s*:\s*"/"', manifest), 'PWA scope must be /'
assert re.search(r'"start_url"\s*:\s*"/"', manifest), 'PWA start_url must be /'

headers = (web / '_headers').read_text(errors='ignore')
assert 'Referrer-Policy: no-referrer' in headers
assert 'Cache-Control: no-store' in headers
assert 'https://hsoyfbtpvwfmjokudznx.supabase.co' in headers
assert 'Service-Worker-Allowed: /' in headers

print('customer push policy verified')
