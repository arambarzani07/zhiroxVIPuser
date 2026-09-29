
create index if not exists daftar_mirror_transactions_nonzero_type_source_idx
on public.daftar_mirror_transactions (
  sync_source_id,
  ((payload->>'transaction_type')),
  source_id
)
where coalesce(nullif(payload->>'amount','')::numeric,0) <> 0;

create index if not exists daftar_mirror_transactions_zero_order_idx
on public.daftar_mirror_transactions (
  sync_source_id,
  last_mirrored_at,
  source_id
)
where coalesce(nullif(payload->>'amount','')::numeric,0) = 0;
