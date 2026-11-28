# VIP migration reconciliation checkpoint

This directory contains metadata only. The live database was restored from an established source, and the current Git migration sequence is not a complete replayable baseline. Do not execute or mark migrations applied based on this inventory.

- Live history: 19 versions; repository history: 14 versions; common version IDs: 0.
- The expiry patch in draft PR #55 is already applied in production. Its SQL body matches stored migration 20261128045515 after removal of explanatory comment lines and surrounding whitespace. Do not reapply to production.
- External database backup runs 45996118374, 45985348027 and 45805117122 failed. The current backup workflow requires an approved private repository and configured fresh backup credentials; never disable that guard or upload any database dump to this public repository.
- Prior restore/rehearsal workflows target an empty database, not current production. Do not dispatch those workflows against the live database.

## Replay requirements

1. Establish a verified encrypted backup in a separate approved private destination; verify authenticated decryption and archive integrity without exposing secrets.
2. Establish a separately provisioned, disposable test PostgreSQL/Supabase instance with zero production customer rows, no real service credentials, and outbound integrations disabled. No new paid project or branch without cost approval.
3. Obtain an approved schema-only baseline privately, review function bodies, extensions, roles, policies, triggers, storage definitions, and managed schemas; keep any embedded secrets out of Git. Record which historical changes are already incorporated.
4. Rehearse ordered migrations against the isolated baseline. Never use production URLs. Treat destructive/data backfill/cron/integration migrations separately and use synthetic fixtures.
5. Compare catalogs and ACLs, verify RLS, expiry guard, receipt ownership and portal smoke tests. Reconcile only proven migration versions; do not perform production migration repair on the basis of counts or hashes alone.
6. Keep PR #55 draft and production unchanged until replay evidence and backup recovery verification exist.

This checkpoint is not an executable schema dump, a database backup, or evidence of successful replay. No raw SQL or customer rows are exported here.
