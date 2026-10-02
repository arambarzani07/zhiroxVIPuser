-- Documentation marker migration for Daftar recovery hardening.
-- The functional migrations immediately before this file add:
-- 1) append-only recovery audit hash chain,
-- 2) service-role + system-owner break-glass authorization with a short-lived token,
-- 3) preflight recovery risk checks against Last Known Good snapshots,
-- 4) restore-drill/audit-chain guarding from the main Daftar guardian.
select 1;
