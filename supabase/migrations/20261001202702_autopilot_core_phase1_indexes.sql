create index if not exists autopilot_jobs_event_idx on private.autopilot_jobs(event_id);
create index if not exists autopilot_jobs_customer_idx on private.autopilot_jobs(customer_id) where customer_id is not null;
create index if not exists customer_risk_scores_market_idx on public.customer_risk_scores(market_id, calculated_at desc);
create index if not exists market_autopilot_settings_updated_by_idx on public.market_autopilot_settings(updated_by) where updated_by is not null;
