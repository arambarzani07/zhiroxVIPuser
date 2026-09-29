create table if not exists public.market_exchange_rates (
  source text not null,
  city text not null,
  variant text not null,
  rate_iqd_per_100_usd numeric not null check (rate_iqd_per_100_usd > 0),
  source_url text not null,
  source_published_at timestamptz,
  retrieved_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (source, city, variant)
);

alter table public.market_exchange_rates enable row level security;

drop policy if exists market_exchange_rates_authenticated_read on public.market_exchange_rates;
create policy market_exchange_rates_authenticated_read
on public.market_exchange_rates
for select
to authenticated
using (true);

revoke insert, update, delete on public.market_exchange_rates from anon, authenticated;
grant select on public.market_exchange_rates to authenticated;
grant all on public.market_exchange_rates to service_role;

create index if not exists market_exchange_rates_updated_at_idx
  on public.market_exchange_rates(updated_at desc);
