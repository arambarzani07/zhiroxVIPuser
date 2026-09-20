#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
migration = (
    ROOT / 'supabase/migrations/20260920165000_daftar_planned_primary_cutover.sql'
).read_text(errors='ignore')
workflow = (ROOT / '.github/workflows/ios-unsigned-ipa.yml').read_text(errors='ignore')

assert 'activate_zhirox_primary_planned' in migration
assert 'PLANNED_ACTIVATE_ZHIROX_PRIMARY_ACCOUNT_28' in migration
assert "sync_mode <> 'mirror'" in migration
assert "health_status <> 'healthy'" in migration
assert 'consecutive_failures <> 0' in migration
assert "outage_status <> 'healthy'" in migration
assert "last_success_at < now() - interval '5 minutes'" in migration
assert 'run_daftar_cutover_rehearsal' in migration
assert 'refresh_daftar_failover_readiness' in migration
assert "reconciliation_status <> 'clean'" in migration
assert 'reconciliation_missing_contacts <> 0' in migration
assert 'reconciliation_missing_transactions <> 0' in migration
assert "cutover_rehearsal_status <> 'pass'" in migration
assert 'cutover_rehearsal_mismatches <> 0' in migration
assert 'not v_source.failover_ready' in migration
assert "sync_mode = 'zhirox_primary'" in migration
assert "live_read_mode = 'off'" in migration
assert 'enabled = false' in migration
assert 'primary_activated_at = now()' in migration
assert 'planned_primary_cutover_while_source_healthy' in migration
assert "from public, anon, authenticated" in migration
assert 'to service_role' in migration

# Emergency failover remains distinct and still requires a confirmed outage.
outage_migration = (
    ROOT / 'supabase/migrations/20260920013000_daftar_outage_qualification.sql'
).read_text(errors='ignore')
assert "raise exception 'daftar_outage_not_confirmed'" in outage_migration
assert 'activate_zhirox_primary(' in outage_migration

assert 'Verify Daftar planned primary cutover' in workflow
print('Daftar planned primary cutover verified')
