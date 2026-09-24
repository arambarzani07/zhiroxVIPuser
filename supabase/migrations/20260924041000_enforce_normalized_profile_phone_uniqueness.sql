create or replace function private.normalize_profile_phone(p_phone text)
returns text
language sql
immutable
strict
set search_path to ''
as $function$
  with cleaned as (
    select regexp_replace(
      translate(
        trim(p_phone),
        '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹',
        '01234567890123456789'
      ),
      '[^0-9]',
      '',
      'g'
    ) as digits
  )
  select case
    when digits like '00964%' then '0' || substr(digits, 6)
    when digits like '964%' then '0' || substr(digits, 4)
    when digits ~ '^7[0-9]{9}$' then '0' || digits
    else digits
  end
  from cleaned;
$function$;

create unique index if not exists profiles_normalized_phone_unique_idx
  on public.profiles (private.normalize_profile_phone(phone))
  where private.normalize_profile_phone(phone) <> '';
