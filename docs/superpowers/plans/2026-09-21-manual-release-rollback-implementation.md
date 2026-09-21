# Manual Release Rollback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a manual, fail-closed rollback path for the `user-source` app and Supabase Edge Functions that can restore one of the five newest validated releases without reverting or mutating database data.

**Architecture:** The normal iOS workflow will create an immutable, checksummed release bundle containing the IPA, update manifest, exact Edge Function sources/settings, Git identity, and minimum database migration. A protected manual workflow will validate a retained tag and confirmation phrase, prove forward-schema compatibility, save the active release, deploy the selected functions, promote its app manifest last, verify deployment/sync safety, and record an audit summary. Eligibility is maintained in a signed-by-GitHub-workflow `rollback-index.json` asset on the moving `user-latest` release; release tags and immutable assets are never rewritten.

**Tech Stack:** GitHub Actions, Python 3.11 standard library (`argparse`, `hashlib`, `json`, `tarfile`, `tomllib`, `unittest`), GitHub CLI, Supabase CLI, Deno 2/TypeScript, Flutter iOS unsigned IPA release assets.

**Spec:** `docs/superpowers/specs/2026-09-21-manual-release-rollback-design.md`

## Global Constraints

- The rollback line is `user-source` only; `owner-source` continues using its existing release flow.
- Rollback is manual only through `workflow_dispatch`; no health check, runtime error, CI failure, or schedule may invoke it automatically.
- Restore the app artifact and rollback-managed Supabase Edge Functions only.
- Never reverse/apply PostgreSQL migrations, restore a database backup, mutate/delete production rows, clear the Daftar outbox, or rewrite sync origins in the rollback workflow.
- Retain exactly the newest five validated rollback-ready releases as eligible targets without deleting Git history or immutable release assets.
- Production execution requires GitHub Environment `production-rollback`; dry-run performs no production write.
- Target inputs must be immutable retained tags, never branch names, arbitrary commits, or the currently active release.
- App promotion occurs only after every selected Edge Function deploy succeeds.
- Database evolution stays forward-only; a missing minimum migration or an intervening rollback barrier blocks before deployment.
- A production rollback requires the exact phrase `ROLLBACK <target-tag>` and a non-empty operator reason of at least 12 characters.
- Release bundles and logs contain no secrets, Supabase credentials, Vault values, Daftar credentials, or service-role values.
- A production function absent from the target release is kept, never deleted; it must be explicitly classified `safe_to_keep` or rollback is blocked.
- Existing Daftar inbound/outbound idempotency, origin tracking, retry, duplicate protection, credit-limit, and live-read checks remain green.

## Review Focus

- **Moving tag or replaced release asset:** validation must compare the tag commit, metadata commit, bundle checksums, and downloaded asset digests before any deploy. Covered in Tasks 2 and 5.
- **Current production contains a function absent from an older bundle:** rollback must keep only explicitly `safe_to_keep` functions and block every unknown function. Covered in Tasks 1 and 5.
- **Current schema crossed an incompatible migration:** a declared rollback barrier between target minimum and current migration must stop before the Supabase CLI deploy command. Covered in Tasks 3 and 5.
- **Function deployment succeeds partially or verification fails:** app manifest must remain unpromoted, and the saved source release plus partial deployment report must be shown. Covered in Tasks 5 and 7.
- **Two operators start rollback concurrently:** production workflow concurrency must serialize runs without cancellation and re-read the active release after entering the protected environment. Covered in Task 5.

---

## File Structure

### New files

- `rollback/managed-functions.json` — explicit allowlist of every currently managed production function and its source path; records which future-only functions may be kept when absent from an older release.
- `rollback/rollback-barriers.json` — versioned list of intentionally incompatible forward migrations; initially empty.
- `scripts/rollback/release_bundle.py` — deterministic bundle creation, checksum generation, tag/index validation, compatibility checks, active-release snapshots, and CLI subcommands.
- `scripts/rollback/test_release_bundle.py` — pure unit tests for discovery, checksum tamper detection, retention, confirmation, tag identity, barriers, and absent-function policy.
- `scripts/rollback/verify_workflows.py` — static safety contract for the capture and manual rollback workflows.
- `.github/workflows/manual-rollback.yml` — protected dry-run/production rollback orchestration.

### Modified files

- `.github/workflows/ios-unsigned-ipa.yml` — use an immutable user release tag/download URL, capture the validated bundle, publish the moving update pointer, and retain the newest five target tags.
- `scripts/verify_auto_update.py` — require immutable user download URLs and the active-release/rollback index assets.

### Generated release assets (not committed)

- `release-metadata.json` — schema, tag, commit, build, minimum migration, IPA/manifest names and digests, function settings, absent-function policy, and `rollback_ready`.
- `release-checksums.sha256` — sorted SHA-256 inventory for all files in the bundle except itself.
- `edge-functions.tar.gz` — exact managed `supabase/functions` sources plus `supabase/config.toml` and the allowlist.
- `active-release.json` — current immutable user release tag/commit/build and promotion timestamp.
- `rollback-index.json` — newest-to-oldest list of at most five validated immutable tags.

---

### Task 1: Lock the managed function and compatibility policy

**Files:**
- Create: `rollback/managed-functions.json`
- Create: `rollback/rollback-barriers.json`
- Create: `scripts/rollback/test_release_bundle.py`
- Create: `scripts/rollback/release_bundle.py`

**Interfaces:**
- Produces `load_policy(repo: Path) -> dict`, `discover_functions(repo: Path) -> dict[str, bool]`, and `validate_function_policy(repo: Path) -> list[str]`.
- `discover_functions` maps function name to effective `verify_jwt`; an omitted `supabase/config.toml` entry defaults to `true`.
- `validate_function_policy` returns sorted validation errors and never changes files.

- [ ] **Step 1: Add failing policy tests**

Create `scripts/rollback/test_release_bundle.py` with these first tests:

```python
import json
import tempfile
import unittest
from pathlib import Path

from release_bundle import discover_functions, validate_function_policy


class FunctionPolicyTests(unittest.TestCase):
    def make_repo(self) -> Path:
        root = Path(tempfile.mkdtemp())
        (root / "supabase/functions/alpha").mkdir(parents=True)
        (root / "supabase/functions/beta").mkdir(parents=True)
        (root / "supabase/functions/alpha/index.ts").write_text("export {};\n")
        (root / "supabase/functions/beta/index.ts").write_text("export {};\n")
        (root / "supabase/config.toml").write_text(
            "[functions.alpha]\nverify_jwt = false\n"
        )
        (root / "rollback").mkdir()
        return root

    def test_discovers_false_and_default_true_jwt(self):
        root = self.make_repo()
        self.assertEqual(discover_functions(root), {"alpha": False, "beta": True})

    def test_rejects_unlisted_repository_function(self):
        root = self.make_repo()
        (root / "rollback/managed-functions.json").write_text(json.dumps({
            "schema": 1,
            "functions": [{"name": "alpha", "path": "supabase/functions/alpha", "safe_to_keep_when_absent": False}],
        }))
        self.assertEqual(
            validate_function_policy(root),
            ["repository function is not allowlisted: beta"],
        )
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
cd scripts/rollback
python3 -m unittest -v test_release_bundle.FunctionPolicyTests
```

Expected: `ModuleNotFoundError: No module named 'release_bundle'`.

- [ ] **Step 3: Add the explicit policies**

Create `rollback/managed-functions.json` with all current production function directories, sorted by name:

```json
{
  "schema": 1,
  "functions": [
    {"name":"account-admin","path":"supabase/functions/account-admin","safe_to_keep_when_absent":false},
    {"name":"customer-push","path":"supabase/functions/customer-push","safe_to_keep_when_absent":false},
    {"name":"customer-push-admin","path":"supabase/functions/customer-push-admin","safe_to_keep_when_absent":false},
    {"name":"customer-push-events","path":"supabase/functions/customer-push-events","safe_to_keep_when_absent":false},
    {"name":"customer-push-link","path":"supabase/functions/customer-push-link","safe_to_keep_when_absent":false},
    {"name":"customer-push-manifest","path":"supabase/functions/customer-push-manifest","safe_to_keep_when_absent":false},
    {"name":"customer-push-worker","path":"supabase/functions/customer-push-worker","safe_to_keep_when_absent":false},
    {"name":"customer-read-link","path":"supabase/functions/customer-read-link","safe_to_keep_when_absent":false},
    {"name":"daftar-credit-gateway","path":"supabase/functions/daftar-credit-gateway","safe_to_keep_when_absent":false},
    {"name":"daftar-live-read","path":"supabase/functions/daftar-live-read","safe_to_keep_when_absent":false},
    {"name":"daftar-outbound-sync","path":"supabase/functions/daftar-outbound-sync","safe_to_keep_when_absent":false},
    {"name":"daftar-sync","path":"supabase/functions/daftar-sync","safe_to_keep_when_absent":false},
    {"name":"daftar-sync-gateway","path":"supabase/functions/daftar-sync-gateway","safe_to_keep_when_absent":false},
    {"name":"debt-restore-admin","path":"supabase/functions/debt-restore-admin","safe_to_keep_when_absent":false},
    {"name":"delete-account","path":"supabase/functions/delete-account","safe_to_keep_when_absent":false},
    {"name":"fib-subscription-payment","path":"supabase/functions/fib-subscription-payment","safe_to_keep_when_absent":false},
    {"name":"intelligence-ai","path":"supabase/functions/intelligence-ai","safe_to_keep_when_absent":false},
    {"name":"legacy-import","path":"supabase/functions/legacy-import","safe_to_keep_when_absent":false},
    {"name":"record-payment","path":"supabase/functions/record-payment","safe_to_keep_when_absent":false},
    {"name":"update-account","path":"supabase/functions/update-account","safe_to_keep_when_absent":false}
  ]
}
```

Create `rollback/rollback-barriers.json`:

```json
{"schema":1,"barriers":[]}
```

New functions must enter the allowlist as `safe_to_keep_when_absent: false`; setting it to `true` requires an explicit reviewed commit proving the old release remains compatible while the newer function stays deployed.

- [ ] **Step 4: Implement function discovery and policy validation**

Create `scripts/rollback/release_bundle.py` beginning with:

```python
#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import tarfile
import tempfile
import tomllib
from pathlib import Path

RETENTION = 5
TAG_RE = re.compile(r"^user-r[1-9][0-9]*-[0-9a-f]{7}$")


def read_json(path: Path) -> dict:
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def discover_functions(repo: Path) -> dict[str, bool]:
    config_path = repo / "supabase/config.toml"
    config = tomllib.loads(config_path.read_text()) if config_path.exists() else {}
    configured = config.get("functions", {})
    result: dict[str, bool] = {}
    for path in sorted((repo / "supabase/functions").iterdir()):
        if not path.is_dir() or path.name.startswith("_"):
            continue
        if not (path / "index.ts").is_file():
            raise ValueError(f"missing entrypoint: {path}/index.ts")
        result[path.name] = bool(configured.get(path.name, {}).get("verify_jwt", True))
    return result


def load_policy(repo: Path) -> dict:
    policy = read_json(repo / "rollback/managed-functions.json")
    if policy.get("schema") != 1 or not isinstance(policy.get("functions"), list):
        raise ValueError("unsupported managed-functions policy")
    return policy


def validate_function_policy(repo: Path) -> list[str]:
    discovered = discover_functions(repo)
    entries = load_policy(repo)["functions"]
    names = [entry.get("name") for entry in entries]
    errors: list[str] = []
    if names != sorted(names) or len(names) != len(set(names)):
        errors.append("allowlist names must be sorted and unique")
    allowed = set(names)
    for name in sorted(set(discovered) - allowed):
        errors.append(f"repository function is not allowlisted: {name}")
    for name in sorted(allowed - set(discovered)):
        errors.append(f"allowlisted function is missing from repository: {name}")
    for entry in entries:
        expected = f"supabase/functions/{entry.get('name')}"
        if entry.get("path") != expected:
            errors.append(f"invalid function path for {entry.get('name')}: {entry.get('path')}")
        if not isinstance(entry.get("safe_to_keep_when_absent"), bool):
            errors.append(f"invalid absent-function policy for {entry.get('name')}")
    return errors
```

- [ ] **Step 5: Run policy tests and the real-repository validation**

Run:

```bash
python3 -m unittest -v scripts/rollback/test_release_bundle.py
python3 scripts/rollback/release_bundle.py validate-policy --repo .
```

Add a `validate-policy` argparse command that prints `managed function policy valid` and exits 0 only when `validate_function_policy` is empty. Expected: all tests pass and the repository validation exits 0.

- [ ] **Step 6: Commit**

```bash
git add rollback/managed-functions.json rollback/rollback-barriers.json scripts/rollback/release_bundle.py scripts/rollback/test_release_bundle.py
git commit -m "feat(release): define rollback-managed functions"
```

---

### Task 2: Build and cryptographically validate immutable release bundles

**Files:**
- Modify: `scripts/rollback/release_bundle.py`
- Modify: `scripts/rollback/test_release_bundle.py`

**Interfaces:**
- Produces `sha256_file(path: Path) -> str`, `build_bundle(repo, output, tag, commit, build_number, ipa, update_manifest) -> dict`, and `validate_bundle(bundle_dir, expected_tag, expected_commit) -> list[str]`.
- Bundle metadata schema is `1`; all timestamps are informational, while tag, commit, file names, function settings, minimum migration, and hashes are authoritative.

- [ ] **Step 1: Add failing happy-path and tamper tests**

Append tests that create a miniature repo with `supabase/functions/alpha/index.ts`, `_shared/helper.ts`, `supabase/config.toml`, two ordered migration files, the policies, an IPA byte fixture, and an update manifest whose `commit`/`download_url` match the immutable tag. Assert:

```python
metadata = build_bundle(
    root, output, "user-r42-abcdef0", "abcdef0123456789", 42, ipa, manifest
)
self.assertEqual(metadata["minimum_migration"], "20260921103000_daftar_bidirectional_mutations.sql")
self.assertEqual(metadata["functions"][0]["verify_jwt"], False)
self.assertEqual(validate_bundle(output, "user-r42-abcdef0", "abcdef0123456789"), [])
(output / metadata["ipa"]["name"]).write_bytes(b"tampered")
self.assertIn("checksum mismatch", "\n".join(validate_bundle(output, "user-r42-abcdef0", "abcdef0123456789")))
```

Also assert the tar member list contains only relative normalized paths under `supabase/functions`, `supabase/config.toml`, and `rollback/managed-functions.json`; no member may start with `/` or contain `..`.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
python3 -m unittest -v scripts.rollback.test_release_bundle.FunctionPolicyTests scripts.rollback.test_release_bundle.BundleTests
```

Expected: import errors for `build_bundle` and `validate_bundle`.

- [ ] **Step 3: Implement deterministic bundle capture**

Implement these rules in `build_bundle`:

```python
def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def latest_migration(repo: Path) -> str:
    migrations = sorted(path.name for path in (repo / "supabase/migrations").glob("*.sql"))
    if not migrations:
        raise ValueError("no Supabase migration found")
    return migrations[-1]
```

- Reject a tag that does not match `TAG_RE` or whose seven-character suffix differs from `commit[:7]`.
- Reject a non-40-character lowercase hexadecimal production commit; fixtures may pass a 16+ hexadecimal commit only through a documented test helper parameter.
- Require `validate_function_policy(repo) == []`.
- Require manifest `edition == "user"`, integer `build_number`, exact `commit`, exact IPA SHA-256, and `download_url` ending `/releases/download/<tag>/<ipa-name>`.
- Copy IPA and update manifest into the output directory.
- Create `edge-functions.tar.gz` deterministically with gzip mtime 0 and tar members sorted by POSIX path; include every allowlisted function, `_shared`, `supabase/config.toml`, and the allowlist.
- Record each function as `{name, path, entrypoint: "index.ts", verify_jwt, source_sha256, safe_to_keep_when_absent}` where `source_sha256` hashes sorted relative paths plus file bytes.
- Write `release-metadata.json` with `rollback_ready: true` only after every file is built.
- Write `release-checksums.sha256` last as sorted lines `<sha256>  <filename>` for IPA, update manifest, function archive, and metadata.

- [ ] **Step 4: Implement fail-closed bundle validation**

`validate_bundle` must return explicit errors for:

- malformed/unknown metadata schema;
- invalid or mismatched tag/commit;
- `rollback_ready` not exactly `true`;
- missing file, unexpected symlink, invalid checksum syntax, duplicate checksum name, or checksum mismatch;
- metadata file names containing `/`, `\`, `..`, or an absolute path;
- missing/duplicate functions, invalid `verify_jwt`, or a function set inconsistent with bundled allowlist;
- unsafe tar paths, unlisted tar members, or extracted function source hash mismatch;
- manifest commit, build number, IPA name/hash, or immutable download URL mismatch.

The validator must not extract with `extractall`; inspect members first and copy allowed regular files one-by-one when later deployment needs extraction.

- [ ] **Step 5: Run all bundle tests**

Run:

```bash
python3 -m unittest -v scripts/rollback/test_release_bundle.py
```

Expected: all tests pass, including tamper, traversal, duplicate checksum, wrong tag, and moving-download-URL cases.

- [ ] **Step 6: Commit**

```bash
git add scripts/rollback/release_bundle.py scripts/rollback/test_release_bundle.py
git commit -m "feat(release): build validated rollback bundles"
```

---

### Task 3: Add retention, confirmation, migration compatibility, and absent-function guards

**Files:**
- Modify: `scripts/rollback/release_bundle.py`
- Modify: `scripts/rollback/test_release_bundle.py`

**Interfaces:**
- Produces `next_index(existing: dict | None, release: dict) -> dict`, `authorize(target, confirmation, reason, active, retained) -> list[str]`, `check_compatibility(metadata, applied_migrations, barriers, production_functions) -> dict`, and CLI commands `update-index`, `authorize`, and `check-compatibility`.

- [ ] **Step 1: Add failing safety-policy tests**

Add tests proving:

```python
self.assertEqual(len(next_index(existing_seven, newest)["releases"]), 5)
self.assertEqual(next_index(existing_seven, newest)["releases"][0]["tag"], newest["tag"])
self.assertIn("confirmation phrase", "\n".join(authorize(target, "wrong", "valid rollback reason", active, retained)))
self.assertIn("currently active", "\n".join(authorize(active, f"ROLLBACK {active}", "valid rollback reason", active, retained)))
self.assertIn("not retained", "\n".join(authorize("user-r1-aaaaaaa", "ROLLBACK user-r1-aaaaaaa", "valid rollback reason", active, retained)))
```

Add compatibility tests for: minimum migration not applied; barrier strictly newer than the target minimum and at-or-before current migration; an unknown production function absent from target; an explicitly safe-to-keep production function; and current migration older than target minimum.

- [ ] **Step 2: Run safety-policy tests and verify RED**

Run:

```bash
python3 -m unittest -v scripts.rollback.test_release_bundle.RetentionAuthorizationTests scripts.rollback.test_release_bundle.CompatibilityTests
```

Expected: import errors for the new functions.

- [ ] **Step 3: Implement five-release retention and manual authorization**

`next_index` must validate existing schema, deduplicate by tag, prepend the new release, sort by numeric build descending, slice to `RETENTION`, and output:

```json
{"schema":1,"retention":5,"releases":[{"tag":"user-r42-abcdef0","commit":"abcdef...","build_number":42,"metadata_sha256":"..."}]}
```

`authorize` must reject invalid tag syntax, a target absent from the retained set, current target, exact phrase mismatch, and stripped reasons shorter than 12 characters. It returns all errors so dry-run summaries are actionable.

- [ ] **Step 4: Implement forward-only compatibility checks**

Normalize applied migrations to exact `*.sql` names. Require the target `minimum_migration` to be present. Determine `current_migration = max(applied_migrations)` and block every barrier whose `migration` satisfies:

```python
metadata["minimum_migration"] < barrier["migration"] <= current_migration
```

Reject barrier files not sorted/unique or entries missing a non-empty `reason`. Compare production function names to target metadata: target functions are deployed; extra production functions are kept only when the *current checked-out policy* marks them `safe_to_keep_when_absent: true`; all other extras block. Return a plan object containing `deploy`, `keep`, `minimum_migration`, `current_migration`, and `barriers_checked` only when no errors exist.

- [ ] **Step 5: Add CLI JSON contracts and run tests**

Commands must accept file inputs and print exactly one JSON object to stdout; diagnostics go to stderr. A validation error exits 2, while environmental/IO failure exits 1.

Run:

```bash
python3 -m unittest -v scripts/rollback/test_release_bundle.py
python3 scripts/rollback/release_bundle.py authorize --target user-r1-aaaaaaa --confirmation wrong --reason short --active user-r2-bbbbbbb --index /tmp/nonexistent.json
```

Expected: tests pass; the deliberately invalid CLI exits non-zero without a traceback or secret-bearing environment dump.

- [ ] **Step 6: Commit**

```bash
git add scripts/rollback/release_bundle.py scripts/rollback/test_release_bundle.py
git commit -m "feat(release): enforce rollback eligibility"
```

---

### Task 4: Capture immutable rollback-ready releases in the iOS workflow

**Files:**
- Modify: `.github/workflows/ios-unsigned-ipa.yml`
- Modify: `scripts/verify_auto_update.py`
- Create: `scripts/rollback/verify_workflows.py`

**Interfaces:**
- Produces immutable tag `user-r${GITHUB_RUN_NUMBER}-${GITHUB_SHA::7}` for `user-source`.
- Publishes immutable IPA, immutable update manifest, `release-metadata.json`, `release-checksums.sha256`, and `edge-functions.tar.gz`.
- Updates `user-latest` assets `user-update.json`, `active-release.json`, and `rollback-index.json` only after immutable release validation/publish succeeds.

- [ ] **Step 1: Write failing static workflow assertions**

Create `scripts/rollback/verify_workflows.py` using `Path.read_text()` and explicit `require(condition, message)` checks for:

- `IMMUTABLE_TAG=user-r${GITHUB_RUN_NUMBER}-${GITHUB_SHA::7}` only on `user-source`;
- `release_bundle.py build`, `release_bundle.py validate`, and `release_bundle.py update-index`;
- immutable manifest URL uses `${IMMUTABLE_TAG}`;
- immutable release creation uses `--verify-tag` after an annotated tag is created at `$GITHUB_SHA`;
- moving `user-latest` receives `active-release.json` and `rollback-index.json`;
- capture occurs after Flutter/Deno/static tests and before moving-channel publication;
- no `supabase db`, `migration up/down/repair`, destructive SQL, or `--clobber` against an immutable tag.

Add equivalent requirements to `scripts/verify_auto_update.py` for immutable user URLs and active/index assets.

- [ ] **Step 2: Run static checks and verify RED**

Run:

```bash
python3 scripts/rollback/verify_workflows.py
python3 scripts/verify_auto_update.py
```

Expected: both fail because capture assets and immutable user tag do not yet exist.

- [ ] **Step 3: Split immutable and moving release identities**

In `Resolve app edition`, add user-only `ROLLBACK_ENABLED=true`; owner uses `false`. Add a step after checkout:

```bash
if [ "$ROLLBACK_ENABLED" = true ]; then
  echo "IMMUTABLE_TAG=user-r${GITHUB_RUN_NUMBER}-${GITHUB_SHA::7}" >> "$GITHUB_ENV"
else
  echo "IMMUTABLE_TAG=$UPDATE_TAG" >> "$GITHUB_ENV"
fi
```

Change user manifest `download_url` to use `IMMUTABLE_TAG`; keep owner behavior unchanged. The immutable IPA filename remains `ZHIROX-User-${GITHUB_RUN_NUMBER}.ipa`.

- [ ] **Step 4: Build and validate the release bundle**

After all tests and packaging succeed, run for `user-source`:

```bash
python3 scripts/rollback/release_bundle.py build \
  --repo . --output rollback-bundle \
  --tag "$IMMUTABLE_TAG" --commit "$GITHUB_SHA" \
  --build-number "$GITHUB_RUN_NUMBER" \
  --ipa "$IPA_FILE" --manifest "$UPDATE_MANIFEST"
python3 scripts/rollback/release_bundle.py validate \
  --bundle rollback-bundle --tag "$IMMUTABLE_TAG" --commit "$GITHUB_SHA"
```

- [ ] **Step 5: Publish the immutable tag/release without overwrite**

Use `GH_TOKEN` and fail if either tag or release already exists:

```bash
git fetch --tags --force
if git rev-parse "refs/tags/$IMMUTABLE_TAG" >/dev/null 2>&1 || gh release view "$IMMUTABLE_TAG" >/dev/null 2>&1; then
  echo "immutable release already exists: $IMMUTABLE_TAG" >&2
  exit 1
fi
git tag -a "$IMMUTABLE_TAG" "$GITHUB_SHA" -m "Rollback-ready user release $IMMUTABLE_TAG"
git push origin "refs/tags/$IMMUTABLE_TAG"
gh release create "$IMMUTABLE_TAG" \
  rollback-bundle/* \
  --verify-tag --title "ZHIROX User $IMMUTABLE_TAG" \
  --notes "Validated rollback-ready user release from $GITHUB_SHA."
```

Never use `--clobber` with `$IMMUTABLE_TAG`.

- [ ] **Step 6: Update the moving channel and five-release index**

Download the prior `rollback-index.json` from `user-latest` when present; otherwise use no existing index. Generate the next index with the new metadata hash. Generate `active-release.json` through a `release_bundle.py active-release` command so escaping is not shell-built. Upload the moving manifest, active pointer, and index with `--clobber`. The moving release does not need a duplicate IPA because its manifest points to the immutable release.

- [ ] **Step 7: Run static and regression checks**

Run:

```bash
python3 scripts/rollback/verify_workflows.py
python3 scripts/verify_auto_update.py
python3 -m unittest -v scripts/rollback/test_release_bundle.py
```

Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add .github/workflows/ios-unsigned-ipa.yml scripts/verify_auto_update.py scripts/rollback/verify_workflows.py
git commit -m "feat(release): capture rollback-ready user releases"
```

---

### Task 5: Implement the protected manual rollback workflow

**Files:**
- Create: `.github/workflows/manual-rollback.yml`
- Modify: `scripts/rollback/verify_workflows.py`
- Modify: `scripts/rollback/test_release_bundle.py`
- Modify: `scripts/rollback/release_bundle.py`

**Interfaces:**
- Inputs: `target_tag` (string), `reason` (string), `mode` (`dry-run` or `production`), and `confirmation` (string).
- Secrets for production: `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`; GitHub token remains the job token.
- Environment: `production-rollback` only on the production job.
- Produces downloaded/validated bundle, compatibility plan, current release snapshot, deployment report, and step summary.

- [ ] **Step 1: Extend failing static workflow tests**

Require:

- trigger is only `workflow_dispatch`;
- top-level `permissions: contents: read` and production job overrides only `contents: write`;
- `concurrency.group: user-production-rollback` and `cancel-in-progress: false`;
- a validation/dry-run job with no environment or Supabase secrets;
- production job condition is exactly `inputs.mode == 'production'` and uses `environment: production-rollback`;
- authorization/validation/compatibility precede any deploy;
- active release is re-downloaded inside production after environment approval;
- function deploy precedes app promotion;
- no DB migration/data mutation command and no function delete command.

- [ ] **Step 2: Add tests for applied migration parsing and safe tar extraction**

Add fixtures matching `supabase migration list --linked` table output, including local-only/remote-only rows. `parse_applied_migrations(text)` must return only remote-applied exact migration filenames by matching migration numeric versions back to the checked-out `supabase/migrations/*.sql`. Add a malicious tar fixture and assert `extract_bundle_functions` rejects it before writing outside the destination.

- [ ] **Step 3: Run focused tests and verify RED**

Run:

```bash
python3 -m unittest -v scripts.rollback.test_release_bundle.MigrationParsingTests scripts.rollback.test_release_bundle.ExtractionTests
python3 scripts/rollback/verify_workflows.py
```

Expected: new unit tests error and workflow verifier reports missing `manual-rollback.yml`.

- [ ] **Step 4: Create validation/dry-run job**

The job must:

1. Check out `user-source` by immutable workflow commit.
2. Validate input shape and reason/confirmation with `authorize`.
3. Download `active-release.json` and `rollback-index.json` from `user-latest`.
4. Prove the target index entry includes the same metadata SHA as the downloaded target release.
5. Resolve target tag commit with `git rev-list -n1 "$target_tag"` and require exact metadata commit.
6. Download target release assets to an empty directory with `gh release download "$target_tag" --dir target`.
7. Run bundle validation.
8. Install a pinned Supabase CLI version (record exact version in workflow env, initially `2.45.5`).
9. Run `supabase migration list --linked`, parse applied remote migrations, and run compatibility.
10. Run `supabase functions list --project-ref "$SUPABASE_PROJECT_REF" --output json` only in production; for dry-run, use a checked-in current allowlist snapshot and explicitly label production drift as unchecked.
11. Emit a complete planned action summary and upload validation artifacts.

Dry-run must stop here and never receive write-capable secrets. Because migration/function live-state checks need protected credentials, label dry-run `repository-only` unless it is run in the protected production job; production repeats every check against live state.

- [ ] **Step 5: Create protected production job and revalidate**

The production job must use:

```yaml
environment: production-rollback
concurrency:
  group: user-production-rollback
  cancel-in-progress: false
```

After approval, re-download active/index/target assets into a fresh directory, repeat authorization, Git/tag/checksum validation, query live applied migrations/functions, and regenerate compatibility. Abort if the active tag changed since the validation job or is now the target.

- [ ] **Step 6: Save source release and deploy functions deterministically**

Before deployment, create `rollback-source-release.json` containing active tag/commit/build, requested target, actor `${{ github.actor }}`, run ID/attempt, and reason. Upload it as a run artifact even on later failure.

Safely extract sources, then for metadata functions in sorted order run:

```bash
if [ "$verify_jwt" = false ]; then
  supabase functions deploy "$function_name" --project-ref "$SUPABASE_PROJECT_REF" --no-verify-jwt
else
  supabase functions deploy "$function_name" --project-ref "$SUPABASE_PROJECT_REF"
fi
```

Run from the extracted bundle root. Capture function name, expected source hash, JWT setting, start/end time, and command exit status in `function-deployment-report.json`. Stop at the first failure. Never deploy a source from the current checkout.

- [ ] **Step 7: Promote the app only after every deploy passes**

Re-run bundle validation, then upload the selected bundled `user-update.json` to `user-latest` with `--clobber`. Generate a new `active-release.json` that points to the selected immutable tag and records `promotion_kind: "manual_rollback"`, `source_tag`, actor, reason, run ID, and target metadata hash. Upload it after the manifest. Do not change `rollback-index.json` during rollback.

- [ ] **Step 8: Run workflow/static/unit tests and commit**

Run:

```bash
python3 -m unittest -v scripts/rollback/test_release_bundle.py
python3 scripts/rollback/verify_workflows.py
python3 scripts/verify_auto_update.py
```

Expected: all pass.

```bash
git add .github/workflows/manual-rollback.yml scripts/rollback/release_bundle.py scripts/rollback/test_release_bundle.py scripts/rollback/verify_workflows.py
git commit -m "feat(release): add protected manual rollback"
```

---

### Task 6: Add non-mutating runtime verification and Daftar safety gates

**Files:**
- Modify: `scripts/rollback/release_bundle.py`
- Modify: `scripts/rollback/test_release_bundle.py`
- Modify: `.github/workflows/manual-rollback.yml`
- Modify: `scripts/rollback/verify_workflows.py`

**Interfaces:**
- Produces `verify-promotion` and `verify-functions` CLI commands.
- `verify-promotion` checks live moving assets against target metadata without writing.
- `verify-functions` compares live Supabase function names/status/JWT metadata where exposed and performs non-mutating HTTP liveness probes.

- [ ] **Step 1: Add failing verification tests**

Add tests that reject: moving manifest build/hash/download URL differing from target metadata; active pointer target differing from manifest; missing deployed function; failed deployment status; 404/5xx function probe; and a verifier configuration containing POST/PUT/PATCH/DELETE probes. Accept 200, 204, 400, 401, 403, and 405 as proof the function route is alive; reject network failure, 404, 410, 429, and 5xx.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
python3 -m unittest -v scripts.rollback.test_release_bundle.RuntimeVerificationTests
```

Expected: missing verification functions.

- [ ] **Step 3: Implement non-mutating promotion/function verification**

Use only `GET`, `HEAD`, or `OPTIONS`. Probe each function URL with `OPTIONS` and a 10-second timeout; do not send service-role/Daftar secrets in query strings or logs. Compare deployed names from `supabase functions list --output json` with metadata and ensure every target function is present. Treat any status field other than `ACTIVE`/`active` (when supplied by CLI) as failure.

- [ ] **Step 4: Add Daftar regression and production safety checks**

Before app promotion, run from the selected bundle source:

```bash
python3 scripts/verify_daftar_sync_lock.py
python3 scripts/verify_daftar_primary_inbound_sync.py
python3 scripts/verify_daftar_outbound_sync.py
python3 scripts/verify_daftar_bidirectional_mutations.py
python3 scripts/verify_daftar_credit_limit_gateway.py
deno test supabase/functions/_shared/daftar_outbound/client_test.ts
deno check supabase/functions/daftar-sync/index.ts
deno check supabase/functions/daftar-outbound-sync/index.ts
deno check supabase/functions/daftar-credit-gateway/index.ts
```

After promotion, query only operational status via a read-only SQL file executed with `psql --set=ON_ERROR_STOP=1 --single-transaction --file ...` under a dedicated `ROLLBACK_AUDIT_DATABASE_URL` role that has SELECT only. Assert:

- account 28 source exists and `health_status = 'healthy'`;
- `sync_mode = 'zhirox_primary'`, inbound and outbound sync are enabled;
- no outbox event is stuck `processing` beyond its lease;
- failed/pending/blocked counts are reported but never deleted/retried by rollback;
- duplicate idempotency keys and duplicate remote mappings count zero;
- origin fields remain non-null for synchronized entities.

Create the SQL as an inline read-only query in the workflow and have the static verifier reject any keyword outside `SELECT`/CTEs. If a dedicated read-only URL is not configured, production rollback must block rather than reuse the service-role write credential.

- [ ] **Step 5: Verify the selected app and functions after promotion**

Download `user-update.json` and `active-release.json` again from `user-latest`, run `verify-promotion`, list/probe functions, and append exact results to `$GITHUB_STEP_SUMMARY`. A verification failure exits non-zero and explicitly prints the saved source release tag for a separate manual reverse rollback; it never auto-rolls forward/back.

- [ ] **Step 6: Run complete checks and commit**

```bash
python3 -m unittest -v scripts/rollback/test_release_bundle.py
python3 scripts/rollback/verify_workflows.py
python3 scripts/verify_auto_update.py
python3 scripts/verify_daftar_sync_lock.py
python3 scripts/verify_daftar_outbound_sync.py
python3 scripts/verify_daftar_bidirectional_mutations.py
python3 scripts/verify_daftar_credit_limit_gateway.py
```

Expected: all pass.

```bash
git add .github/workflows/manual-rollback.yml scripts/rollback/release_bundle.py scripts/rollback/test_release_bundle.py scripts/rollback/verify_workflows.py
git commit -m "feat(release): verify rollback and Daftar safety"
```

---

### Task 7: Make audit evidence complete and failure-safe

**Files:**
- Modify: `.github/workflows/manual-rollback.yml`
- Modify: `scripts/rollback/verify_workflows.py`
- Modify: `scripts/rollback/test_release_bundle.py`

**Interfaces:**
- Produces `rollback-audit.json`, `function-deployment-report.json`, `rollback-source-release.json`, and a GitHub step summary on every attempted production run.

- [ ] **Step 1: Add failing audit contract checks**

Require `if: always()` artifact upload and summary steps. Unit-test an `audit-record` CLI command that rejects missing actor/source/target/reason/run/checksum/compatibility/deployment/verification fields and writes canonical JSON with a SHA-256 `record_digest` computed over the record excluding the digest itself.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
python3 -m unittest -v scripts.rollback.test_release_bundle.AuditRecordTests
python3 scripts/rollback/verify_workflows.py
```

Expected: audit command/static requirements are missing.

- [ ] **Step 3: Implement canonical audit records**

Record actor, source/target tag+commit+build, reason, mode, workflow run ID/attempt, started/completed UTC timestamps, target metadata and IPA hashes, compatibility result, functions planned/deployed/kept, app promotion result, runtime verification, overall `succeeded|failed|rejected`, and failure stage. Serialize with `sort_keys=True`, separators `(',', ':')`, UTF-8, then calculate `record_digest`.

- [ ] **Step 4: Upload evidence and human-readable summary on every path**

Use `actions/upload-artifact@v4` with `if: always()`, `retention-days: 90`, `if-no-files-found: warn`. The summary must show active/target releases, compatibility, functions, IPA hash, whether promotion occurred, verification results, and exact reverse target. Never render secret values or full environment variables.

- [ ] **Step 5: Test rejected, partial, and successful fixtures**

Run the audit command against three checked-in-in-test temporary fixture dictionaries: authorization rejection, third-function deployment failure, and full success. Assert deterministic digest for identical content and a changed digest after any field mutation.

- [ ] **Step 6: Run checks and commit**

```bash
python3 -m unittest -v scripts/rollback/test_release_bundle.py
python3 scripts/rollback/verify_workflows.py
```

```bash
git add .github/workflows/manual-rollback.yml scripts/rollback/release_bundle.py scripts/rollback/test_release_bundle.py scripts/rollback/verify_workflows.py
git commit -m "feat(release): retain rollback audit evidence"
```

---

### Task 8: Rehearse dry-run, staging rollback, reverse rollback, and final regression

**Files:**
- Modify only if rehearsal exposes a defect in files from Tasks 1–7.

**Interfaces:**
- Consumes the completed release/capture/rollback workflows.
- Produces GitHub Actions evidence for a no-write dry-run, one-version staging rollback, and explicit roll-forward to the saved source release.

- [ ] **Step 1: Run local full regression before pushing**

```bash
python3 -m unittest -v scripts/rollback/test_release_bundle.py
python3 scripts/rollback/verify_workflows.py
python3 scripts/verify_auto_update.py
python3 scripts/verify_daftar_sync_lock.py
python3 scripts/verify_daftar_primary_inbound_sync.py
python3 scripts/verify_daftar_outbound_sync.py
python3 scripts/verify_daftar_bidirectional_mutations.py
python3 scripts/verify_daftar_credit_limit_gateway.py
deno test supabase/functions/_shared/daftar_outbound/client_test.ts
deno check supabase/functions/daftar-sync/index.ts
deno check supabase/functions/daftar-outbound-sync/index.ts
deno check supabase/functions/daftar-credit-gateway/index.ts
flutter analyze
flutter test
```

Expected: every command exits 0.

- [ ] **Step 2: Configure protected environments and least-privilege secrets**

In repository settings, require reviewer approval for `production-rollback`. Configure `staging-rollback` with a separate Supabase staging project and read-only audit DB role. Add `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`, and `ROLLBACK_AUDIT_DATABASE_URL` only to the relevant protected environment. Record reviewer/ruleset screenshots or URLs in the rehearsal run notes; do not commit values.

- [ ] **Step 3: Create two consecutive rollback-ready releases**

Dispatch/push the normal `user-source` workflow twice from known-good commits. For each, verify the immutable tag resolves to the metadata commit and the release has exactly the required five assets. Verify `rollback-index.json` orders the newest first and contains no more than five releases.

- [ ] **Step 4: Execute a repository-only dry-run**

Dispatch `manual-rollback.yml` with the previous retained tag, `mode=dry-run`, a reason of at least 12 characters, and `confirmation=ROLLBACK <tag>`. Expected: complete planned function/app actions, explicit `repository-only` live-state caveat, no Supabase deploy invocation, and unchanged `user-update.json`/`active-release.json` hashes.

- [ ] **Step 5: Perform staging rollback and verify**

Run production mode against `staging-rollback` first (temporarily parameterized only on a reviewed staging-only branch/workflow copy, never by accepting an arbitrary project input). Confirm protected approval, saved source release, function deployments with exact JWT flags, manifest promotion last, healthy function probes, and zero Daftar safety violations.

- [ ] **Step 6: Reverse staging rollback explicitly**

Dispatch a second manual rollback targeting the saved source tag. Confirm the source/target swap appears in audit evidence, active manifest returns to the source build/hash, and no database migration/data row was changed by either run.

- [ ] **Step 7: Exercise rejection paths**

Run dry-run attempts with wrong phrase, unretained tag, current active tag, a locally tampered downloaded asset in unit/integration fixture, simulated barrier, and unknown production function. Expected: all stop before function deployment and app promotion.

- [ ] **Step 8: Request review, fix findings, and run final verification**

Use the required `superpowers:requesting-code-review` skill. Re-run Step 1 after every review fix. Review must specifically inspect shell quoting, GitHub expression injection boundaries, token permissions, tar traversal, immutable-tag enforcement, app-promotion ordering, database non-mutation, and partial-failure evidence.

- [ ] **Step 9: Commit rehearsal-only fixes and evidence references**

If code changed:

```bash
git add .github/workflows/ios-unsigned-ipa.yml .github/workflows/manual-rollback.yml rollback scripts/rollback scripts/verify_auto_update.py
git commit -m "fix(release): harden rollback rehearsal findings"
```

Do not commit secrets, generated release bundles, downloaded IPA files, or database output containing customer data.

---

## Completion Gate

Implementation is complete only when:

- all Task 8 local regression commands pass from a clean execution worktree;
- two immutable rollback-ready releases exist and the moving index retains at most five;
- dry-run proves no-write behavior;
- staging rollback and explicit reverse rollback both succeed;
- the app manifest is promoted only after exact function deployment;
- production schema/data/outbox/origin values are not changed by rollback;
- every rejected/partial/successful run leaves audit evidence and the correct reverse tag;
- GitHub Environment protection is confirmed before enabling production use.
