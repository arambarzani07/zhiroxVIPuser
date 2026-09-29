
alter table public.profiles
  add column if not exists can_refund_payments boolean not null default false,
  add column if not exists can_restore_debts boolean not null default false,
  add column if not exists can_manage_receipts boolean not null default false,
  add column if not exists can_manage_notifications boolean not null default false,
  add column if not exists can_approve_customers boolean not null default false,
  add column if not exists can_manage_employees boolean not null default false,
  add column if not exists can_view_audit_log boolean not null default false,
  add column if not exists can_manage_backup boolean not null default false,
  add column if not exists can_manage_daftar_sync boolean not null default false,
  add column if not exists can_manage_subscription boolean not null default false;
