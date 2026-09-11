alter table public.subscription_payments
  add column if not exists provider_status text,
  add column if not exists declining_reason text,
  add column if not exists provider_paid_at timestamptz,
  add column if not exists last_verified_at timestamptz;

create index if not exists subscription_payments_admin_status_created_idx
  on public.subscription_payments(admin_id, status, created_at desc);

revoke insert, update, delete on public.subscription_payments from anon;
revoke insert, update, delete on public.subscription_payments from authenticated;
grant select on public.subscription_payments to authenticated;

comment on column public.subscription_payments.provider_status is
  'Last payment status returned by FIB after a server-to-server verification.';
comment on column public.subscription_payments.declining_reason is
  'FIB decliningReason, including PAYMENT_EXPIRATION or PAYMENT_CANCELLATION.';
comment on column public.subscription_payments.provider_paid_at is
  'Payment completion time reported by FIB; subscription activation remains controlled by the atomic activation RPC.';
comment on column public.subscription_payments.last_verified_at is
  'Last time the backend fetched this payment directly from the FIB status endpoint.';
