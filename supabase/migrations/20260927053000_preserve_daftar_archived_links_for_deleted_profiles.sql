-- Archived identity links retain historical UUIDs after a profile is removed.
-- The active link and authorization checks remain unchanged.
alter table public.daftar_customer_link_archive
  drop constraint if exists daftar_customer_link_archive_target_id_fkey;
