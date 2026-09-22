-- Covers the audit actor foreign key used by receipt template history.
create index if not exists receipt_template_versions_created_by_idx
  on public.receipt_template_versions (created_by)
  where created_by is not null;
