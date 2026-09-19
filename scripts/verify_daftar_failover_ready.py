#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
migration = (ROOT / 'supabase/migrations/20260920010000_daftar_failover_ready.sql').read_text(errors='ignore')
worker = (ROOT / 'supabase/functions/daftar-sync/index.ts').read_text(errors='ignore')
workflow = (ROOT / '.github/workflows/ios-unsigned-ipa.yml').read_text(errors='ignore')

assert 'failover_ready boolean not null default false' in migration
assert 'last_safe_cutover_at' in migration
assert 'last_safe_contact_id' in migration
assert 'last_safe_transaction_id' in migration
assert 'primary_activated_at' in migration
assert 'daftar_source_mode_events' in migration
assert 'refresh_daftar_failover_readiness' in migration
assert 'activate_zhirox_primary' in migration
assert 'ACTIVATE_ZHIROX_PRIMARY_ACCOUNT_28' in migration
assert "health_status = 'healthy'" in migration
assert "raise exception 'daftar_source_still_healthy'" in migration
assert "sync_mode = 'zhirox_primary'" in migration
assert 'active => false' in migration
assert "if v_mode = 'zhirox_primary'" in migration
assert "new.enabled is distinct from false" in migration
assert "new.enabled is distinct from true" in migration

assert 'refresh_daftar_failover_readiness' in worker
assert 'failover_readiness_failed' in worker
assert 'Verify Daftar failover readiness' in workflow

print('Daftar failover readiness verified')
