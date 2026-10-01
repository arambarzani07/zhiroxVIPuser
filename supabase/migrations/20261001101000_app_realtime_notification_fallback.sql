create table if not exists public.app_realtime_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_user_id uuid not null references auth.users(id) on delete cascade,
  market_id uuid null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 160),
  body text not null check (char_length(body) between 1 and 1000),
  event_type text not null default 'general' check (char_length(event_type) between 1 and 80),
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz null,
  created_at timestamptz not null default now(),
  expires_at timestamptz null,
  delivered_at timestamptz null
);

alter table public.app_realtime_notifications
  add column if not exists delivered_at timestamptz null;

create index if not exists app_realtime_notifications_recipient_created_idx
  on public.app_realtime_notifications (recipient_user_id, created_at desc);

alter table public.app_realtime_notifications enable row level security;

revoke all on public.app_realtime_notifications from anon;
revoke all on public.app_realtime_notifications from authenticated;
grant select on public.app_realtime_notifications to authenticated;
grant update (delivered_at) on public.app_realtime_notifications to authenticated;

drop policy if exists "app_notifications_select_own" on public.app_realtime_notifications;
drop policy if exists "app_notifications_update_own" on public.app_realtime_notifications;
drop policy if exists "app_notifications_mark_delivered" on public.app_realtime_notifications;

create policy "app_notifications_select_own"
  on public.app_realtime_notifications
  for select
  to authenticated
  using (recipient_user_id = (select auth.uid()));

create policy "app_notifications_mark_delivered"
  on public.app_realtime_notifications
  for update
  to authenticated
  using (recipient_user_id = (select auth.uid()))
  with check (recipient_user_id = (select auth.uid()));

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'app_realtime_notifications'
  ) then
    alter publication supabase_realtime
      add table public.app_realtime_notifications;
  end if;
end $$;
