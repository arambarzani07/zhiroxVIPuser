#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
migration = (ROOT / 'supabase/migrations/20260920203000_backfill_daftar_customer_links.sql').read_text(errors='ignore')
projection = (ROOT / 'supabase/migrations/20260920190500_fix_daftar_projection_auth.sql').read_text(errors='ignore')

for marker in (
    'tmp_daftar_customer_link_map',
    'daftar_mirror_contacts',
    'legacy_import_links',
    "'customer'",
    'norm_phone',
    'norm_name',
    'matches = 1',
    'v_resolved <> v_contacts',
):
    assert marker in migration, f'missing safe customer-link backfill marker: {marker}'

assert 'get_daftar_official_customer_totals' in projection
assert "l.entity_kind = 'customer'" in projection

print('Daftar customer identity link backfill verified')
