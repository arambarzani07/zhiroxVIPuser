create index if not exists debt_installments_created_by_idx
  on public.debt_installments (created_by)
  where created_by is not null;

create index if not exists market_notification_settings_updated_by_idx
  on public.market_notification_settings (updated_by)
  where updated_by is not null;
