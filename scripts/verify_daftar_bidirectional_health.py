#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
migration = (
    ROOT
    / 'supabase/migrations/20260921124359_expose_bidirectional_sync_health.sql'
).read_text(encoding='utf-8')
screen = (
    ROOT / 'lib/screens/admin/daftar_sync_dashboard_screen.dart'
).read_text(encoding='utf-8')

for marker in (
    "'bidirectional_ready'",
    "'outbound_queue'",
    "'inbound_missing_candidates'",
    "'reconciliation_missing_contacts'",
    "'reconciliation_missing_transactions'",
    "o.status in ('failed', 'blocked')",
    "'inbound_request_id'",
    "'outbound_request_id'",
    "'action', 'drain'",
):
    assert marker in migration, marker

for marker in (
    "final bidirectionalReady",
    "final outboundWaiting",
    "final outboundErrors",
    "final reconciliationGaps",
    "پەیوەندی دوولایەنە: چالاک",
    "گۆڕانکاریی چاوەڕوان",
    "هەڵەی ناردن",
    "جیاوازیی داتا",
):
    assert marker in screen, marker

assert "from public, anon" in migration
assert "to authenticated" in migration

print('Daftar bidirectional health dashboard verified')
