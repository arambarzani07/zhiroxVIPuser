from pathlib import Path


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


service = Path('lib/services/app_update_service.dart').read_text()
gate = Path('lib/widgets/auto_update_gate.dart').read_text()
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
require('--build-number "$GITHUB_RUN_NUMBER"' in workflow, 'iOS build must use monotonic run number')
require('--dart-define=ZHIROX_BUILD_NUMBER="$GITHUB_RUN_NUMBER"' in workflow, 'iOS build must embed update build number')
require('--dart-define=ZHIROX_APP_EDITION="$UPDATE_EDITION"' in workflow, 'iOS build must embed app edition')
require('rollout_percent' in service, 'update service must honor staged rollout policy')
require('minimum_build' in service, 'update service must enforce minimum supported build')
require('_includedInRollout' in service, 'update service must use stable rollout bucketing')
require('Generate update manifest' in workflow, 'workflow must generate update manifest')
require('$UPDATE_MANIFEST' in workflow, 'workflow must publish update manifest')
require('${GITHUB_RUN_NUMBER}.ipa' in workflow, 'every IPA must have a cache-safe unique build filename')
require('--sequesterRsrc' not in workflow, 'IPA packaging must not preserve macOS resource-fork metadata')
require('xattr -cr Payload' in workflow, 'IPA packaging must clear extended attributes before resigning')
require('find Payload -type d -name _CodeSignature -prune -exec rm -rf {}' in workflow, 'IPA packaging must remove stale nested code signatures')
require('/usr/bin/zip -qry "$IPA_FILE" Payload' in workflow, 'IPA packaging must use a signer-friendly ZIP')
require('unzip -t "$IPA_FILE"' in workflow, 'IPA workflow must validate archive integrity')
require("'$ipaFileStem-${info.latestBuild}.ipa'" in service, 'update service must validate the unique IPA filename')
require('rollback-index.json' in workflow, 'workflow must retain rollback targets')
require('active-release.json' in workflow, 'workflow must publish active release identity')
require('release-metadata.json' in workflow, 'workflow must capture immutable release metadata')
require('isRollback' in service, 'update service must recognize rollback manifests')
require('immutableUserPath' in service, 'user downloads must use immutable release tags')

print('Auto Update Center verification passed.')
