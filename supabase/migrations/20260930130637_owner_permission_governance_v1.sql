-- Owner permission governance v1.
-- Platform metadata/control only; normal Owner permissions must not expose
-- customer debt, payment, receipt, or private-note business content.

create schema if not exists private;

create table if not exists private.owner_permission_catalog (
  permission_key text primary key
    check (permission_key ~ '^owner_[a-z0-9_]+$'),
  label text not null,
  group_key text not null,
  group_label text not null,
  risk_level smallint not null check (risk_level between 1 and 4),
  scopes text[] not null check (
    cardinality(scopes) > 0
    and scopes <@ ARRAY['platform','market','admin']::text[]
  ),
  requires_reason boolean not null default false,
  requires_reauth boolean not null default false,
  requires_typed_confirmation boolean not null default false,
  requires_two_person_approval boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (risk_level < 3 or (requires_reason and requires_reauth)),
  check (risk_level < 4 or (requires_typed_confirmation and requires_two_person_approval))
);

create table if not exists private.owner_permission_principals (
  owner_id uuid primary key references public.profiles(id) on delete cascade,
  permission_mode text not null default 'full'
    check (permission_mode in ('full','restricted')),
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists private.owner_permission_grants (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  permission_key text not null
    references private.owner_permission_catalog(permission_key) on delete cascade,
  scope_type text not null check (scope_type in ('platform','market','admin')),
  scope_id uuid,
  allowed boolean not null,
  expires_at timestamptz,
  reason text not null default '',
  granted_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (scope_type = 'platform' and scope_id is null)
    or scope_type in ('market','admin')
  )
);

create unique index if not exists owner_permission_grants_unique_scope
  on private.owner_permission_grants (
    owner_id,
    permission_key,
    scope_type,
    coalesce(scope_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

create index if not exists owner_permission_grants_lookup
  on private.owner_permission_grants (owner_id, permission_key, scope_type, scope_id, expires_at);

create table if not exists private.owner_permission_audit (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references public.profiles(id) on delete restrict,
  target_owner_id uuid references public.profiles(id) on delete set null,
  permission_key text references private.owner_permission_catalog(permission_key) on delete set null,
  scope_type text not null default 'platform'
    check (scope_type in ('platform','market','admin')),
  scope_id uuid,
  action text not null,
  before_state jsonb not null default '{}'::jsonb,
  after_state jsonb not null default '{}'::jsonb,
  reason text not null default '',
  risk_level smallint not null default 1 check (risk_level between 1 and 4),
  request_id uuid not null default gen_random_uuid(),
  created_at timestamptz not null default now()
);

alter table private.owner_permission_catalog enable row level security;
alter table private.owner_permission_principals enable row level security;
alter table private.owner_permission_grants enable row level security;
alter table private.owner_permission_audit enable row level security;

revoke all on table private.owner_permission_catalog from public, anon, authenticated;
revoke all on table private.owner_permission_principals from public, anon, authenticated;
revoke all on table private.owner_permission_grants from public, anon, authenticated;
revoke all on table private.owner_permission_audit from public, anon, authenticated;

grant select, insert, update, delete on table private.owner_permission_catalog to service_role;
grant select, insert, update, delete on table private.owner_permission_principals to service_role;
grant select, insert, update, delete on table private.owner_permission_grants to service_role;
grant select, insert, update, delete on table private.owner_permission_audit to service_role;

insert into private.owner_permission_catalog (
  permission_key, label, group_key, group_label, risk_level, scopes,
  requires_reason, requires_reauth, requires_typed_confirmation,
  requires_two_person_approval, active
) values
('owner_access_console', 'چوونە ناو کۆنترۆڵی Owner', 'core', 'بنەڕەتی Owner', 1, ARRAY['platform']::text[], false, false, false, false, true),
('owner_view_platform_dashboard', 'بینینی داشبۆردی پلاتفۆرم', 'core', 'بنەڕەتی Owner', 1, ARRAY['platform']::text[], false, false, false, false, true),
('owner_view_platform_metrics', 'بینینی پێوانەکانی پلاتفۆرم', 'core', 'بنەڕەتی Owner', 1, ARRAY['platform']::text[], false, false, false, false, true),
('owner_view_all_markets', 'بینینی هەموو مارکێتەکان', 'core', 'بنەڕەتی Owner', 1, ARRAY['platform']::text[], false, false, false, false, true),
('owner_view_all_admins', 'بینینی هەموو بەڕێوەبەران', 'core', 'بنەڕەتی Owner', 1, ARRAY['platform']::text[], false, false, false, false, true),
('owner_search_markets', 'گەڕان لە مارکێتەکان', 'core', 'بنەڕەتی Owner', 1, ARRAY['platform']::text[], false, false, false, false, true),
('owner_search_admins', 'گەڕان لە بەڕێوەبەران', 'core', 'بنەڕەتی Owner', 1, ARRAY['platform']::text[], false, false, false, false, true),
('owner_view_platform_activity', 'بینینی چالاکی پلاتفۆرم', 'core', 'بنەڕەتی Owner', 1, ARRAY['platform']::text[], false, false, false, false, true),
('owner_create_admin', 'دروستکردنی بەڕێوەبەر', 'admin_accounts', 'هەژماری بەڕێوەبەر', 2, ARRAY['admin']::text[], false, false, false, false, true),
('owner_view_admin_profile', 'بینینی پڕۆفایلی بەڕێوەبەر', 'admin_accounts', 'هەژماری بەڕێوەبەر', 1, ARRAY['admin']::text[], false, false, false, false, true),
('owner_edit_admin_name', 'گۆڕینی ناوی بەڕێوەبەر', 'admin_accounts', 'هەژماری بەڕێوەبەر', 2, ARRAY['admin']::text[], false, false, false, false, true),
('owner_edit_admin_phone', 'گۆڕینی ژمارەی بەڕێوەبەر', 'admin_accounts', 'هەژماری بەڕێوەبەر', 2, ARRAY['admin']::text[], false, false, false, false, true),
('owner_edit_admin_email', 'گۆڕینی ئیمەیڵی بەڕێوەبەر', 'admin_accounts', 'هەژماری بەڕێوەبەر', 2, ARRAY['admin']::text[], false, false, false, false, true),
('owner_change_admin_market', 'گواستنەوەی بەڕێوەبەر بۆ مارکێتی تر', 'admin_accounts', 'هەژماری بەڕێوەبەر', 3, ARRAY['admin']::text[], true, true, false, false, true),
('owner_reset_admin_password', 'ڕێکخستنەوەی وشەی نهێنی بەڕێوەبەر', 'admin_accounts', 'هەژماری بەڕێوەبەر', 3, ARRAY['admin']::text[], true, true, false, false, true),
('owner_force_admin_password_change', 'ناچارکردنی گۆڕینی وشەی نهێنی', 'admin_accounts', 'هەژماری بەڕێوەبەر', 2, ARRAY['admin']::text[], false, false, false, false, true),
('owner_lock_admin_login', 'قوفڵکردنی چوونەژوورەوەی بەڕێوەبەر', 'admin_accounts', 'هەژماری بەڕێوەبەر', 3, ARRAY['admin']::text[], true, true, false, false, true),
('owner_unlock_admin_login', 'کردنەوەی قوفڵی چوونەژوورەوە', 'admin_accounts', 'هەژماری بەڕێوەبەر', 3, ARRAY['admin']::text[], true, true, false, false, true),
('owner_suspend_admin', 'ڕاگرتنی هەژماری بەڕێوەبەر', 'admin_accounts', 'هەژماری بەڕێوەبەر', 3, ARRAY['admin']::text[], true, true, false, false, true),
('owner_activate_admin', 'چالاککردنەوەی بەڕێوەبەر', 'admin_accounts', 'هەژماری بەڕێوەبەر', 2, ARRAY['admin']::text[], false, false, false, false, true),
('owner_archive_admin', 'ئەرشیڤکردنی بەڕێوەبەر', 'admin_accounts', 'هەژماری بەڕێوەبەر', 3, ARRAY['admin']::text[], true, true, false, false, true),
('owner_restore_admin', 'گەڕاندنەوەی بەڕێوەبەر', 'admin_accounts', 'هەژماری بەڕێوەبەر', 3, ARRAY['admin']::text[], true, true, false, false, true),
('owner_delete_admin', 'سڕینەوەی کۆتایی بەڕێوەبەر', 'admin_accounts', 'هەژماری بەڕێوەبەر', 4, ARRAY['admin']::text[], true, true, true, true, true),
('owner_view_admin_last_login', 'بینینی کۆتا چوونەژوورەوە', 'admin_accounts', 'هەژماری بەڕێوەبەر', 1, ARRAY['admin']::text[], false, false, false, false, true),
('owner_view_admin_login_history', 'بینینی مێژووی چوونەژوورەوە', 'admin_accounts', 'هەژماری بەڕێوەبەر', 1, ARRAY['admin']::text[], false, false, false, false, true),
('owner_view_admin_devices', 'بینینی ئامێرەکانی بەڕێوەبەر', 'admin_accounts', 'هەژماری بەڕێوەبەر', 1, ARRAY['admin']::text[], false, false, false, false, true),
('owner_revoke_admin_device', 'لابردنی مۆڵەتی ئامێری بەڕێوەبەر', 'admin_accounts', 'هەژماری بەڕێوەبەر', 3, ARRAY['admin']::text[], true, true, false, false, true),
('owner_revoke_admin_sessions', 'دەرکردنی بەڕێوەبەر لە هەموو session ـەکان', 'admin_accounts', 'هەژماری بەڕێوەبەر', 3, ARRAY['admin']::text[], true, true, false, false, true),
('owner_verify_admin', 'پشتڕاستکردنەوەی بەڕێوەبەر', 'admin_accounts', 'هەژماری بەڕێوەبەر', 2, ARRAY['admin']::text[], false, false, false, false, true),
('owner_revoke_admin_verification', 'لابردنی پشتڕاستکردنەوە', 'admin_accounts', 'هەژماری بەڕێوەبەر', 3, ARRAY['admin']::text[], true, true, false, false, true),
('owner_view_admin_status', 'بینینی دۆخی بەڕێوەبەر', 'admin_accounts', 'هەژماری بەڕێوەبەر', 1, ARRAY['admin']::text[], false, false, false, false, true),
('owner_add_admin_internal_note', 'زیادکردنی تێبینی ناوخۆ بۆ بەڕێوەبەر', 'admin_accounts', 'هەژماری بەڕێوەبەر', 2, ARRAY['admin']::text[], false, false, false, false, true),
('owner_create_market', 'دروستکردنی مارکێت', 'market_identity', 'ناسنامەی مارکێت', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_view_market_profile', 'بینینی پڕۆفایلی مارکێت', 'market_identity', 'ناسنامەی مارکێت', 1, ARRAY['market']::text[], false, false, false, false, true),
('owner_edit_market_name', 'گۆڕینی ناوی مارکێت', 'market_identity', 'ناسنامەی مارکێت', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_edit_market_code', 'گۆڕینی کۆدی مارکێت', 'market_identity', 'ناسنامەی مارکێت', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_edit_market_phone', 'گۆڕینی ژمارەی مارکێت', 'market_identity', 'ناسنامەی مارکێت', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_edit_market_address', 'گۆڕینی ناونیشانی مارکێت', 'market_identity', 'ناسنامەی مارکێت', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_edit_market_region', 'گۆڕینی ناوچەی مارکێت', 'market_identity', 'ناسنامەی مارکێت', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_edit_market_timezone', 'گۆڕینی timezone ـی مارکێت', 'market_identity', 'ناسنامەی مارکێت', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_edit_market_currency', 'گۆڕینی دراوی بنەڕەتی مارکێت', 'market_identity', 'ناسنامەی مارکێت', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_change_primary_admin', 'گۆڕینی بەڕێوەبەری سەرەکی', 'market_identity', 'ناسنامەی مارکێت', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_add_secondary_admin', 'زیادکردنی بەڕێوەبەری دووەم', 'market_identity', 'ناسنامەی مارکێت', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_remove_secondary_admin', 'لابردنی بەڕێوەبەری دووەم', 'market_identity', 'ناسنامەی مارکێت', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_transfer_market', 'گواستنەوەی خاوەندارێتی مارکێت', 'market_identity', 'ناسنامەی مارکێت', 4, ARRAY['market']::text[], true, true, true, true, true),
('owner_merge_market', 'یەکخستنی دوو هەژماری مارکێت', 'market_identity', 'ناسنامەی مارکێت', 4, ARRAY['market']::text[], true, true, true, true, true),
('owner_split_market', 'جیاکردنەوەی هەژماری مارکێت', 'market_identity', 'ناسنامەی مارکێت', 4, ARRAY['market']::text[], true, true, true, true, true),
('owner_set_market_metadata', 'گۆڕینی metadata ـی مارکێت', 'market_identity', 'ناسنامەی مارکێت', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_market_tags', 'دانانی tag بۆ مارکێت', 'market_identity', 'ناسنامەی مارکێت', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_market_priority', 'دانانی ئاستی پێشەنگی مارکێت', 'market_identity', 'ناسنامەی مارکێت', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_market_trial', 'خستنە دۆخی تاقیکردنەوە', 'market_lifecycle', 'دۆخی ژیانی مارکێت', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_activate_market', 'چالاککردنی مارکێت', 'market_lifecycle', 'دۆخی ژیانی مارکێت', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_market_grace', 'دانانی ماوەی Grace', 'market_lifecycle', 'دۆخی ژیانی مارکێت', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_suspend_market', 'ڕاگرتنی مارکێت', 'market_lifecycle', 'دۆخی ژیانی مارکێت', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_resume_market', 'دەستپێکردنەوەی مارکێت', 'market_lifecycle', 'دۆخی ژیانی مارکێت', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_archive_market', 'ئەرشیڤکردنی مارکێت', 'market_lifecycle', 'دۆخی ژیانی مارکێت', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_restore_market', 'گەڕاندنەوەی مارکێت', 'market_lifecycle', 'دۆخی ژیانی مارکێت', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_close_market', 'داخستنی مارکێت', 'market_lifecycle', 'دۆخی ژیانی مارکێت', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_delete_market', 'سڕینەوەی کۆتایی مارکێت', 'market_lifecycle', 'دۆخی ژیانی مارکێت', 4, ARRAY['market']::text[], true, true, true, true, true),
('owner_enable_market_read_only', 'خستنە دۆخی تەنها-خوێندنەوە', 'market_lifecycle', 'دۆخی ژیانی مارکێت', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_disable_market_read_only', 'لابردنی دۆخی تەنها-خوێندنەوە', 'market_lifecycle', 'دۆخی ژیانی مارکێت', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_enable_market_maintenance', 'چالاککردنی maintenance بۆ مارکێت', 'market_lifecycle', 'دۆخی ژیانی مارکێت', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_disable_market_maintenance', 'ناچالاککردنی maintenance', 'market_lifecycle', 'دۆخی ژیانی مارکێت', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_emergency_freeze_market', 'قوفڵکردنی فریاکەوتنی مارکێت', 'market_lifecycle', 'دۆخی ژیانی مارکێت', 4, ARRAY['market']::text[], true, true, true, true, true),
('owner_emergency_unfreeze_market', 'کردنەوەی قوفڵی فریاکەوتن', 'market_lifecycle', 'دۆخی ژیانی مارکێت', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_schedule_market_shutdown', 'خشتەکردنی داخستنی مارکێت', 'market_lifecycle', 'دۆخی ژیانی مارکێت', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_view_subscription', 'بینینی بەشداری', 'subscription', 'بەشداری و پارەدان', 1, ARRAY['market']::text[], false, false, false, false, true),
('owner_create_subscription', 'دروستکردنی بەشداری', 'subscription', 'بەشداری و پارەدان', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_change_subscription_plan', 'گۆڕینی پلانی بەشداری', 'subscription', 'بەشداری و پارەدان', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_renew_subscription', 'نوێکردنەوەی بەشداری', 'subscription', 'بەشداری و پارەدان', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_extend_subscription_days', 'زیادکردنی ڕۆژی بەشداری', 'subscription', 'بەشداری و پارەدان', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_reduce_subscription_days', 'کەمکردنەوەی ڕۆژی بەشداری', 'subscription', 'بەشداری و پارەدان', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_pause_subscription', 'وەستاندنی بەشداری', 'subscription', 'بەشداری و پارەدان', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_resume_subscription', 'دەستپێکردنەوەی بەشداری', 'subscription', 'بەشداری و پارەدان', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_cancel_subscription', 'هەڵوەشاندنەوەی بەشداری', 'subscription', 'بەشداری و پارەدان', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_set_custom_expiry', 'دانانی بەرواری کۆتایی تایبەت', 'subscription', 'بەشداری و پارەدان', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_grant_trial', 'پێدانی trial', 'subscription', 'بەشداری و پارەدان', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_grant_free_period', 'پێدانی ماوەی بەخۆڕایی', 'subscription', 'بەشداری و پارەدان', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_override_plan_price', 'گۆڕینی نرخی پلان بۆ مارکێت', 'subscription', 'بەشداری و پارەدان', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_apply_subscription_discount', 'دانانی داشکاندن', 'subscription', 'بەشداری و پارەدان', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_remove_subscription_discount', 'لابردنی داشکاندن', 'subscription', 'بەشداری و پارەدان', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_enable_auto_renew', 'چالاککردنی نوێکردنەوەی خۆکار', 'subscription', 'بەشداری و پارەدان', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_disable_auto_renew', 'ناچالاککردنی نوێکردنەوەی خۆکار', 'subscription', 'بەشداری و پارەدان', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_view_billing_history', 'بینینی مێژووی پارەدان', 'subscription', 'بەشداری و پارەدان', 1, ARRAY['market']::text[], false, false, false, false, true),
('owner_view_subscription_history', 'بینینی مێژووی بەشداری', 'subscription', 'بەشداری و پارەدان', 1, ARRAY['market']::text[], false, false, false, false, true),
('owner_correct_subscription_error', 'چاککردنەوەی هەڵەی بەشداری', 'subscription', 'بەشداری و پارەدان', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_set_employee_limit', 'دانانی سنووری کارمەند', 'resource_limits', 'سنوورەکانی سەرچاوە', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_device_limit', 'دانانی سنووری ئامێر', 'resource_limits', 'سنوورەکانی سەرچاوە', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_customer_limit', 'دانانی سنووری کڕیار', 'resource_limits', 'سنوورەکانی سەرچاوە', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_storage_limit', 'دانانی سنووری storage', 'resource_limits', 'سنوورەکانی سەرچاوە', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_attachment_limit', 'دانانی سنووری هاوپێچ', 'resource_limits', 'سنوورەکانی سەرچاوە', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_backup_limit', 'دانانی سنووری backup', 'resource_limits', 'سنوورەکانی سەرچاوە', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_backup_retention', 'دانانی ماوەی هەڵگرتنی backup', 'resource_limits', 'سنوورەکانی سەرچاوە', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_export_limit', 'دانانی سنووری export', 'resource_limits', 'سنوورەکانی سەرچاوە', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_notification_limit', 'دانانی سنووری notification', 'resource_limits', 'سنوورەکانی سەرچاوە', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_sms_limit', 'دانانی سنووری SMS', 'resource_limits', 'سنوورەکانی سەرچاوە', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_api_request_limit', 'دانانی سنووری API', 'resource_limits', 'سنوورەکانی سەرچاوە', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_webhook_limit', 'دانانی سنووری webhook', 'resource_limits', 'سنوورەکانی سەرچاوە', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_active_session_limit', 'دانانی سنووری session', 'resource_limits', 'سنوورەکانی سەرچاوە', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_receipt_limit', 'دانانی سنووری پسوولە', 'resource_limits', 'سنوورەکانی سەرچاوە', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_sync_job_limit', 'دانانی سنووری sync job', 'resource_limits', 'سنوورەکانی سەرچاوە', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_file_upload_limit', 'دانانی سنووری upload', 'resource_limits', 'سنوورەکانی سەرچاوە', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_audit_retention', 'دانانی ماوەی audit', 'resource_limits', 'سنوورەکانی سەرچاوە', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_reset_market_limits', 'گەڕاندنەوەی سنوورەکان بۆ بنەڕەت', 'resource_limits', 'سنوورەکانی سەرچاوە', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_view_feature_catalog', 'بینینی کاتەلۆگی تایبەتمەندی', 'feature_entitlements', 'دەسەڵاتی تایبەتمەندی', 1, ARRAY['market']::text[], false, false, false, false, true),
('owner_enable_market_feature', 'چالاککردنی تایبەتمەندی بۆ مارکێت', 'feature_entitlements', 'دەسەڵاتی تایبەتمەندی', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_disable_market_feature', 'ناچالاککردنی تایبەتمەندی بۆ مارکێت', 'feature_entitlements', 'دەسەڵاتی تایبەتمەندی', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_inherit_market_feature', 'شوێنکەوتنی تایبەتمەندی لە پلان', 'feature_entitlements', 'دەسەڵاتی تایبەتمەندی', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_override_market_feature', 'override ـی تایبەتمەندی مارکێت', 'feature_entitlements', 'دەسەڵاتی تایبەتمەندی', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_clear_feature_override', 'لابردنی override', 'feature_entitlements', 'دەسەڵاتی تایبەتمەندی', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_edit_standard_plan_features', 'گۆڕینی تایبەتمەندی پلانی Standard', 'feature_entitlements', 'دەسەڵاتی تایبەتمەندی', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_edit_pro_plan_features', 'گۆڕینی تایبەتمەندی پلانی Pro', 'feature_entitlements', 'دەسەڵاتی تایبەتمەندی', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_edit_vip_plan_features', 'گۆڕینی تایبەتمەندی پلانی VIP', 'feature_entitlements', 'دەسەڵاتی تایبەتمەندی', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_create_feature', 'دروستکردنی تایبەتمەندی', 'feature_entitlements', 'دەسەڵاتی تایبەتمەندی', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_deprecate_feature', 'کۆنکردنەوەی تایبەتمەندی', 'feature_entitlements', 'دەسەڵاتی تایبەتمەندی', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_enable_feature_globally', 'چالاککردنی تایبەتمەندی بۆ هەمووان', 'feature_entitlements', 'دەسەڵاتی تایبەتمەندی', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_disable_feature_globally', 'ناچالاککردنی تایبەتمەندی بۆ هەمووان', 'feature_entitlements', 'دەسەڵاتی تایبەتمەندی', 4, ARRAY['market']::text[], true, true, true, true, true),
('owner_set_feature_rollout', 'دانانی rollout ـی تایبەتمەندی', 'feature_entitlements', 'دەسەڵاتی تایبەتمەندی', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_view_feature_history', 'بینینی مێژووی تایبەتمەندی', 'feature_entitlements', 'دەسەڵاتی تایبەتمەندی', 1, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_market_feature_plan', 'دانانی پلانی تایبەتمەندی مارکێت', 'feature_entitlements', 'دەسەڵاتی تایبەتمەندی', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_copy_feature_profile', 'کۆپیکردنی پڕۆفایلی تایبەتمەندی', 'feature_entitlements', 'دەسەڵاتی تایبەتمەندی', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_reset_feature_profile', 'گەڕاندنەوەی پڕۆفایلی تایبەتمەندی', 'feature_entitlements', 'دەسەڵاتی تایبەتمەندی', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_view_security_dashboard', 'بینینی داشبۆردی ئاسایش', 'security', 'ئاسایش', 1, ARRAY['admin','market']::text[], false, false, false, false, true),
('owner_view_active_sessions', 'بینینی session ـە چالاکەکان', 'security', 'ئاسایش', 1, ARRAY['admin','market']::text[], false, false, false, false, true),
('owner_revoke_session', 'هەڵوەشاندنەوەی session', 'security', 'ئاسایش', 3, ARRAY['admin','market']::text[], true, true, false, false, true),
('owner_revoke_all_sessions', 'هەڵوەشاندنەوەی هەموو session ـەکان', 'security', 'ئاسایش', 3, ARRAY['admin','market']::text[], true, true, false, false, true),
('owner_view_devices', 'بینینی ئامێرەکان', 'security', 'ئاسایش', 1, ARRAY['admin','market']::text[], false, false, false, false, true),
('owner_block_device', 'بلۆککردنی ئامێر', 'security', 'ئاسایش', 3, ARRAY['admin','market']::text[], true, true, false, false, true),
('owner_unblock_device', 'لابردنی بلۆکی ئامێر', 'security', 'ئاسایش', 3, ARRAY['admin','market']::text[], true, true, false, false, true),
('owner_require_password_reset', 'ناچارکردنی reset ـی وشەی نهێنی', 'security', 'ئاسایش', 3, ARRAY['admin','market']::text[], true, true, false, false, true),
('owner_require_2fa', 'ناچارکردنی 2FA', 'security', 'ئاسایش', 3, ARRAY['admin','market']::text[], true, true, false, false, true),
('owner_disable_2fa', 'ناچالاککردنی 2FA', 'security', 'ئاسایش', 3, ARRAY['admin','market']::text[], true, true, false, false, true),
('owner_set_session_timeout', 'دانانی session timeout', 'security', 'ئاسایش', 2, ARRAY['admin','market']::text[], false, false, false, false, true),
('owner_set_login_attempt_limit', 'دانانی سنووری هەوڵی login', 'security', 'ئاسایش', 2, ARRAY['admin','market']::text[], false, false, false, false, true),
('owner_lock_suspicious_account', 'قوفڵکردنی هەژماری گومانلێکراو', 'security', 'ئاسایش', 3, ARRAY['admin','market']::text[], true, true, false, false, true),
('owner_unlock_suspicious_account', 'کردنەوەی قوفڵی هەژماری گومانلێکراو', 'security', 'ئاسایش', 3, ARRAY['admin','market']::text[], true, true, false, false, true),
('owner_view_security_incidents', 'بینینی ڕووداوە ئاسایشییەکان', 'security', 'ئاسایش', 1, ARRAY['admin','market']::text[], false, false, false, false, true),
('owner_resolve_security_incident', 'چارەسەرکردنی ڕووداوی ئاسایشی', 'security', 'ئاسایش', 2, ARRAY['admin','market']::text[], false, false, false, false, true),
('owner_rotate_market_api_key', 'گۆڕینی API key ـی مارکێت', 'security', 'ئاسایش', 3, ARRAY['admin','market']::text[], true, true, false, false, true),
('owner_revoke_market_api_key', 'هەڵوەشاندنەوەی API key', 'security', 'ئاسایش', 3, ARRAY['admin','market']::text[], true, true, false, false, true),
('owner_rotate_market_secret', 'گۆڕینی secret ـی مارکێت', 'security', 'ئاسایش', 4, ARRAY['admin','market']::text[], true, true, true, true, true),
('owner_view_security_history', 'بینینی مێژووی ئاسایش', 'security', 'ئاسایش', 1, ARRAY['admin','market']::text[], false, false, false, false, true),
('owner_set_support_standard', 'دانانی پشتیوانی Standard', 'support', 'پشتیوانی', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_support_priority', 'دانانی پشتیوانی Priority', 'support', 'پشتیوانی', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_support_vip', 'دانانی پشتیوانی VIP', 'support', 'پشتیوانی', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_assign_support_agent', 'دیاریکردنی ئەجێنتی پشتیوانی', 'support', 'پشتیوانی', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_add_internal_support_note', 'زیادکردنی تێبینی پشتیوانی', 'support', 'پشتیوانی', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_view_support_history', 'بینینی مێژووی پشتیوانی', 'support', 'پشتیوانی', 1, ARRAY['market']::text[], false, false, false, false, true),
('owner_mark_market_high_priority', 'خستنە پێشەنگی بەرز', 'support', 'پشتیوانی', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_set_support_sla', 'دانانی SLA', 'support', 'پشتیوانی', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_open_support_case', 'کردنەوەی کەیسی پشتیوانی', 'support', 'پشتیوانی', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_close_support_case', 'داخستنی کەیسی پشتیوانی', 'support', 'پشتیوانی', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_view_backup_health', 'بینینی تەندروستی backup', 'backup_recovery', 'Backup و Recovery', 1, ARRAY['platform']::text[], false, false, false, false, true),
('owner_view_market_backups', 'بینینی backup ـەکانی مارکێت', 'backup_recovery', 'Backup و Recovery', 1, ARRAY['market']::text[], false, false, false, false, true),
('owner_trigger_market_backup', 'دەستپێکردنی backup ـی مارکێت', 'backup_recovery', 'Backup و Recovery', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_trigger_platform_backup', 'دەستپێکردنی backup ـی پلاتفۆرم', 'backup_recovery', 'Backup و Recovery', 3, ARRAY['platform']::text[], true, true, false, false, true),
('owner_download_backup', 'داگرتنی backup', 'backup_recovery', 'Backup و Recovery', 2, ARRAY['platform']::text[], false, false, false, false, true),
('owner_verify_backup', 'پشتڕاستکردنەوەی backup', 'backup_recovery', 'Backup و Recovery', 2, ARRAY['platform']::text[], false, false, false, false, true),
('owner_restore_market_backup', 'restore ـی backup ـی مارکێت', 'backup_recovery', 'Backup و Recovery', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_restore_platform_backup', 'restore ـی backup ـی پلاتفۆرم', 'backup_recovery', 'Backup و Recovery', 4, ARRAY['platform']::text[], true, true, true, true, true),
('owner_delete_backup', 'سڕینەوەی backup', 'backup_recovery', 'Backup و Recovery', 3, ARRAY['platform']::text[], true, true, false, false, true),
('owner_change_backup_retention', 'گۆڕینی ماوەی هەڵگرتنی backup', 'backup_recovery', 'Backup و Recovery', 2, ARRAY['platform']::text[], false, false, false, false, true),
('owner_start_disaster_recovery', 'دەستپێکردنی disaster recovery', 'backup_recovery', 'Backup و Recovery', 4, ARRAY['platform']::text[], true, true, true, true, true),
('owner_stop_disaster_recovery', 'وەستاندنی disaster recovery', 'backup_recovery', 'Backup و Recovery', 3, ARRAY['platform']::text[], true, true, false, false, true),
('owner_view_sync_health', 'بینینی تەندروستی sync', 'sync_integration', 'Sync و Integration', 1, ARRAY['market']::text[], false, false, false, false, true),
('owner_view_sync_failures', 'بینینی sync ـە شکستخواردووەکان', 'sync_integration', 'Sync و Integration', 1, ARRAY['market']::text[], false, false, false, false, true),
('owner_pause_sync', 'وەستاندنی sync', 'sync_integration', 'Sync و Integration', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_resume_sync', 'دەستپێکردنەوەی sync', 'sync_integration', 'Sync و Integration', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_retry_sync', 'دووبارەکردنەوەی sync', 'sync_integration', 'Sync و Integration', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_clear_failed_sync_queue', 'پاککردنەوەی ڕیزی sync ـی شکستخواردوو', 'sync_integration', 'Sync و Integration', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_view_integrations', 'بینینی integration ـەکان', 'sync_integration', 'Sync و Integration', 1, ARRAY['market']::text[], false, false, false, false, true),
('owner_enable_integration', 'چالاککردنی integration', 'sync_integration', 'Sync و Integration', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_disable_integration', 'ناچالاککردنی integration', 'sync_integration', 'Sync و Integration', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_view_webhooks', 'بینینی webhook ـەکان', 'sync_integration', 'Sync و Integration', 1, ARRAY['market']::text[], false, false, false, false, true),
('owner_retry_webhook', 'دووبارەکردنەوەی webhook', 'sync_integration', 'Sync و Integration', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_disable_webhook', 'ناچالاککردنی webhook', 'sync_integration', 'Sync و Integration', 3, ARRAY['market']::text[], true, true, false, false, true),
('owner_rotate_integration_secret', 'گۆڕینی secret ـی integration', 'sync_integration', 'Sync و Integration', 4, ARRAY['market']::text[], true, true, true, true, true),
('owner_test_integration', 'تاقیکردنەوەی integration', 'sync_integration', 'Sync و Integration', 2, ARRAY['market']::text[], false, false, false, false, true),
('owner_view_app_versions', 'بینینی وەشانەکانی ئەپ', 'app_version', 'وەشان و Update', 1, ARRAY['platform']::text[], false, false, false, false, true),
('owner_set_minimum_app_version', 'دانانی کەمترین وەشانی ڕێگەپێدراو', 'app_version', 'وەشان و Update', 2, ARRAY['platform']::text[], false, false, false, false, true),
('owner_force_app_update', 'ناچارکردنی app update', 'app_version', 'وەشان و Update', 4, ARRAY['platform']::text[], true, true, true, true, true),
('owner_disable_forced_update', 'لابردنی forced update', 'app_version', 'وەشان و Update', 3, ARRAY['platform']::text[], true, true, false, false, true),
('owner_block_old_app_version', 'بلۆککردنی وەشانی کۆن', 'app_version', 'وەشان و Update', 3, ARRAY['platform']::text[], true, true, false, false, true),
('owner_allow_old_app_version', 'ڕێگەدان بە وەشانی کۆن', 'app_version', 'وەشان و Update', 2, ARRAY['platform']::text[], false, false, false, false, true),
('owner_publish_update_message', 'بڵاوکردنەوەی پەیامی update', 'app_version', 'وەشان و Update', 2, ARRAY['platform']::text[], false, false, false, false, true),
('owner_set_update_deadline', 'دانانی دواوادەی update', 'app_version', 'وەشان و Update', 2, ARRAY['platform']::text[], false, false, false, false, true),
('owner_view_backend_health', 'بینینی تەندروستی backend', 'platform_health', 'تەندروستی پلاتفۆرم', 1, ARRAY['platform']::text[], false, false, false, false, true),
('owner_view_database_health', 'بینینی تەندروستی database', 'platform_health', 'تەندروستی پلاتفۆرم', 1, ARRAY['platform']::text[], false, false, false, false, true),
('owner_view_edge_function_health', 'بینینی تەندروستی Edge Functions', 'platform_health', 'تەندروستی پلاتفۆرم', 1, ARRAY['platform']::text[], false, false, false, false, true),
('owner_view_storage_health', 'بینینی تەندروستی storage', 'platform_health', 'تەندروستی پلاتفۆرم', 1, ARRAY['platform']::text[], false, false, false, false, true),
('owner_view_queue_health', 'بینینی تەندروستی queue', 'platform_health', 'تەندروستی پلاتفۆرم', 1, ARRAY['platform']::text[], false, false, false, false, true),
('owner_view_platform_error_rate', 'بینینی ڕێژەی هەڵە', 'platform_health', 'تەندروستی پلاتفۆرم', 1, ARRAY['platform']::text[], false, false, false, false, true),
('owner_view_platform_latency', 'بینینی latency ـی پلاتفۆرم', 'platform_health', 'تەندروستی پلاتفۆرم', 1, ARRAY['platform']::text[], false, false, false, false, true),
('owner_refresh_platform_config', 'نوێکردنەوەی configuration', 'platform_health', 'تەندروستی پلاتفۆرم', 2, ARRAY['platform']::text[], false, false, false, false, true),
('owner_view_owner_audit', 'بینینی audit ـی Owner', 'audit', 'Audit و بەدواداچوون', 1, ARRAY['platform']::text[], false, false, false, false, true),
('owner_export_owner_audit', 'هەناردەکردنی audit ـی Owner', 'audit', 'Audit و بەدواداچوون', 2, ARRAY['platform']::text[], false, false, false, false, true),
('owner_view_admin_audit', 'بینینی audit ـی بەڕێوەبەر', 'audit', 'Audit و بەدواداچوون', 1, ARRAY['admin']::text[], false, false, false, false, true),
('owner_view_market_audit', 'بینینی audit ـی مارکێت', 'audit', 'Audit و بەدواداچوون', 1, ARRAY['market']::text[], false, false, false, false, true),
('owner_view_before_after_state', 'بینینی before/after state', 'audit', 'Audit و بەدواداچوون', 1, ARRAY['platform']::text[], false, false, false, false, true),
('owner_view_rollback_history', 'بینینی مێژووی rollback', 'audit', 'Audit و بەدواداچوون', 1, ARRAY['platform']::text[], false, false, false, false, true)
on conflict (permission_key) do update
set label = excluded.label,
    group_key = excluded.group_key,
    group_label = excluded.group_label,
    risk_level = excluded.risk_level,
    scopes = excluded.scopes,
    requires_reason = excluded.requires_reason,
    requires_reauth = excluded.requires_reauth,
    requires_typed_confirmation = excluded.requires_typed_confirmation,
    requires_two_person_approval = excluded.requires_two_person_approval,
    active = excluded.active,
    updated_at = now();

insert into private.owner_permission_principals (owner_id, permission_mode, updated_by)
select p.id, 'full', p.id
from public.profiles p
where p.is_system_owner = true
  and p.active = true
  and p.approved = true
on conflict (owner_id) do nothing;

create or replace function private.system_owner_has_permission(
  p_permission_key text,
  p_scope_type text default 'platform',
  p_scope_id uuid default null,
  p_owner_id uuid default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := coalesce(p_owner_id, auth.uid());
  v_mode text := 'full';
  v_allowed boolean;
  v_scope_ok boolean := false;
begin
  if v_owner_id is null then
    return false;
  end if;

  if p_scope_type not in ('platform','market','admin') then
    return false;
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = v_owner_id
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  ) then
    return false;
  end if;

  select p_scope_type = any(c.scopes)
    into v_scope_ok
  from private.owner_permission_catalog c
  where c.permission_key = p_permission_key
    and c.active = true;

  if not coalesce(v_scope_ok, false) then
    return false;
  end if;

  select pr.permission_mode
    into v_mode
  from private.owner_permission_principals pr
  where pr.owner_id = v_owner_id;

  v_mode := coalesce(v_mode, 'full');

  select g.allowed
    into v_allowed
  from private.owner_permission_grants g
  where g.owner_id = v_owner_id
    and g.permission_key = p_permission_key
    and g.scope_type = p_scope_type
    and (g.scope_id = p_scope_id or g.scope_id is null)
    and (g.expires_at is null or g.expires_at > now())
  order by (g.scope_id is not null) desc, g.updated_at desc
  limit 1;

  if found then
    return v_allowed;
  end if;

  return v_mode = 'full';
end;
$$;

revoke all on function private.system_owner_has_permission(text,text,uuid,uuid)
  from public, anon, authenticated;
grant execute on function private.system_owner_has_permission(text,text,uuid,uuid)
  to service_role;

create or replace function private.assert_system_owner_permission(
  p_permission_key text,
  p_scope_type text default 'platform',
  p_scope_id uuid default null
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.system_owner_has_permission(
    p_permission_key,
    p_scope_type,
    p_scope_id,
    auth.uid()
  ) then
    raise exception 'owner_permission_required:%', p_permission_key
      using errcode = '42501';
  end if;
end;
$$;

revoke all on function private.assert_system_owner_permission(text,text,uuid)
  from public, anon, authenticated;
grant execute on function private.assert_system_owner_permission(text,text,uuid)
  to service_role;

create or replace function private.get_system_owner_permission_catalog_internal()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_items jsonb;
begin
  if v_uid is null or not exists (
    select 1
    from public.profiles p
    where p.id = v_uid
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'system_owner_required' using errcode = '42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'key', c.permission_key,
        'label', c.label,
        'group_key', c.group_key,
        'group_label', c.group_label,
        'risk_level', c.risk_level,
        'scopes', to_jsonb(c.scopes),
        'requires_reason', c.requires_reason,
        'requires_reauth', c.requires_reauth,
        'requires_typed_confirmation', c.requires_typed_confirmation,
        'requires_two_person_approval', c.requires_two_person_approval,
        'active', c.active,
        'allowed_platform', case
          when 'platform' = any(c.scopes)
          then private.system_owner_has_permission(c.permission_key, 'platform', null, v_uid)
          else false
        end
      )
      order by c.group_key, c.risk_level, c.permission_key
    ),
    '[]'::jsonb
  )
  into v_items
  from private.owner_permission_catalog c
  where c.active = true;

  return jsonb_build_object(
    'count', jsonb_array_length(v_items),
    'permissions', v_items
  );
end;
$$;

revoke all on function private.get_system_owner_permission_catalog_internal()
  from public, anon, authenticated;
grant execute on function private.get_system_owner_permission_catalog_internal()
  to authenticated, service_role;

grant usage on schema private to authenticated;

create or replace function public.get_system_owner_permission_catalog()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select private.get_system_owner_permission_catalog_internal();
$$;

revoke all on function public.get_system_owner_permission_catalog()
  from public, anon;
grant execute on function public.get_system_owner_permission_catalog()
  to authenticated;

comment on table private.owner_permission_catalog is
  'Central registry for System Owner platform/admin/market permissions. No direct customer-business-content permissions.';
comment on table private.owner_permission_grants is
  'Scoped allow/deny overrides for System Owner permissions. Null market/admin scope_id acts as a wildcard.';
comment on function private.system_owner_has_permission(text,text,uuid,uuid) is
  'Server-side Owner authorization guard. Existing active approved system owners default to full access unless explicitly restricted/denied.';
