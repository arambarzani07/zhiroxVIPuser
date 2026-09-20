#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
pb = (ROOT / 'lib/services/pb_service.dart').read_text(errors='ignore')
live = (ROOT / 'lib/services/daftar_live_read_service.dart').read_text(errors='ignore')
workflow = (ROOT / '.github/workflows/ios-unsigned-ipa.yml').read_text(errors='ignore')

assert "client.rpc('get_admin_dashboard_snapshot')" in pb
assert "refreshSession()" in pb
assert "DaftarLiveReadService.invokeMap('admin_dashboard')" in pb
assert "refreshSession()" in live
assert "FunctionException" in live
assert "Verify dashboard primary resilience" in workflow

print('Dashboard primary resilience verified')
