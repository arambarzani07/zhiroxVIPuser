update public.market_receipt_settings
set vat_percent = 0
where vat_percent <> 0;

alter table public.market_receipt_settings
  alter column vat_percent set default 0;

alter table public.market_receipt_settings
  drop constraint if exists market_receipt_settings_vat_percent_check;

create or replace function private.force_receipt_vat_zero()
returns trigger
language plpgsql
set search_path to 'pg_catalog'
as $function$
begin
  new.vat_percent := 0;
  return new;
end;
$function$;

drop trigger if exists trg_market_receipt_settings_vat_zero
on public.market_receipt_settings;

create trigger trg_market_receipt_settings_vat_zero
before insert or update of vat_percent on public.market_receipt_settings
for each row execute function private.force_receipt_vat_zero();

alter table public.market_receipt_settings
  add constraint market_receipt_settings_vat_percent_check
  check (vat_percent = 0);
