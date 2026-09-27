-- Cover both remaining customer identity merge foreign keys (Audit40 gate).
create index if not exists customer_identity_merges_admin_idx
  on public.customer_identity_merges(admin_id);
create index if not exists customer_identity_merges_merged_by_idx
  on public.customer_identity_merges(merged_by);
