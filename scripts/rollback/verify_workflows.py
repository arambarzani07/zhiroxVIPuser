from pathlib import Path
def require(value,message):
    if not value: raise SystemExit(message)
release=Path('.github/workflows/ios-unsigned-ipa.yml').read_text()
rollback=Path('.github/workflows/manual-rollback.yml').read_text()
require('rollback-index.json' in release,'release must publish rollback index')
require('active-release.json' in release,'release must publish active pointer')
require('release-metadata.json' in release,'release must publish immutable metadata')
require('workflow_dispatch:' in rollback,'rollback must be manual')
require('environment: production-rollback' in rollback,'production rollback must be protected')
require('cancel-in-progress: false' in rollback,'rollback must serialize')
require("if: inputs.mode == 'production'" in rollback,'production mode guard missing')
require('supabase functions deploy' in rollback,'function restore missing')
require('supabase migration' not in rollback and 'db reset' not in rollback and 'db push' not in rollback,
        'rollback must not mutate database')
require('Promote app manifest last' in rollback,'manifest must be promoted last')
print('Rollback workflow safety verification passed.')
