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
), 'base push outbox event_type must start with debt_created/payment_created'

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

automatic_migration = ROOT / 'supabase/migrations/20260918090000_guaranteed_customer_push_events.sql'
assert automatic_migration.exists(), 'guaranteed automatic customer push migration missing'
automatic_schema = automatic_migration.read_text(errors='ignore')
for marker in (
    'trg_customer_push_debt_insert',
    'trg_customer_push_payment_insert',
    'enqueue_customer_push_event_service',
    'record_payment_service',
    'record_customer_payment_service',
    'legacy_import_apply_payment',
):
    assert marker in automatic_schema, f'automatic customer push guarantee missing: {marker}'
assert "'debt_created'" in automatic_schema, 'automatic debt push must be queued server-side'
assert "'payment_created'" in automatic_schema, 'automatic payment push must be queued server-side'
assert 'exception when others' in automatic_schema.lower(), 'push side effects must remain best-effort and never roll back finance writes'
assert 'daftar_live_sync' in automatic_schema and 'legacy_import' in automatic_schema, 'automatic debt trigger must suppress imported historical records'

overview_filter_migration = ROOT / 'supabase/migrations/20260918103000_customer_push_admin_overview_filters.sql'
assert overview_filter_migration.exists(), 'customer push overview filter migration missing'
overview_filter_schema = overview_filter_migration.read_text(errors='ignore')
for marker in (
    'list_customer_push_overview_service',
    'p_filter',
    "'active'",
    "'inactive'",
    "'failed'",
    "'pending'",
):
    assert marker in overview_filter_schema, f'customer push overview filter marker missing: {marker}'

history_migration = ROOT / 'supabase/migrations/20260918100000_customer_push_history_retry.sql'
assert history_migration.exists(), 'customer push history/retry migration missing'
history_schema = history_migration.read_text(errors='ignore')
for marker in (
    'read_customer_push_history_service',
    'retry_customer_push_service',
    "'no_device'",
    "'partial'",
    'notification_deliveries',
):
    assert marker in history_schema, f'customer push history/retry marker missing: {marker}'
assert 'no_active_push_subscription' in history_schema, 'retry must refuse when no active device exists'

manual_migration = ROOT / 'supabase/migrations/20260917210000_manual_customer_push_notifications.sql'
assert manual_migration.exists(), 'manual customer push migration missing'
manual_schema = manual_migration.read_text(errors='ignore')
assert 'customer_manual_push_campaigns' in manual_schema, 'manual push audit table missing'
assert 'enqueue_manual_customer_push_service' in manual_schema, 'manual push enqueue RPC missing'
assert re.search(
    r"event_type\s+in\s*\(\s*'debt_created'\s*,\s*'payment_created'\s*,\s*'due_reminder'\s*,\s*'manual'\s*\)",
    manual_schema,
    re.IGNORECASE | re.DOTALL,
), 'manual migration must preserve debt/payment/due reminder and add manual push events'
assert "actor.role = 'admin'" in manual_schema, 'manual push must be restricted to the market manager/admin'
assert 'market_name' in manual_schema and 'p_message' in manual_schema, 'manual push payload must be server-branded with market name'
assert "revoke all on table public.customer_manual_push_campaigns from public, anon, authenticated" in manual_schema.lower(), 'manual push audit table must not be client-writable'

admin_text = (ROOT / 'supabase/functions/customer-push-admin/index.ts').read_text(errors='ignore')
assert 'https://push.zhirox.com/' in admin_text, 'customer QR links must use push.zhirox.com'
assert '90 * 24 * 60 * 60 * 1000' not in admin_text, 'customer push links must not auto-expire after 90 days'
assert 'expires_at: null' in admin_text or 'expires_at: null,' in admin_text, 'admin API must return null expiry for permanent links'
assert 'send_manual' in admin_text, 'admin API must support a single-customer manual push'
assert 'broadcast_manual' in admin_text, 'admin API must support broadcast manual push'
assert 'enqueue_manual_customer_push_service' in admin_text, 'admin API must route manual pushes through the secure RPC'
assert 'MANUAL_PUSH_MESSAGE_MAX_LENGTH = 240' in admin_text, 'manual push message limit must remain bounded'

link_text = (ROOT / 'supabase/functions/customer-push-link/index.ts').read_text(errors='ignore')
manifest_text = (ROOT / 'supabase/functions/customer-push-manifest/index.ts').read_text(errors='ignore')
assert 'https://push.zhirox.com/' in link_text, 'legacy QR gateway must redirect to push.zhirox.com'
assert 'https://push.zhirox.com/' in manifest_text, 'install manifest must use push.zhirox.com'
assert 'raw.githack.com' not in link_text, 'production QR gateway must not depend on raw.githack.com'
assert 'raw.githack.com' not in manifest_text, 'production manifest must not depend on raw.githack.com'

payload_text = (ROOT / 'supabase/functions/_shared/customer_push/payload.ts').read_text(errors='ignore')
assert '"manual"' in payload_text, 'push payload formatter must support manual notifications'
assert 'title: market' in payload_text, 'push notification title must be the supermarket name'

service_text = (ROOT / 'lib/services/customer_push_service.dart').read_text(errors='ignore')
assert 'sendManual' in service_text, 'Flutter push service must support sending one manual notification'
assert 'broadcastManual' in service_text, 'Flutter push service must support manual broadcast'

card_text = (ROOT / 'lib/widgets/customer_push_card.dart').read_text(errors='ignore')
assert '١٥ خولەک' not in card_text, 'manager UI must not claim a permanent QR expires in 15 minutes'
assert 'ئەم لینکە بەردەوام کار دەکات تا بەڕێوەبەر ڕایدەگرێت.' in card_text, 'manager UI must explain permanent-link behavior'
assert 'ناردنی ئاگاداری' in card_text, 'customer profile must expose manual notification send'

broadcast_widget = ROOT / 'lib/widgets/manual_push_broadcast_card.dart'
assert broadcast_widget.exists(), 'admin broadcast notification card missing'
broadcast_text = broadcast_widget.read_text(errors='ignore')
assert 'ئاگاداری گشتی' in broadcast_text, 'broadcast UI label missing'
assert 'broadcastManual' in broadcast_text, 'broadcast UI must call the broadcast service'

settings_text = (ROOT / 'lib/screens/admin/admin_settings_screen.dart').read_text(errors='ignore')
assert 'AdminNotificationsScreen' in settings_text, 'manager notification center must be reachable from the admin area'

web = ROOT / 'customer-push-web'
for name in ('index.html', 'app.js', 'sw.js', 'manifest.webmanifest', '_headers', 'apple-touch-icon.png'):
    assert (web / name).exists(), f'missing customer push web asset: {name}'
for name in ('styles.css',):
    assert (web / name).exists(), f'missing official portal asset: {name}'

index_html = (web / 'index.html').read_text(errors='ignore')
for marker in (
    'id="portalShell"',
    'id="homeView"',
    'id="transactionsView"',
    'id="notificationsView"',
    'id="marketBrand"',
    'id="primaryRemaining"',
    'id="notificationState"',
    'data-portal-tab="home"',
    'data-portal-tab="transactions"',
    'data-portal-tab="notifications"',
):
    assert marker in index_html, f'official customer portal marker missing: {marker}'
assert '<style>' not in index_html, 'official customer portal CSS must live in styles.css'
assert 'aria-live="polite"' in index_html, 'portal needs a scoped polite status region'
assert 'rel="apple-touch-icon"' in index_html and 'apple-touch-icon.png' in index_html, 'iOS Add to Home Screen must use the ZHIROX app logo'

styles_text = (web / 'styles.css').read_text(errors='ignore')
for marker in (
    '.portal-shell',
    '.balance-card',
    '.portal-nav',
    '@media (max-width: 420px)',
    'prefers-reduced-motion',
):
    assert marker in styles_text, f'official portal style missing: {marker}'
assert 'overflow-x: hidden' in styles_text, 'portal must guard narrow-screen horizontal overflow'

app_js = (web / 'app.js').read_text(errors='ignore')
assert (
    'https://madoflmbretqghqbqaak.supabase.co/functions/v1/customer-push'
    in app_js
), 'customer push PWA must use the Supabase JSON API'
for secret_name in (
    'SUPABASE_SERVICE_ROLE_KEY',
    'VAPID_PRIVATE_KEY',
    'CUSTOMER_PUSH_WORKER_SECRET',
    'CUSTOMER_PUSH_RATE_LIMIT_SALT',
):
    assert secret_name not in app_js, f'server secret leaked to customer push PWA: {secret_name}'
assert "action = 'portal'" in app_js and "portalCredentials(" in app_js, 'customer push link must expose the read-only customer portal'
assert 'ماوەکەی تەواو بووە' not in app_js, 'permanent-link PWA must not describe links as expired'
assert 'QR ـێکی نوێ دروست بکە و دووبارە هەوڵ بدە' not in app_js, 'retry errors must not imply permanent links need replacement'
assert 'ئەم لینکە بەردەست نییە یان ڕاگیراوە.' in app_js, 'PWA must describe unavailable links as revoked/unavailable'
assert 'URLSearchParams(' in app_js and "currentUrl.hash" in app_js, 'PWA must recover the QR bearer token from the URL fragment'
assert "searchParams.delete('token')" in app_js and "fragment.delete('token')" in app_js, 'PWA must scrub bearer-token credentials while preserving safe deep-link parameters'
assert 'function persistedPushCredentials()' in app_js, 'installed PWA must recognize its saved push session'
resolve_start = app_js.index('function resolveLinkToken')
resolve_end = app_js.index('let activeToken', resolve_start)
resolve_block = app_js[resolve_start:resolve_end]
assert 'persistedPushCredentials()' in resolve_block, 'saved device credentials must be checked before reusing the QR token'
assert resolve_block.index('persistedPushCredentials()') < resolve_block.index("currentUrl.searchParams.get('token')"), 'saved push session must take priority over the permanent QR token on app relaunch'
assert 'localStorage.removeItem(LINK_TOKEN_KEY)' in resolve_block, 'relaunch must discard stale bearer-token state once a device session exists'
configure_start = app_js.index('function configureNotificationExperience')
configure_end = app_js.index('async function initialize', configure_start)
configure_block = app_js[configure_start:configure_end]
assert configure_block.index('isIos() && !isStandalone()') < configure_block.index('!supportsPush()'), 'iOS Safari must show Add to Home Screen guidance before generic push unsupported state'
manifest_bootstrap = (web / 'manifest-bootstrap.js').read_text(errors='ignore')
assert 'currentUrl.hash' in manifest_bootstrap or 'window.location.hash' in manifest_bootstrap, 'install manifest bootstrap must recover the QR token from the URL fragment'
assert 'customer-push-manifest?token=' in manifest_bootstrap, 'install manifest bootstrap must request a token-aware manifest before Add to Home Screen'
for marker in (
    "setActiveView('home')",
    "setActiveView('transactions')",
    "setActiveView('notifications')",
    'renderNotificationState',
    'renderPrimaryBalance',
):
    assert marker in app_js, f'official portal behavior missing: {marker}'

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
assert "new URL('./', self.location.href).pathname" in sw_js, 'service worker scope must follow the static host path'
assert "navigator.serviceWorker.register('./sw.js', { scope: './' })" in app_js, 'PWA must register the service worker relative to its static host'

manifest = (web / 'manifest.webmanifest').read_text(errors='ignore')
assert re.search(r'"scope"\s*:\s*"\./"', manifest), 'PWA scope must stay inside the static portal directory'
assert re.search(r'"start_url"\s*:\s*"\./index\.html"', manifest), 'PWA start_url must stay inside the static portal directory'
assert 'apple-touch-icon.png' in manifest, 'static PWA manifest must expose the ZHIROX app logo'
assert 'apple-touch-icon.png' in manifest_text, 'token-aware install manifest must expose the ZHIROX app logo'

headers = (web / '_headers').read_text(errors='ignore')
assert 'Referrer-Policy: no-referrer' in headers
assert 'Cache-Control: no-store' in headers
assert 'https://madoflmbretqghqbqaak.supabase.co' in headers
assert 'Service-Worker-Allowed: /' in headers

print('customer push policy verified')

# Admin notification observability controls
service_text = (ROOT / 'lib/services/customer_push_service.dart').read_text(errors='ignore')
assert 'CustomerPushHistoryItem' in service_text, 'push history model missing'
assert 'loadHistory' in service_text, 'push history gateway missing'
assert 'retryNotification' in service_text, 'push retry gateway missing'
card_text = (ROOT / 'lib/widgets/customer_push_card.dart').read_text(errors='ignore')
assert 'مێژووی ئاگادارکردنەوەکان' in card_text, 'customer push history UI missing'
assert 'دووبارە ناردنەوە' in card_text, 'customer push retry UI missing'
admin_text = (ROOT / 'supabase/functions/customer-push-admin/index.ts').read_text(errors='ignore')
assert 'action === "history"' in admin_text, 'admin API history action missing'
assert 'action === "retry"' in admin_text, 'admin API retry action missing'
assert 'read_customer_push_history_service' in admin_text, 'admin API history RPC missing'
assert 'retry_customer_push_service' in admin_text, 'admin API retry RPC missing'


# Manager notification center
overview_migration = ROOT / 'supabase/migrations/20260918101500_customer_push_admin_overview.sql'
assert overview_migration.exists(), 'manager push overview migration missing'
overview_schema = overview_migration.read_text(errors='ignore')
assert 'list_customer_push_overview_service' in overview_schema, 'manager push overview RPC missing'
assert "'active_link_count'" in overview_schema, 'manager push overview must expose active links'
assert "'device_count'" in overview_schema, 'manager push overview must expose active devices'
assert 'action === "overview"' in admin_text, 'admin API overview action missing'
assert 'list_customer_push_overview_service' in admin_text, 'admin API overview RPC missing'
assert 'CustomerPushOverviewItem' in service_text, 'manager push overview model missing'
assert 'loadOverview' in service_text, 'manager push overview gateway missing'
notification_screen = ROOT / 'lib/screens/admin/admin_notifications_screen.dart'
assert notification_screen.exists(), 'manager notification center screen missing'
notification_screen_text = notification_screen.read_text(errors='ignore')
for marker in (
    'ئاگادارکردنەوەکان',
    'ManualPushBroadcastCard',
    'loadOverview',
    'notifications_active_rounded',
):
    assert marker in notification_screen_text, f'manager notification center marker missing: {marker}'
settings_text = (ROOT / 'lib/screens/admin/admin_settings_screen.dart').read_text(errors='ignore')
assert 'AdminNotificationsScreen' in settings_text, 'manager notification center must be reachable from settings'


# Customer portal notification history
portal_history_candidates = sorted(
    (ROOT / 'supabase/migrations').glob('*_customer_push_portal_notification_history.sql')
)
assert len(portal_history_candidates) == 1, (
    'customer portal notification history migration must exist exactly once'
)
portal_history_migration = portal_history_candidates[0]
portal_history_schema = portal_history_migration.read_text(errors='ignore')
assert 'read_customer_push_notification_history_service' in portal_history_schema, 'customer portal notification history RPC missing'
public_push_text = (ROOT / 'supabase/functions/customer-push/index.ts').read_text(errors='ignore')
assert 'action === "notifications"' in public_push_text, 'public push API notification history action missing'
assert 'read_customer_push_notification_history_service' in public_push_text, 'public push API history RPC missing'
assert 'id="notificationHistory"' in index_html, 'portal notification history container missing'
assert 'id="notificationHistoryRefresh"' in index_html, 'portal notification history refresh control missing'
assert 'loadNotificationHistory' in app_js, 'portal notification history loader missing'
assert 'renderNotificationHistory' in app_js, 'portal notification history renderer missing'
assert '.notification-history-item' in styles_text, 'portal notification history styles missing'

admin_center_text = (ROOT / 'lib/screens/admin/admin_notifications_screen.dart').read_text(errors='ignore')
for marker in ('هەموو', 'چالاک', 'ناچالاک', 'شکست', 'لە ڕیزدایە', 'ناردنی ئاگاداری'):
    assert marker in admin_center_text, f'admin notification center filters missing: {marker}'
assert 'filter:' in admin_center_text, 'admin notification center must use server-side filtering'