alter table public.profiles
  add column if not exists can_view_dashboard boolean not null default true,
  add column if not exists can_view_recent_activity boolean not null default true,
  add column if not exists can_view_transactions boolean not null default false,
  add column if not exists can_edit_payments boolean not null default false,
  add column if not exists can_delete_payments boolean not null default false,
  add column if not exists can_create_statements boolean not null default false,
  add column if not exists can_manage_customer_links boolean not null default false,
  add column if not exists can_pin_customers boolean not null default false,
  add column if not exists can_manage_vip_customers boolean not null default false,
  add column if not exists can_merge_customer_identities boolean not null default false,
  add column if not exists can_view_market_rates boolean not null default true,
  add column if not exists can_view_intelligence boolean not null default false,
  add column if not exists can_manage_collections boolean not null default false,
  add column if not exists can_manage_expiry boolean not null default false,
  add column if not exists can_manage_settings boolean not null default false;

update public.profiles
set
  can_view_transactions = case when role = 'employee' then can_view_debts else can_view_transactions end,
  can_create_statements = case when role = 'employee' then can_view_financial_reports else can_create_statements end,
  can_view_intelligence = case when role = 'employee' then can_view_financial_reports else can_view_intelligence end,
  can_manage_collections = case when role = 'employee' then can_edit_debts else can_manage_collections end,
  can_manage_customer_links = case when role = 'employee' then can_send_notifications else can_manage_customer_links end
where role = 'employee';
