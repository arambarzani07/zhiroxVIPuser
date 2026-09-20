-- Allow explicit shadow verification telemetry states.

do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'daftar_live_read_events_status_check'
      and conrelid = 'public.daftar_live_read_events'::regclass
  ) then
    alter table public.daftar_live_read_events
      drop constraint daftar_live_read_events_status_check;
  end if;

  alter table public.daftar_live_read_events
    add constraint daftar_live_read_events_status_check
    check (
      status in (
        'success',
        'fallback',
        'rejected',
        'failed',
        'shadow_success',
        'shadow_failed'
      )
    );
end;
$$;
