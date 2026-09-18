from pathlib import Path


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


service = Path('lib/services/app_update_service.dart').read_text()
gate = Path('lib/widgets/auto_update_gate.dart').read_text()
control = Path('lib/screens/auth/update_control_screen.dart').read_text()
main = Path('lib/main.dart').read_text()
workflow = Path('.github/workflows/ios-unsigned-ipa.yml').read_text()

require('ZHIROX_BUILD_NUMBER' in service, 'update service must read CI build number')
require('ZHIROX_APP_EDITION' in service, 'update service must isolate owner/user editions')
require('releases/download/' in service, 'update service must use permanent release manifest')
require("downloadUri.host != 'github.com'" in service, 'update download URL must be GitHub-only')
require('AppLifecycleState.resumed' in gate, 'update gate must re-check on app resume')
require('Auto Update Center' in gate, 'update gate UI is missing')
require('AppUpdateService.currentBuild' in gate, 'update gate must compare build numbers')
require("import 'package:zhirox/widgets/auto_update_gate.dart';" in main, 'main must import AutoUpdateGate')
require('AutoUpdateGate(' in main, 'main must wrap the app with AutoUpdateGate')
require('--build-number "$BUILD_NUMBER"' in workflow, 'iOS build must use resolved edition build number')
require('--dart-define=ZHIROX_BUILD_NUMBER="$BUILD_NUMBER"' in workflow, 'iOS build must embed resolved update build number')
require('Align Owner build number with User' in workflow, 'owner build must align to the latest user build number')
require('user-update.json' in workflow, 'owner build alignment must read the user update manifest')
require('--dart-define=ZHIROX_APP_EDITION="$UPDATE_EDITION"' in workflow, 'iOS build must embed app edition')
require('rollout_percent' in service, 'update service must honor staged rollout policy')
require('minimum_build' in service, 'update service must enforce minimum supported build')
require('_includedInRollout' in service, 'update service must use stable rollout bucketing')
require('rollout_percent' in control, 'owner release center must expose rollout percentage')
require('minimum_build' in control, 'owner release center must expose minimum build')
require('Generate update manifest' in workflow, 'workflow must generate update manifest')
require('$UPDATE_MANIFEST' in workflow, 'workflow must publish update manifest')

print('Auto Update Center verification passed.')
