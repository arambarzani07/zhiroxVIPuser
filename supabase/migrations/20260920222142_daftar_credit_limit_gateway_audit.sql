create table if not exists public.daftar_credit_limit_gateway_events (
  id uuid primary key default gen_random_uuid(),
  source_fingerprint text not null default 'daftar-live-account-28-v1',
  legacy_user_id integer not null default 28,
  contact_source_id text,
  target_customer_id uuid,
  transaction_type text,
  amount numeric,
  currency text,
  debt_limit numeric,
  current_balance numeric,
  projected_balance numeric,
  decision text not null check (decision in ('allowed','blocked','error')),
  http_status integer,
  detail text,
  created_at timestamptz not null default now()
);

alter table public.daftar_credit_limit_gateway_events enable row level security;

revoke all on table public.daftar_credit_limit_gateway_events from public, anon, authenticated;
grant select, insert on table public.daftar_credit_limit_gateway_events to service_role;

create index if not exists daftar_credit_limit_gateway_events_contact_created_idx
  on public.daftar_credit_limit_gateway_events (contact_source_id, created_at desc);

create index if not exists daftar_credit_limit_gateway_events_decision_created_idx
  on public.daftar_credit_limit_gateway_events (decision, created_at desc);
