-- Fix hostname validation escaping for standard_conforming_strings.

create or replace function private.validate_platform_hostname(p_value text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select
    p_value ~ '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$'
    and length(p_value) between 1 and 253
    and p_value not in ('localhost')
    and p_value not like '%.local'
    and p_value not like '%.internal';
$$;
