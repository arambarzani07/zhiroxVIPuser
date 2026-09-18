-- Platform release rollout policy.
-- Adds staged rollout and minimum supported build controls per app edition.

alter table public.app_update_settings
  add column if not exists rollout_percent integer not null default 100
    check (rollout_percent between 0 and 100),
  add column if not exists minimum_build integer not null default 0
    check (minimum_build >= 0);

revoke update on table public.app_update_settings from authenticated;
grant update (
  mandatory,
  notes,
  rollout_percent,
  minimum_build,
  updated_at,
  updated_by
) on table public.app_update_settings to authenticated;
