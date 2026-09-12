alter table public.market_receipt_settings
  add column if not exists template_style text not null default 'modern',
  add column if not exists debt_template text not null default 'modern',
  add column if not exists payment_template text not null default 'classic',
  add column if not exists purchase_template text not null default 'modern',
  add column if not exists logo_path text not null default '',
  add column if not exists stamp_path text not null default '',
  add column if not exists signature_path text not null default '',
  add column if not exists primary_color text not null default '#0F766E',
  add column if not exists font_scale numeric not null default 1,
  add column if not exists header_alignment text not null default 'center',
  add column if not exists show_qr boolean not null default true,
  add column if not exists show_barcode boolean not null default false,
  add column if not exists receipt_prefix text not null default 'INV',
  add column if not exists vat_percent numeric not null default 0,
  add column if not exists discount_percent numeric not null default 0,
  add column if not exists default_payment_method text not null default 'debt',
  add column if not exists custom_fields jsonb not null default '[]'::jsonb,
  add column if not exists margin_mm numeric not null default 8,
  add column if not exists language_mode text not null default 'ku',
  add column if not exists template_version integer not null default 1;

alter table public.market_receipt_settings
  drop constraint if exists market_receipt_settings_paper_size_check;
alter table public.market_receipt_settings
  add constraint market_receipt_settings_paper_size_check
  check (paper_size in ('a4','thermal80','thermal58'));

alter table public.market_receipt_settings
  drop constraint if exists market_receipt_settings_template_style_check,
  drop constraint if exists market_receipt_settings_debt_template_check,
  drop constraint if exists market_receipt_settings_payment_template_check,
  drop constraint if exists market_receipt_settings_purchase_template_check,
  drop constraint if exists market_receipt_settings_primary_color_check,
  drop constraint if exists market_receipt_settings_font_scale_check,
  drop constraint if exists market_receipt_settings_header_alignment_check,
  drop constraint if exists market_receipt_settings_receipt_prefix_check,
  drop constraint if exists market_receipt_settings_vat_percent_check,
  drop constraint if exists market_receipt_settings_discount_percent_check,
  drop constraint if exists market_receipt_settings_payment_method_check,
  drop constraint if exists market_receipt_settings_custom_fields_check,
  drop constraint if exists market_receipt_settings_margin_mm_check,
  drop constraint if exists market_receipt_settings_language_mode_check,
  drop constraint if exists market_receipt_settings_template_version_check;

alter table public.market_receipt_settings
  add constraint market_receipt_settings_template_style_check check (template_style in ('classic','modern')),
  add constraint market_receipt_settings_debt_template_check check (debt_template in ('classic','modern')),
  add constraint market_receipt_settings_payment_template_check check (payment_template in ('classic','modern')),
  add constraint market_receipt_settings_purchase_template_check check (purchase_template in ('classic','modern')),
  add constraint market_receipt_settings_primary_color_check check (primary_color ~ '^#[0-9A-Fa-f]{6}$'),
  add constraint market_receipt_settings_font_scale_check check (font_scale between 0.75 and 1.50),
  add constraint market_receipt_settings_header_alignment_check check (header_alignment in ('start','center','end')),
  add constraint market_receipt_settings_receipt_prefix_check check (receipt_prefix ~ '^[A-Za-z0-9_-]{1,12}$'),
  add constraint market_receipt_settings_vat_percent_check check (vat_percent between 0 and 100),
  add constraint market_receipt_settings_discount_percent_check check (discount_percent between 0 and 100),
  add constraint market_receipt_settings_payment_method_check check (default_payment_method in ('cash','fib','transfer','card','debt')),
  add constraint market_receipt_settings_custom_fields_check check (jsonb_typeof(custom_fields) = 'array'),
  add constraint market_receipt_settings_margin_mm_check check (margin_mm between 0 and 30),
  add constraint market_receipt_settings_language_mode_check check (language_mode in ('ku','ar','en','ku_ar','ku_en')),
  add constraint market_receipt_settings_template_version_check check (template_version > 0);

create or replace function private.bump_receipt_template_version()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
begin
  new.template_version := old.template_version + 1;
  new.updated_at := now();
  return new;
end;
$function$;

drop trigger if exists trg_market_receipt_settings_version on public.market_receipt_settings;
create trigger trg_market_receipt_settings_version
before update on public.market_receipt_settings
for each row execute function private.bump_receipt_template_version();

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('market-branding','market-branding',false,5242880,array['image/png','image/jpeg','image/webp']::text[])
on conflict (id) do update set public=excluded.public,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists market_branding_select_tenant on storage.objects;
create policy market_branding_select_tenant on storage.objects for select to authenticated
using (bucket_id='market-branding' and (storage.foldername(name))[1]=private.current_admin_id()::text);

drop policy if exists market_branding_insert_admin on storage.objects;
create policy market_branding_insert_admin on storage.objects for insert to authenticated
with check (bucket_id='market-branding' and private.current_role()='admin' and (storage.foldername(name))[1]=auth.uid()::text and auth.uid()=private.current_admin_id());

drop policy if exists market_branding_update_admin on storage.objects;
create policy market_branding_update_admin on storage.objects for update to authenticated
using (bucket_id='market-branding' and private.current_role()='admin' and (storage.foldername(name))[1]=auth.uid()::text and auth.uid()=private.current_admin_id())
with check (bucket_id='market-branding' and private.current_role()='admin' and (storage.foldername(name))[1]=auth.uid()::text and auth.uid()=private.current_admin_id());

drop policy if exists market_branding_delete_admin on storage.objects;
create policy market_branding_delete_admin on storage.objects for delete to authenticated
using (bucket_id='market-branding' and private.current_role()='admin' and (storage.foldername(name))[1]=auth.uid()::text and auth.uid()=private.current_admin_id());

create table if not exists public.receipt_documents (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  source_type text not null check (source_type in ('debt','payment','purchase')),
  source_id uuid not null,
  version_no integer not null default 1 check (version_no > 0),
  receipt_number text not null default '',
  settings_version integer not null default 1 check (settings_version > 0),
  settings_snapshot jsonb not null default '{}'::jsonb check (jsonb_typeof(settings_snapshot)='object'),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (admin_id, receipt_number),
  unique (admin_id, source_type, source_id, version_no)
);

create table if not exists private.receipt_counters (
  admin_id uuid not null references public.profiles(id) on delete cascade,
  receipt_year integer not null,
  next_number bigint not null default 1 check (next_number > 0),
  primary key (admin_id, receipt_year)
);

create or replace function private.assign_receipt_identity()
returns trigger language plpgsql security definer set search_path to 'pg_catalog'
as $function$
declare
  v_year integer := extract(year from current_timestamp)::integer;
  v_number bigint;
  v_prefix text;
begin
  if new.receipt_number is null or btrim(new.receipt_number)='' then
    insert into private.receipt_counters (admin_id,receipt_year,next_number)
    values (new.admin_id,v_year,2)
    on conflict (admin_id,receipt_year)
    do update set next_number=private.receipt_counters.next_number+1
    returning next_number-1 into v_number;
    v_prefix := upper(coalesce(nullif(btrim(new.settings_snapshot->>'receipt_prefix'),''),'INV'));
    new.receipt_number := v_prefix||'-'||v_year::text||'-'||lpad(v_number::text,6,'0');
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_receipt_documents_identity on public.receipt_documents;
create trigger trg_receipt_documents_identity before insert on public.receipt_documents
for each row execute function private.assign_receipt_identity();

alter table public.receipt_documents enable row level security;
revoke all on table public.receipt_documents from public, anon, authenticated;
grant select, insert on table public.receipt_documents to authenticated;
grant all on table public.receipt_documents to service_role;

drop policy if exists receipt_documents_select_tenant on public.receipt_documents;
create policy receipt_documents_select_tenant on public.receipt_documents for select to authenticated
using (admin_id=private.current_admin_id());

drop policy if exists receipt_documents_insert_staff on public.receipt_documents;
create policy receipt_documents_insert_staff on public.receipt_documents for insert to authenticated
with check (admin_id=private.current_admin_id() and private.current_role() in ('admin','employee') and created_by=auth.uid());

create index if not exists receipt_documents_source_idx
on public.receipt_documents (admin_id,source_type,source_id,version_no desc);
