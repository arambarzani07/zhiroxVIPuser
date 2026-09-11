create table if not exists public.market_receipt_settings (
  admin_id uuid primary key references public.profiles(id) on delete cascade,
  receipt_title text not null default 'پسوولەی فەرمی',
  address text not null default '',
  phone text not null default '',
  secondary_phone text not null default '',
  registration_no text not null default '',
  footer_note text not null default 'سوپاس بۆ مامەڵەکردنتان',
  paper_size text not null default 'a4' check (paper_size in ('a4','thermal80')),
  show_customer_phone boolean not null default true,
  show_admin_name boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.market_receipt_settings enable row level security;

revoke all on table public.market_receipt_settings from public, anon;
grant select, insert, update, delete on table public.market_receipt_settings to authenticated;
grant all on table public.market_receipt_settings to service_role;

drop policy if exists market_receipt_settings_select_tenant on public.market_receipt_settings;
create policy market_receipt_settings_select_tenant
on public.market_receipt_settings
for select
to authenticated
using (admin_id = private.current_admin_id());

drop policy if exists market_receipt_settings_insert_admin on public.market_receipt_settings;
create policy market_receipt_settings_insert_admin
on public.market_receipt_settings
for insert
to authenticated
with check (
  private.current_role() = 'admin'
  and admin_id = auth.uid()
  and admin_id = private.current_admin_id()
);

drop policy if exists market_receipt_settings_update_admin on public.market_receipt_settings;
create policy market_receipt_settings_update_admin
on public.market_receipt_settings
for update
to authenticated
using (
  private.current_role() = 'admin'
  and admin_id = auth.uid()
  and admin_id = private.current_admin_id()
)
with check (
  private.current_role() = 'admin'
  and admin_id = auth.uid()
  and admin_id = private.current_admin_id()
);

drop policy if exists market_receipt_settings_delete_admin on public.market_receipt_settings;
create policy market_receipt_settings_delete_admin
on public.market_receipt_settings
for delete
to authenticated
using (
  private.current_role() = 'admin'
  and admin_id = auth.uid()
  and admin_id = private.current_admin_id()
);
