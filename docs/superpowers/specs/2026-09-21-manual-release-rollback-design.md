# Manual Release Rollback Design

## Purpose

ZHIROX needs a safe operator-controlled way to return to a previously known-good release when a new version has an error or is not acceptable. Rollback must restore application code and Supabase Edge Functions without reversing database migrations or changing customer, debt, payment, sync, or audit data.

## Scope

The rollback system covers the `user-source` release line and restores:

- the selected release's application source/build inputs;
- the selected release's unsigned iOS IPA artifact and update manifest;
- the exact Supabase Edge Function sources and deployment settings recorded for that release.

It does not roll back:

- PostgreSQL migrations or schema versions;
- rows in Supabase, Daftar Qarz, outbox, mirror, audit, debt, payment, or customer tables;
- secrets, Vault entries, project identity, or the locked Daftar account-28 connection;
- historical data or sync checkpoints.

Only the five most recent rollback-ready releases are retained.

## Operating Model

Rollback is manual only. No warning, failed health check, CI failure, or runtime exception may initiate rollback without an explicit operator action.

Every successful release produces an immutable release bundle identified by a Git tag and commit SHA. The bundle contains:

1. release metadata and checksums;
2. the IPA and update manifest;
3. a manifest of every rollback-managed Edge Function, including function name, source paths, source checksums, entrypoint, and `verify_jwt` value;
4. the Git commit from which every artifact was built;
5. compatibility metadata stating the minimum database migration already required by that release.

A GitHub Actions `workflow_dispatch` workflow lists or accepts one of the retained release tags. The operator must type the selected tag and a confirmation phrase. The workflow rejects arbitrary commits, moving branches, unretained tags, incomplete bundles, and the currently active release.

## Release Capture

The normal release workflow gains a capture stage after all CI tests pass and before the release is marked rollback-ready.

The stage:

- builds the app once from the release commit;
- records artifact SHA-256 checksums;
- packages the managed Edge Function sources from the same commit;
- records current function deployment settings;
- creates an immutable Git tag and GitHub Release;
- uploads the release bundle;
- marks the release `rollback_ready=true` only after bundle validation succeeds;
- prunes rollback eligibility to the newest five releases without deleting Git history.

A release that fails capture or validation remains deployable only through the normal repair process and is not offered as a rollback target.

## Manual Rollback Flow

The rollback workflow executes these stages in order:

1. **Authorize** — require a manually entered retained tag and exact confirmation phrase.
2. **Validate bundle** — verify tag immutability, commit identity, required files, checksums, function list, and deployment settings.
3. **Compatibility check** — confirm that the current database migration level is at least the release's declared minimum and that the older application/functions can run against the current forward-only schema.
4. **Snapshot current release** — preserve the currently active app/function release identifier so the rollback itself can be reversed.
5. **Deploy functions** — deploy the selected release's managed Edge Functions with their recorded entrypoints and `verify_jwt` settings. Database migrations are never applied or reverted.
6. **Promote app artifact** — repoint the user update manifest/release channel to the selected IPA only after function deployment succeeds.
7. **Verify** — run app manifest checks, function health checks, Daftar inbound/outbound contract checks, sync health, and outbox safety checks.
8. **Record** — write a tamper-evident workflow summary containing actor, source release, target release, reason, timestamps, checksums, deployment results, and verification results.

The app artifact is promoted last so users cannot receive an older app while its matching functions are not yet active.

## Failure Handling

Rollback is fail-closed:

- A missing or invalid artifact stops before any deployment.
- A database compatibility failure stops before any deployment.
- A function deployment failure stops app promotion and leaves an explicit partial-deployment report.
- A post-deployment verification failure does not modify database data and does not silently select another version.
- Recovery from a partial rollback is another explicit manual rollback to the saved source release or another retained release.

The workflow must never run destructive Git commands, force-move release tags, reverse migrations, restore a database backup, delete production rows, clear the Daftar outbox, or rewrite sync origins.

## Database Compatibility

Database evolution remains forward-only. Migrations used by rollback-managed releases must follow additive compatibility rules for the five-release window:

- do not remove or rename a column/function still used by a retained release;
- introduce replacements before removing old interfaces;
- keep compatibility wrappers until every dependent release leaves the five-release window;
- identify an intentionally incompatible migration as a rollback barrier.

If a rollback barrier exists between the current and selected release, the workflow refuses the rollback and reports the exact barrier. It must not attempt an automatic database downgrade.

## Security and Permissions

- The workflow uses GitHub Environment protection for production.
- Only authorized repository operators may approve the production rollback job.
- Supabase credentials remain GitHub secrets and are never stored in release artifacts or logs.
- Release bundles contain source and metadata only, never secret values.
- Deployment permissions are scoped to the required repository release and Supabase function operations.
- Every attempt, including rejected attempts, is retained in GitHub Actions history.

## Managed Edge Functions

The first implementation derives the managed function list from the repository's Supabase function configuration and validates it against an explicit allowlist. At minimum, all production functions involved in authentication, account administration, Daftar sync, Daftar outbound sync, credit-limit gateway, live reads, notifications, and customer portals must be included when present in the selected release.

A function existing in production but absent from the selected release is not automatically deleted. The compatibility check must classify it as safe-to-keep or block rollback for operator review.

## Verification and Acceptance Criteria

The feature is complete only when automated tests prove:

- an unretained tag is rejected;
- a wrong confirmation phrase is rejected;
- a modified artifact or checksum mismatch is rejected;
- an incompatible database migration blocks rollback before deployment;
- the selected functions are deployed with recorded JWT settings;
- app promotion occurs only after all function deployments succeed;
- no database migration or data mutation command is present in the rollback path;
- the current release identifier is saved for a reverse rollback;
- only the newest five validated releases are offered;
- the existing Daftar sync, outbound idempotency, origin tracking, retry, and duplicate protection tests continue to pass;
- a dry-run produces the complete intended action list without changing production;
- a controlled staging rehearsal can roll back one version and then roll forward to the saved release.

## Operator Experience

The GitHub Actions form asks for:

- target release tag;
- rollback reason;
- dry-run or production mode;
- exact confirmation phrase for production.

The workflow summary shows the active release, target release, compatibility result, affected functions, IPA checksum, verification results, and the exact release tag needed to reverse the rollback.

## Non-Goals

- automatic rollback;
- database point-in-time recovery;
- historical data backfill;
- modifying Daftar Qarz records during rollback;
- rolling back only one arbitrary file or one database row;
- retaining more than five rollback-ready releases.
