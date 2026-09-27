-- Expiry monitoring is independent of customers, debts, payments, and sales.
alter table public.employee_permissions
  add column if not exists can_view_expiry boolean not null default false,
  add column if not exists can_manage_expiry boolean not null default false;

create or replace function private.expiry_access(p_write boolean default false)
returns boolean language sql stable security definer set search_path = '' as $$
  select case
    when private.current_role() = 'admin' then true
    when private.current_role() = 'employee' then exists (
      select 1 from public.employee_permissions ep
      where ep.employee_id = (select auth.uid())
        and ep.admin_id = private.current_admin_id()
        and (case when p_write then ep.can_manage_expiry
                  else ep.can_view_expiry or ep.can_manage_expiry end)
    )
    else false
  end
$$;
revoke all on function private.expiry_access(boolean) from public, anon, authenticated;
grant execute on function private.expiry_access(boolean) to authenticated;

create table public.expiry_products (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  external_code text not null check (length(trim(external_code)) between 1 and 120),
  barcode text check (barcode is null or length(trim(barcode)) between 1 and 120),
  name text not null check (length(trim(name)) between 1 and 300),
  category text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (admin_id, external_code),
  unique (admin_id, id)
);
create unique index expiry_products_barcode_unique
  on public.expiry_products(admin_id, barcode) where barcode is not null;
create index expiry_products_name_idx on public.expiry_products(admin_id, name);

create table public.expiry_arrivals (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  product_id uuid not null,
  expiry_date date not null,
  arrived_on date not null default current_date,
  batch_code text not null default '',
  notes text not null default '',
  resolved_at timestamptz,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  resolved_by uuid,
  foreign key (admin_id, product_id) references public.expiry_products(admin_id, id) on delete cascade
);
create index expiry_arrivals_active_idx
  on public.expiry_arrivals(admin_id, expiry_date, product_id)
  where resolved_at is null;
create index expiry_arrivals_product_idx
  on public.expiry_arrivals(admin_id, product_id, created_at desc);

create function private.expiry_arrival_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    if new.admin_id is distinct from old.admin_id or
       new.product_id is distinct from old.product_id or
       new.expiry_date is distinct from old.expiry_date or
       new.arrived_on is distinct from old.arrived_on or
       new.batch_code is distinct from old.batch_code or
       new.created_by is distinct from old.created_by or
       new.created_at is distinct from old.created_at then
      raise exception 'Arrival identity and dates are immutable';
    end if;
    if old.resolved_at is not null and new.resolved_at is null then
      raise exception 'Resolved arrivals cannot be reopened';
    end if;
    if new.resolved_by is distinct from old.resolved_by and
       new.resolved_at is not distinct from old.resolved_at then
      raise exception 'Resolution actor cannot be changed';
    end if;
    if new.resolved_at is distinct from old.resolved_at then
      new.resolved_by := (select auth.uid());
      new.resolved_at := now();
    end if;
  end if;
  return new;
end
$$;
create trigger expiry_arrival_guard before update on public.expiry_arrivals
  for each row execute function private.expiry_arrival_guard();

alter table public.expiry_products enable row level security;
alter table public.expiry_arrivals enable row level security;
revoke all on public.expiry_products, public.expiry_arrivals from anon, authenticated;
grant select, insert, update on public.expiry_products, public.expiry_arrivals to authenticated;

create policy expiry_products_read on public.expiry_products for select to authenticated
  using (admin_id = (select private.current_admin_id()) and (select private.expiry_access(false)));
create policy expiry_products_add on public.expiry_products for insert to authenticated
  with check (admin_id = (select private.current_admin_id()) and (select private.expiry_access(true)));
create policy expiry_products_edit on public.expiry_products for update to authenticated
  using (admin_id = (select private.current_admin_id()) and (select private.expiry_access(true)))
  with check (admin_id = (select private.current_admin_id()) and (select private.expiry_access(true)));

create policy expiry_arrivals_read on public.expiry_arrivals for select to authenticated
  using (admin_id = (select private.current_admin_id()) and (select private.expiry_access(false)));
create policy expiry_arrivals_add on public.expiry_arrivals for insert to authenticated
  with check (admin_id = (select private.current_admin_id()) and (select private.expiry_access(true))
    and created_by = (select auth.uid()) and resolved_at is null and resolved_by is null);
create policy expiry_arrivals_edit on public.expiry_arrivals for update to authenticated
  using (admin_id = (select private.current_admin_id()) and (select private.expiry_access(true)))
  with check (admin_id = (select private.current_admin_id()) and (select private.expiry_access(true)));

-- One transaction per import; if a barcode belongs to another product the
-- entire import fails rather than silently associating arrivals with it.
create function public.import_expiry_products(p_rows jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  tenant uuid := private.current_admin_id();
  item jsonb;
  code text;
  label text;
  raw_barcode text;
  inserted_count integer := 0;
  updated_count integer := 0;
  existed boolean;
begin
  if tenant is null or not private.expiry_access(true) then
    raise exception 'Expiry import access denied' using errcode = '42501';
  end if;
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'Import must be an array of products';
  end if;
  if jsonb_array_length(p_rows) < 1 or jsonb_array_length(p_rows) > 10000 then
    raise exception 'Import must contain 1 to 10000 products';
  end if;
  for item in select value from jsonb_array_elements(p_rows) loop
    code := trim(coalesce(item->>'external_code', ''));
    label := trim(coalesce(item->>'name', ''));
    raw_barcode := nullif(trim(coalesce(item->>'barcode', '')), '');
    if length(code) not between 1 and 120 or length(label) not between 1 and 300 or
       length(coalesce(raw_barcode, '')) > 120 or
       length(coalesce(item->>'category', '')) > 150 then
      raise exception 'Invalid product code, name, barcode, or category';
    end if;
    select exists(select 1 from public.expiry_products p
      where p.admin_id = tenant and p.external_code = code) into existed;
    insert into public.expiry_products(admin_id, external_code, barcode, name, category)
    values (tenant, code, raw_barcode, label, trim(coalesce(item->>'category', '')))
    on conflict (admin_id, external_code) do update set
      name = excluded.name, barcode = excluded.barcode,
      category = excluded.category, updated_at = now();
    if existed then updated_count := updated_count + 1;
    else inserted_count := inserted_count + 1; end if;
  end loop;
  return jsonb_build_object('inserted', inserted_count, 'updated', updated_count);
end
$$;
revoke all on function public.import_expiry_products(jsonb) from public, anon;
grant execute on function public.import_expiry_products(jsonb) to authenticated;
