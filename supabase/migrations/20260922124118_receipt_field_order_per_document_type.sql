-- Market admins can reorder optional metadata independently on loan and
-- repayment receipts. Identity and fixed attribution remain outside this list.
alter table public.market_receipt_settings
  add column if not exists debt_field_order jsonb not null
    default '["date","customer","customer_phone","due","admin","method","custom"]'::jsonb,
  add column if not exists payment_field_order jsonb not null
    default '["date","customer","customer_phone","admin","debt","method","custom"]'::jsonb;

alter table public.market_receipt_settings
  add constraint market_receipt_settings_debt_field_order_array
    check (jsonb_typeof(debt_field_order) = 'array'),
  add constraint market_receipt_settings_payment_field_order_array
    check (jsonb_typeof(payment_field_order) = 'array');
