#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
migration = (ROOT / 'supabase/migrations/20260920013000_daftar_outage_qualification.sql').read_text(errors='ignore')
workflow = (ROOT / '.github/workflows/ios-unsigned-ipa.yml').read_text(errors='ignore')

assert "outage_status text not null default 'healthy'" in migration
assert 'outage_suspected_at' in migration
assert 'outage_confirmed_at' in migration
assert 'qualify_daftar_outage' in migration
assert 'consecutive_failures >= 7' in migration
assert "circuit_open_until is not null" in migration
assert "last_success_at <= now() - interval '15 minutes'" in migration
assert "outage_status = 'confirmed'" in migration
assert "raise exception 'daftar_outage_not_confirmed'" in migration
assert 'perform public.qualify_daftar_outage(v_source_id)' in migration
assert "'outage_status', s.outage_status" in migration
assert 'Verify Daftar outage qualification' in workflow

print('Daftar outage qualification verified')
