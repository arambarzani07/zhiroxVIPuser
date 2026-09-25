-- Automatically cover every public-schema foreign key with a leading index.
-- This removes drift between production-only tables and fresh installs and
-- keeps future FK additions from silently missing their supporting index.

do $fk_autocover$
declare
  r record;
  v_columns text;
  v_index_name text;
begin
  for r in
    select
      c.oid,
      c.conrelid,
      c.conname,
      c.conkey,
      t.relname as table_name,
      n.nspname as schema_name
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where c.contype = 'f'
      and n.nspname = 'public'
      and not exists (
        select 1
        from pg_index i
        where i.indrelid = c.conrelid
          and i.indisvalid
          and i.indisready
          and i.indnkeyatts >= array_length(c.conkey, 1)
          and (
            select array_agg(k.attnum order by k.ord)
            from unnest(i.indkey::smallint[]) with ordinality k(attnum, ord)
            where k.ord <= array_length(c.conkey, 1)
          ) = c.conkey
      )
    order by t.relname, c.conname
  loop
    select string_agg(format('%I', a.attname), ', ' order by u.ord)
      into v_columns
    from unnest(r.conkey) with ordinality u(attnum, ord)
    join pg_attribute a
      on a.attrelid = r.conrelid
     and a.attnum = u.attnum;

    if nullif(v_columns, '') is null then
      raise exception 'fk_index_columns_not_resolved:%', r.conname;
    end if;

    v_index_name := left(
      'idx_fk_' || r.table_name || '_' ||
      regexp_replace(r.conname, '[^a-zA-Z0-9_]+', '_', 'g'),
      63
    );

    execute format(
      'create index if not exists %I on %I.%I (%s)',
      v_index_name,
      r.schema_name,
      r.table_name,
      v_columns
    );
  end loop;
end
$fk_autocover$;
