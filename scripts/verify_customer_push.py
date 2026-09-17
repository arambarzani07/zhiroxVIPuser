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

migration_text = '\n'.join(
    path.read_text(errors='ignore')
    for path in (ROOT / 'supabase/migrations').glob('*.sql')
)
assert re.search(
    r"event_type\s+in\s*\(\s*'debt_created'\s*,\s*'payment_created'\s*\)",
    migration_text,
    re.IGNORECASE,
), 'push outbox event_type must be limited to debt_created/payment_created'

for forbidden in ('debt_updated', 'payment_updated', 'debt_deleted', 'payment_deleted'):
    outbox_check = re.search(
        rf"event_type\s+in\s*\([^)]*'{re.escape(forbidden)}'",
        migration_text,
        re.IGNORECASE,
    )
    assert outbox_check is None, f'unsupported Web Push event type allowed: {forbidden}'

print('customer push policy verified')
