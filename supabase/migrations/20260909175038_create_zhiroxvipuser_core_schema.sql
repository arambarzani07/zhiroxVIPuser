-- Production schema bootstrap snapshot for zhiroxVIPuser.
-- Generated from project hsoyfbtpvwfmjokudznx; schema only, no user or business rows.
create schema if not exists private;

create table if not exists public.profiles (
  id uuid not null,
  name text default ''::text not null,
  father_name text default ''::text not null,
  grandfather_name text default ''::text not null,
  phone text not null,
  role text not null,
  market_name text default ''::text not null,
  admin_id uuid,
  created_by uuid,
  approved boolean default true not null,
  active boolean default true not null,
  debt_limit numeric default 0 not null,
  debt_duration integer default 30 not null,
  can_add_customers boolean default false not null,
  can_set_debt_limit boolean default false not null,
  can_set_due_date boolean default false not null,
  can_edit_debts boolean default false not null,
  can_send_notifications boolean default false not null,
  subscription_end timestamp with time zone,
  telegram_chat_id text default ''::text not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  is_system_owner boolean default false not null
);

create table if not exists public.debts (
  id uuid default gen_random_uuid() not null,
  customer_id uuid not null,
  description text default ''::text not null,
  amount numeric not null,
  remaining numeric not null,
  due_date date,
  status text default 'pending'::text not null,
  created_by uuid,
  currency text default 'IQD'::text not null,
  dollar_rate numeric default 0 not null,
  amount_usd numeric default 0 not null,
  items jsonb default '[]'::jsonb not null,
  custom_date timestamp with time zone,
  receipt_image_path text default ''::text not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  reference_kind text,
  reference_id uuid,
  reference_snapshot jsonb default '{}'::jsonb not null
);

create table if not exists public.payments (
  id uuid default gen_random_uuid() not null,
  debt_id uuid not null,
  amount numeric not null,
  note text default ''::text not null,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  reference_kind text,
  reference_id uuid,
  reference_snapshot jsonb default '{}'::jsonb not null
);

create table if not exists public.notifications (
  id uuid default gen_random_uuid() not null,
  customer_id uuid not null,
  sender_id uuid,
  message text not null,
  type text default 'general'::text not null,
  is_read boolean default false not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.financial_events (
  id uuid default gen_random_uuid() not null,
  customer_id uuid not null,
  debt_id uuid,
  payment_id uuid,
  event_type text not null,
  actor_id uuid,
  actor_name text default ''::text not null,
  actor_role text default ''::text not null,
  amount numeric default 0 not null,
  remaining numeric default 0 not null,
  currency text default 'IQD'::text not null,
  description text default ''::text not null,
  metadata jsonb default '{}'::jsonb not null,
  created_at timestamp with time zone default now() not null
);

do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.debts'::regclass and conname = 'debts_amount_check'
  ) then
    alter table public.debts add constraint debts_amount_check CHECK (amount > 0::numeric);
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.debts'::regclass and conname = 'debts_amount_usd_check'
  ) then
    alter table public.debts add constraint debts_amount_usd_check CHECK (amount_usd >= 0::numeric);
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.debts'::regclass and conname = 'debts_check'
  ) then
    alter table public.debts add constraint debts_check CHECK (remaining >= 0::numeric AND remaining <= amount);
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.debts'::regclass and conname = 'debts_created_by_fkey'
  ) then
    alter table public.debts add constraint debts_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.debts'::regclass and conname = 'debts_customer_id_fkey'
  ) then
    alter table public.debts add constraint debts_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES profiles(id) ON DELETE CASCADE;
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.debts'::regclass and conname = 'debts_dollar_rate_check'
  ) then
    alter table public.debts add constraint debts_dollar_rate_check CHECK (dollar_rate >= 0::numeric);
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.debts'::regclass and conname = 'debts_financial_reference_pair_chk'
  ) then
    alter table public.debts add constraint debts_financial_reference_pair_chk CHECK (reference_kind IS NULL AND reference_id IS NULL OR (reference_kind = ANY (ARRAY['debt'::text, 'payment'::text])) AND reference_id IS NOT NULL);
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.debts'::regclass and conname = 'debts_items_check'
  ) then
    alter table public.debts add constraint debts_items_check CHECK (jsonb_typeof(items) = 'array'::text);
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.debts'::regclass and conname = 'debts_pkey'
  ) then
    alter table public.debts add constraint debts_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.debts'::regclass and conname = 'debts_status_check'
  ) then
    alter table public.debts add constraint debts_status_check CHECK (status = ANY (ARRAY['pending'::text, 'partial'::text, 'paid'::text]));
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.financial_events'::regclass and conname = 'financial_events_actor_id_fkey'
  ) then
    alter table public.financial_events add constraint financial_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.financial_events'::regclass and conname = 'financial_events_customer_id_fkey'
  ) then
    alter table public.financial_events add constraint financial_events_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES profiles(id) ON DELETE CASCADE;
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.financial_events'::regclass and conname = 'financial_events_event_type_check'
  ) then
    alter table public.financial_events add constraint financial_events_event_type_check CHECK (event_type = ANY (ARRAY['debt_created'::text, 'debt_updated'::text, 'debt_deleted'::text, 'payment_created'::text, 'payment_updated'::text, 'payment_deleted'::text]));
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.financial_events'::regclass and conname = 'financial_events_pkey'
  ) then
    alter table public.financial_events add constraint financial_events_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.notifications'::regclass and conname = 'notifications_customer_id_fkey'
  ) then
    alter table public.notifications add constraint notifications_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES profiles(id) ON DELETE CASCADE;
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.notifications'::regclass and conname = 'notifications_pkey'
  ) then
    alter table public.notifications add constraint notifications_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.notifications'::regclass and conname = 'notifications_sender_id_fkey'
  ) then
    alter table public.notifications add constraint notifications_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES profiles(id) ON DELETE SET NULL;
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.payments'::regclass and conname = 'payments_amount_check'
  ) then
    alter table public.payments add constraint payments_amount_check CHECK (amount > 0::numeric);
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.payments'::regclass and conname = 'payments_created_by_fkey'
  ) then
    alter table public.payments add constraint payments_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.payments'::regclass and conname = 'payments_debt_id_fkey'
  ) then
    alter table public.payments add constraint payments_debt_id_fkey FOREIGN KEY (debt_id) REFERENCES debts(id) ON DELETE CASCADE;
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.payments'::regclass and conname = 'payments_financial_reference_pair_chk'
  ) then
    alter table public.payments add constraint payments_financial_reference_pair_chk CHECK (reference_kind IS NULL AND reference_id IS NULL OR (reference_kind = ANY (ARRAY['debt'::text, 'payment'::text])) AND reference_id IS NOT NULL);
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.payments'::regclass and conname = 'payments_pkey'
  ) then
    alter table public.payments add constraint payments_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass and conname = 'profiles_admin_id_fkey'
  ) then
    alter table public.profiles add constraint profiles_admin_id_fkey FOREIGN KEY (admin_id) REFERENCES profiles(id) ON DELETE CASCADE;
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass and conname = 'profiles_admin_shape_chk'
  ) then
    alter table public.profiles add constraint profiles_admin_shape_chk CHECK (role = 'admin'::text AND admin_id IS NULL OR (role = ANY (ARRAY['employee'::text, 'customer'::text])) AND admin_id IS NOT NULL);
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass and conname = 'profiles_created_by_fkey'
  ) then
    alter table public.profiles add constraint profiles_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass and conname = 'profiles_debt_duration_check'
  ) then
    alter table public.profiles add constraint profiles_debt_duration_check CHECK (debt_duration >= 0);
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass and conname = 'profiles_debt_limit_check'
  ) then
    alter table public.profiles add constraint profiles_debt_limit_check CHECK (debt_limit >= 0::numeric);
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass and conname = 'profiles_id_fkey'
  ) then
    alter table public.profiles add constraint profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass and conname = 'profiles_phone_key'
  ) then
    alter table public.profiles add constraint profiles_phone_key UNIQUE (phone);
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass and conname = 'profiles_pkey'
  ) then
    alter table public.profiles add constraint profiles_pkey PRIMARY KEY (id);
  end if;
end $$;
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass and conname = 'profiles_role_check'
  ) then
    alter table public.profiles add constraint profiles_role_check CHECK (role = ANY (ARRAY['admin'::text, 'employee'::text, 'customer'::text]));
  end if;
end $$;

CREATE OR REPLACE FUNCTION private.audit_debt_financial_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_actor uuid;
  v_actor_name text := '';
  v_actor_role text := '';
  v_event_type text;
  v_metadata jsonb := '{}'::jsonb;
begin
  if tg_op = 'INSERT' then
    v_event_type := 'debt_created';
    v_actor := coalesce(new.created_by, auth.uid());
    v_metadata := jsonb_build_object(
      'due_date', new.due_date,
      'custom_date', new.custom_date
    );
  elsif tg_op = 'UPDATE' then
    -- Payment recording legitimately changes only remaining/status/updated_at.
    -- Do not emit a duplicate debt-edit event for that accounting update.
    if (to_jsonb(new) - 'remaining' - 'status' - 'updated_at')
       = (to_jsonb(old) - 'remaining' - 'status' - 'updated_at') then
      return new;
    end if;
    v_event_type := 'debt_updated';
    v_actor := coalesce(auth.uid(), new.created_by, old.created_by);
    v_metadata := jsonb_build_object(
      'old_amount', old.amount,
      'new_amount', new.amount,
      'old_description', old.description,
      'new_description', new.description,
      'old_due_date', old.due_date,
      'new_due_date', new.due_date,
      'old_currency', old.currency,
      'new_currency', new.currency,
      'items_changed', old.items is distinct from new.items,
      'receipt_changed', old.receipt_image_path is distinct from new.receipt_image_path
    );
  else
    v_event_type := 'debt_deleted';
    v_actor := coalesce(auth.uid(), old.created_by);
    v_metadata := jsonb_build_object(
      'due_date', old.due_date,
      'status', old.status
    );
  end if;

  if v_actor is not null then
    select p.name, p.role
      into v_actor_name, v_actor_role
    from public.profiles p
    where p.id = v_actor;
  end if;

  insert into public.financial_events (
    customer_id, debt_id, event_type, actor_id, actor_name, actor_role,
    amount, remaining, currency, description, metadata
  ) values (
    case when tg_op = 'DELETE' then old.customer_id else new.customer_id end,
    case when tg_op = 'DELETE' then old.id else new.id end,
    v_event_type,
    v_actor,
    coalesce(v_actor_name, ''),
    coalesce(v_actor_role, ''),
    case when tg_op = 'DELETE' then old.amount else new.amount end,
    case when tg_op = 'DELETE' then old.remaining else new.remaining end,
    case when tg_op = 'DELETE' then old.currency else new.currency end,
    case when tg_op = 'DELETE' then old.description else new.description end,
    v_metadata
  );

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.audit_payment_financial_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_debt_id uuid;
  v_customer uuid;
  v_currency text := 'IQD';
  v_remaining numeric := 0;
  v_actor uuid;
  v_actor_name text := '';
  v_actor_role text := '';
  v_event_type text;
  v_amount numeric := 0;
  v_note text := '';
  v_payment_id uuid;
  v_metadata jsonb := '{}'::jsonb;
begin
  if tg_op = 'DELETE' then
    v_debt_id := old.debt_id;
    v_actor := coalesce(auth.uid(), old.created_by);
    v_event_type := 'payment_deleted';
    v_amount := old.amount;
    v_note := old.note;
    v_payment_id := old.id;
  elsif tg_op = 'UPDATE' then
    if to_jsonb(new) = to_jsonb(old) then return new; end if;
    v_debt_id := new.debt_id;
    v_actor := coalesce(auth.uid(), new.created_by, old.created_by);
    v_event_type := 'payment_updated';
    v_amount := new.amount;
    v_note := new.note;
    v_payment_id := new.id;
    v_metadata := jsonb_build_object(
      'old_amount', old.amount,
      'new_amount', new.amount,
      'old_note', old.note,
      'new_note', new.note
    );
  else
    v_debt_id := new.debt_id;
    v_actor := coalesce(new.created_by, auth.uid());
    v_event_type := 'payment_created';
    v_amount := new.amount;
    v_note := new.note;
    v_payment_id := new.id;
  end if;

  select d.customer_id, d.currency, d.remaining
    into v_customer, v_currency, v_remaining
  from public.debts d
  where d.id = v_debt_id;

  -- During a parent debt cascade the debt may already be invisible. The debt
  -- deletion event itself is the canonical audit record, so skip duplicates.
  if v_customer is null then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if v_actor is not null then
    select p.name, p.role
      into v_actor_name, v_actor_role
    from public.profiles p
    where p.id = v_actor;
  end if;

  insert into public.financial_events (
    customer_id, debt_id, payment_id, event_type, actor_id, actor_name,
    actor_role, amount, remaining, currency, description, metadata
  ) values (
    v_customer, v_debt_id, v_payment_id, v_event_type, v_actor,
    coalesce(v_actor_name, ''), coalesce(v_actor_role, ''), v_amount,
    coalesce(v_remaining, 0), coalesce(v_currency, 'IQD'), v_note, v_metadata
  );

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.current_admin_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when p.role = 'admin' then p.id else p.admin_id end
  from public.profiles p
  join public.profiles tenant
    on tenant.id = case when p.role = 'admin' then p.id else p.admin_id end
  where p.id = auth.uid()
    and p.active = true
    and p.approved = true
    and (
      p.is_system_owner = true
      or (
        tenant.role = 'admin'
        and tenant.active = true
        and tenant.approved = true
        and (tenant.subscription_end is null or tenant.subscription_end >= now())
      )
    )
  limit 1
$function$;

CREATE OR REPLACE FUNCTION private.current_can_add_customers()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(p.role = 'admin' or p.can_add_customers, false)
  from public.profiles p
  where p.id = auth.uid()
  limit 1
$function$;

CREATE OR REPLACE FUNCTION private.current_can_edit_debts()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(p.role = 'admin' or p.can_edit_debts, false)
  from public.profiles p
  where p.id = auth.uid()
  limit 1
$function$;

CREATE OR REPLACE FUNCTION private.current_can_send_notifications()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(p.role = 'admin' or p.can_send_notifications, false)
  from public.profiles p
  where p.id = auth.uid()
  limit 1
$function$;

CREATE OR REPLACE FUNCTION private."current_role"()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select p.role
  from public.profiles p
  join public.profiles tenant
    on tenant.id = case when p.role = 'admin' then p.id else p.admin_id end
  where p.id = auth.uid()
    and p.active = true
    and p.approved = true
    and (
      p.is_system_owner = true
      or (
        tenant.role = 'admin'
        and tenant.active = true
        and tenant.approved = true
        and (tenant.subscription_end is null or tenant.subscription_end >= now())
      )
    )
  limit 1
$function$;

CREATE OR REPLACE FUNCTION private.debt_customer_id(target_debt uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select d.customer_id from public.debts d where d.id = target_debt limit 1
$function$;

CREATE OR REPLACE FUNCTION private.debt_tenant_id(target_debt uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when p.role = 'admin' then p.id else p.admin_id end
  from public.debts d
  join public.profiles p on p.id = d.customer_id
  where d.id = target_debt
  limit 1
$function$;

CREATE OR REPLACE FUNCTION private.guard_notification_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then
    return new;
  end if;
  if old.customer_id = auth.uid()
     and new.id = old.id
     and new.customer_id = old.customer_id
     and new.sender_id is not distinct from old.sender_id
     and new.message = old.message
     and new.type = old.type
     and new.created_at = old.created_at
  then
    return new;
  end if;
  raise exception 'only is_read may be changed by the notification recipient';
end;
$function$;

CREATE OR REPLACE FUNCTION private.guard_profile_authority_fields()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
begin
  if auth.role() = 'service_role' or current_user in ('postgres', 'supabase_admin', 'service_role') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.is_system_owner := false;
    return new;
  end if;

  if new.role is distinct from old.role
     or new.admin_id is distinct from old.admin_id
     or new.created_by is distinct from old.created_by
     or new.is_system_owner is distinct from old.is_system_owner
     or new.subscription_end is distinct from old.subscription_end
     or new.approved is distinct from old.approved
     or new.active is distinct from old.active
     or new.debt_limit is distinct from old.debt_limit
     or new.debt_duration is distinct from old.debt_duration
     or new.can_add_customers is distinct from old.can_add_customers
     or new.can_set_debt_limit is distinct from old.can_set_debt_limit
     or new.can_set_due_date is distinct from old.can_set_due_date
     or new.can_edit_debts is distinct from old.can_edit_debts
     or new.can_send_notifications is distinct from old.can_send_notifications then
    raise exception 'protected_profile_authority_fields';
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.guard_profile_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor uuid := auth.uid();
  actor_role text;
  actor_admin uuid;
  actor_can_add boolean := false;
  actor_can_limit boolean := false;
  actor_can_due boolean := false;
begin
  if actor is null then
    return new;
  end if;

  select p.role,
         case when p.role = 'admin' then p.id else p.admin_id end,
         p.can_add_customers,
         p.can_set_debt_limit,
         p.can_set_due_date
    into actor_role, actor_admin, actor_can_add, actor_can_limit, actor_can_due
  from public.profiles p
  where p.id = actor;

  if old.id = actor then
    if new.id is distinct from old.id
       or new.role is distinct from old.role
       or new.admin_id is distinct from old.admin_id
       or new.created_by is distinct from old.created_by
       or new.approved is distinct from old.approved
       or new.active is distinct from old.active
       or new.debt_limit is distinct from old.debt_limit
       or new.debt_duration is distinct from old.debt_duration
       or new.can_add_customers is distinct from old.can_add_customers
       or new.can_set_debt_limit is distinct from old.can_set_debt_limit
       or new.can_set_due_date is distinct from old.can_set_due_date
       or new.can_edit_debts is distinct from old.can_edit_debts
       or new.can_send_notifications is distinct from old.can_send_notifications
       or new.subscription_end is distinct from old.subscription_end
    then
      raise exception 'profile privilege fields cannot be changed by the profile owner';
    end if;
    if old.role <> 'admin' and new.market_name is distinct from old.market_name then
      raise exception 'only admins may change market_name';
    end if;
    return new;
  end if;

  if actor_role = 'admin' and old.admin_id = actor then
    if new.id is distinct from old.id
       or new.role is distinct from old.role
       or new.admin_id is distinct from old.admin_id
       or new.created_by is distinct from old.created_by
       or new.subscription_end is distinct from old.subscription_end
    then
      raise exception 'admin cannot change subordinate identity or subscription ownership fields';
    end if;
    return new;
  end if;

  if actor_role = 'employee' and old.role = 'customer' and old.admin_id = actor_admin then
    if new.id is distinct from old.id
       or new.role is distinct from old.role
       or new.admin_id is distinct from old.admin_id
       or new.created_by is distinct from old.created_by
       or new.active is distinct from old.active
       or new.can_add_customers is distinct from old.can_add_customers
       or new.can_set_debt_limit is distinct from old.can_set_debt_limit
       or new.can_set_due_date is distinct from old.can_set_due_date
       or new.can_edit_debts is distinct from old.can_edit_debts
       or new.can_send_notifications is distinct from old.can_send_notifications
       or new.subscription_end is distinct from old.subscription_end
       or new.market_name is distinct from old.market_name
    then
      raise exception 'employee cannot change customer privilege fields';
    end if;
    if new.approved is distinct from old.approved and not actor_can_add then
      raise exception 'employee lacks permission to approve customers';
    end if;
    if new.debt_limit is distinct from old.debt_limit and not actor_can_limit then
      raise exception 'employee lacks permission to change debt limit';
    end if;
    if new.debt_duration is distinct from old.debt_duration and not actor_can_due then
      raise exception 'employee lacks permission to change debt duration';
    end if;
    return new;
  end if;

  raise exception 'profile update not permitted';
end;
$function$;

CREATE OR REPLACE FUNCTION private.populate_financial_reference()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_customer_id uuid;
  v_ref_customer_id uuid;
  v_ref_amount numeric;
  v_ref_currency text;
  v_ref_text text;
  v_ref_created_at timestamptz;
begin
  if tg_op = 'UPDATE'
     and new.reference_kind is not distinct from old.reference_kind
     and new.reference_id is not distinct from old.reference_id then
    return new;
  end if;

  if new.reference_kind is null and new.reference_id is null then
    new.reference_snapshot := '{}'::jsonb;
    return new;
  end if;

  if new.reference_kind is null
     or new.reference_id is null
     or new.reference_kind not in ('debt', 'payment') then
    raise exception 'invalid_financial_reference' using errcode = '22023';
  end if;

  if tg_table_name = 'debts' then
    v_customer_id := new.customer_id;
    if new.reference_kind = 'debt' and new.reference_id = new.id then
      raise exception 'self_financial_reference' using errcode = '22023';
    end if;
  elsif tg_table_name = 'payments' then
    select d.customer_id into v_customer_id
    from public.debts d
    where d.id = new.debt_id;
    if new.reference_kind = 'payment' and new.reference_id = new.id then
      raise exception 'self_financial_reference' using errcode = '22023';
    end if;
  else
    raise exception 'unsupported_financial_reference_table' using errcode = '22023';
  end if;

  if v_customer_id is null then
    raise exception 'financial_reference_customer_not_found' using errcode = '23503';
  end if;

  if new.reference_kind = 'debt' then
    select d.customer_id,
           d.amount,
           coalesce(nullif(d.currency, ''), 'IQD'),
           nullif(trim(d.description), ''),
           d.created_at
      into v_ref_customer_id, v_ref_amount, v_ref_currency, v_ref_text, v_ref_created_at
    from public.debts d
    where d.id = new.reference_id;
  else
    select d.customer_id,
           p.amount,
           coalesce(nullif(d.currency, ''), 'IQD'),
           nullif(trim(p.note), ''),
           p.created_at
      into v_ref_customer_id, v_ref_amount, v_ref_currency, v_ref_text, v_ref_created_at
    from public.payments p
    join public.debts d on d.id = p.debt_id
    where p.id = new.reference_id;
  end if;

  if v_ref_customer_id is null then
    raise exception 'financial_reference_not_found' using errcode = '23503';
  end if;

  if v_ref_customer_id <> v_customer_id then
    raise exception 'cross_customer_financial_reference_forbidden' using errcode = '42501';
  end if;

  new.reference_snapshot := jsonb_build_object(
    'kind', new.reference_kind,
    'id', new.reference_id,
    'amount', coalesce(v_ref_amount, 0),
    'currency', coalesce(v_ref_currency, 'IQD'),
    'text', coalesce(v_ref_text, ''),
    'created_at', v_ref_created_at
  );

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.profile_tenant_id(target_profile uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when p.role = 'admin' then p.id else p.admin_id end
  from public.profiles p
  where p.id = target_profile
  limit 1
$function$;

CREATE OR REPLACE FUNCTION private.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.validate_profile_admin_link()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  linked_role text;
begin
  if new.role = 'admin' then
    if new.admin_id is not null then
      raise exception 'admin profile must not have admin_id';
    end if;
    return new;
  end if;

  if new.admin_id is null then
    raise exception 'employee/customer profile requires admin_id';
  end if;

  select p.role into linked_role
  from public.profiles p
  where p.id = new.admin_id;

  if linked_role is distinct from 'admin' then
    raise exception 'admin_id must reference an admin profile';
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_telegram_credentials()
 RETURNS TABLE(bot_token text, chat_id text)
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select coalesce(tc.bot_token, ''), coalesce(tc.chat_id, '')
  from private.telegram_credentials tc
  where tc.user_id = auth.uid();
$function$;

CREATE OR REPLACE FUNCTION public.get_telegram_credentials_for_service(uuid)
 RETURNS TABLE(bot_token text, chat_id text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(tc.bot_token, ''), coalesce(tc.chat_id, '')
  from private.telegram_credentials tc
  where tc.user_id = p_user_id;
$function$;

CREATE OR REPLACE FUNCTION public.list_active_markets()
 RETURNS TABLE(id uuid, name text, market_name text)
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select p.id, p.name, p.market_name
  from public.profiles p
  where p.role = 'admin'
    and p.active = true
    and (p.subscription_end is null or p.subscription_end >= now())
  order by p.created_at desc;
$function$;

CREATE OR REPLACE FUNCTION public.record_payment(p_debt_id uuid, p_amount numeric, p_note text DEFAULT ''::text, p_reference_kind text DEFAULT NULL::text, p_reference_id uuid DEFAULT NULL::uuid)
 RETURNS payments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_admin_id uuid;
  v_debt public.debts%rowtype;
  v_payment public.payments%rowtype;
  v_new_remaining numeric;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select p.role,
         case when p.role = 'admin' then p.id else p.admin_id end
    into v_role, v_admin_id
  from public.profiles p
  where p.id = v_uid
  limit 1;

  if v_role not in ('admin', 'employee') or v_admin_id is null then
    raise exception 'payment_forbidden' using errcode = '42501';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_payment_amount' using errcode = '22023';
  end if;

  select d.* into v_debt
  from public.debts d
  join public.profiles customer on customer.id = d.customer_id
  where d.id = p_debt_id
    and (case when customer.role = 'admin' then customer.id else customer.admin_id end) = v_admin_id
  for update of d;

  if not found then
    raise exception 'debt_not_found_or_forbidden' using errcode = '42501';
  end if;

  if v_debt.remaining <= 0 then
    raise exception 'debt_already_paid' using errcode = '22023';
  end if;

  v_new_remaining := greatest(v_debt.remaining - p_amount, 0);

  insert into public.payments (
    debt_id, amount, note, created_by, reference_kind, reference_id
  ) values (
    p_debt_id,
    least(p_amount, v_debt.remaining),
    coalesce(p_note, ''),
    v_uid,
    p_reference_kind,
    p_reference_id
  )
  returning * into v_payment;

  update public.debts
  set remaining = v_new_remaining,
      status = case when v_new_remaining <= 0 then 'paid' else 'partial' end,
      updated_at = now()
  where id = p_debt_id;

  return v_payment;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_my_telegram_credentials(text, text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  insert into private.telegram_credentials(user_id, bot_token, chat_id, updated_at)
  values (auth.uid(), coalesce(p_bot_token, ''), coalesce(p_chat_id, ''), now())
  on conflict (user_id) do update
    set bot_token = excluded.bot_token,
        chat_id = excluded.chat_id,
        updated_at = now();
end;
$function$;

CREATE INDEX idx_debts_created_at ON public.debts USING btree (created_at DESC);
CREATE INDEX idx_debts_created_by ON public.debts USING btree (created_by);
CREATE INDEX idx_debts_customer_id ON public.debts USING btree (customer_id);
CREATE INDEX idx_debts_customer_status ON public.debts USING btree (customer_id, status);
CREATE INDEX idx_debts_customer_timeline ON public.debts USING btree (customer_id, COALESCE(custom_date, created_at) DESC, id DESC);
CREATE INDEX idx_debts_due_date ON public.debts USING btree (due_date) WHERE (status <> 'paid'::text);
CREATE INDEX financial_events_customer_created_idx ON public.financial_events USING btree (customer_id, created_at DESC);
CREATE INDEX financial_events_debt_idx ON public.financial_events USING btree (debt_id) WHERE (debt_id IS NOT NULL);
CREATE INDEX financial_events_payment_idx ON public.financial_events USING btree (payment_id) WHERE (payment_id IS NOT NULL);
CREATE INDEX idx_financial_events_actor_id ON public.financial_events USING btree (actor_id);
CREATE INDEX idx_financial_events_customer_timeline_v2 ON public.financial_events USING btree (customer_id, created_at DESC, id DESC);
CREATE INDEX idx_notifications_customer_unread ON public.notifications USING btree (customer_id, is_read, created_at DESC);
CREATE INDEX idx_notifications_sender_id ON public.notifications USING btree (sender_id);
CREATE INDEX idx_payments_created_at ON public.payments USING btree (created_at DESC);
CREATE INDEX idx_payments_created_by ON public.payments USING btree (created_by);
CREATE INDEX idx_payments_debt_id ON public.payments USING btree (debt_id);
CREATE INDEX idx_payments_debt_timeline ON public.payments USING btree (debt_id, created_at DESC, id DESC);
CREATE INDEX idx_profiles_admin_id ON public.profiles USING btree (admin_id);
CREATE INDEX idx_profiles_admin_role ON public.profiles USING btree (admin_id, role);
CREATE INDEX idx_profiles_created_by ON public.profiles USING btree (created_by);
CREATE INDEX idx_profiles_role ON public.profiles USING btree (role);
CREATE UNIQUE INDEX one_system_owner_idx ON public.profiles USING btree (is_system_owner) WHERE (is_system_owner = true);

alter table public.profiles enable row level security;
alter table public.debts enable row level security;
alter table public.payments enable row level security;
alter table public.notifications enable row level security;
alter table public.financial_events enable row level security;

drop policy if exists "debts_delete_staff" on public.debts;
create policy "debts_delete_staff" on public.debts for delete to authenticated using ((((private."current_role"() = 'admin'::text) OR ((private."current_role"() = 'employee'::text) AND private.current_can_edit_debts())) AND (private.profile_tenant_id(customer_id) = private.current_admin_id())));
drop policy if exists "debts_insert_staff" on public.debts;
create policy "debts_insert_staff" on public.debts for insert to authenticated with check (((private."current_role"() = ANY (ARRAY['admin'::text, 'employee'::text])) AND (private.profile_tenant_id(customer_id) = private.current_admin_id()) AND (created_by = ( SELECT auth.uid() AS uid))));
drop policy if exists "debts_select_authorized" on public.debts;
create policy "debts_select_authorized" on public.debts for select to authenticated using (((customer_id = ( SELECT auth.uid() AS uid)) OR ((private."current_role"() = ANY (ARRAY['admin'::text, 'employee'::text])) AND (private.profile_tenant_id(customer_id) = private.current_admin_id()))));
drop policy if exists "debts_update_staff" on public.debts;
create policy "debts_update_staff" on public.debts for update to authenticated using ((((private."current_role"() = 'admin'::text) OR ((private."current_role"() = 'employee'::text) AND private.current_can_edit_debts())) AND (private.profile_tenant_id(customer_id) = private.current_admin_id()))) with check ((((private."current_role"() = 'admin'::text) OR ((private."current_role"() = 'employee'::text) AND private.current_can_edit_debts())) AND (private.profile_tenant_id(customer_id) = private.current_admin_id())));
drop policy if exists "financial_events_select_authorized" on public.financial_events;
create policy "financial_events_select_authorized" on public.financial_events for select to authenticated using (((customer_id = ( SELECT auth.uid() AS uid)) OR ((private."current_role"() = ANY (ARRAY['admin'::text, 'employee'::text])) AND (private.profile_tenant_id(customer_id) = private.current_admin_id()))));
drop policy if exists "notifications_delete_authorized" on public.notifications;
create policy "notifications_delete_authorized" on public.notifications for delete to authenticated using (((customer_id = ( SELECT auth.uid() AS uid)) OR ((private."current_role"() = 'admin'::text) AND (private.profile_tenant_id(customer_id) = private.current_admin_id()))));
drop policy if exists "notifications_insert_staff" on public.notifications;
create policy "notifications_insert_staff" on public.notifications for insert to authenticated with check ((((private."current_role"() = 'admin'::text) OR ((private."current_role"() = 'employee'::text) AND private.current_can_send_notifications())) AND (private.profile_tenant_id(customer_id) = private.current_admin_id()) AND (sender_id = ( SELECT auth.uid() AS uid))));
drop policy if exists "notifications_select_authorized" on public.notifications;
create policy "notifications_select_authorized" on public.notifications for select to authenticated using (((customer_id = ( SELECT auth.uid() AS uid)) OR ((private."current_role"() = ANY (ARRAY['admin'::text, 'employee'::text])) AND (private.profile_tenant_id(customer_id) = private.current_admin_id()))));
drop policy if exists "notifications_update_recipient" on public.notifications;
create policy "notifications_update_recipient" on public.notifications for update to authenticated using ((customer_id = ( SELECT auth.uid() AS uid))) with check ((customer_id = ( SELECT auth.uid() AS uid)));
drop policy if exists "payments_delete_admin" on public.payments;
create policy "payments_delete_admin" on public.payments for delete to authenticated using (((private."current_role"() = 'admin'::text) AND (private.debt_tenant_id(debt_id) = private.current_admin_id())));
drop policy if exists "payments_insert_staff" on public.payments;
create policy "payments_insert_staff" on public.payments for insert to authenticated with check (((private."current_role"() = ANY (ARRAY['admin'::text, 'employee'::text])) AND (private.debt_tenant_id(debt_id) = private.current_admin_id()) AND (created_by = ( SELECT auth.uid() AS uid))));
drop policy if exists "payments_select_authorized" on public.payments;
create policy "payments_select_authorized" on public.payments for select to authenticated using (((private.debt_customer_id(debt_id) = ( SELECT auth.uid() AS uid)) OR ((private."current_role"() = ANY (ARRAY['admin'::text, 'employee'::text])) AND (private.debt_tenant_id(debt_id) = private.current_admin_id()))));
drop policy if exists "payments_update_admin" on public.payments;
create policy "payments_update_admin" on public.payments for update to authenticated using (((private."current_role"() = 'admin'::text) AND (private.debt_tenant_id(debt_id) = private.current_admin_id()))) with check (((private."current_role"() = 'admin'::text) AND (private.debt_tenant_id(debt_id) = private.current_admin_id())));
drop policy if exists "profiles_delete_admin" on public.profiles;
create policy "profiles_delete_admin" on public.profiles for delete to authenticated using (((private."current_role"() = 'admin'::text) AND (admin_id = ( SELECT auth.uid() AS uid))));
drop policy if exists "profiles_insert_authorized" on public.profiles;
create policy "profiles_insert_authorized" on public.profiles for insert to authenticated with check ((((id = ( SELECT auth.uid() AS uid)) AND (role = 'customer'::text) AND (admin_id IS NOT NULL) AND (approved = false) AND (created_by IS NULL)) OR ((private."current_role"() = 'admin'::text) AND (admin_id = ( SELECT auth.uid() AS uid)) AND (role = ANY (ARRAY['employee'::text, 'customer'::text])) AND (created_by = ( SELECT auth.uid() AS uid))) OR ((private."current_role"() = 'employee'::text) AND private.current_can_add_customers() AND (role = 'customer'::text) AND (admin_id = private.current_admin_id()) AND (created_by = ( SELECT auth.uid() AS uid)))));
drop policy if exists "profiles_select_public_markets" on public.profiles;
create policy "profiles_select_public_markets" on public.profiles for select to anon using (((role = 'admin'::text) AND (active = true) AND ((subscription_end IS NULL) OR (subscription_end >= now()))));
drop policy if exists "profiles_select_tenant" on public.profiles;
create policy "profiles_select_tenant" on public.profiles for select to authenticated using (((id = ( SELECT auth.uid() AS uid)) OR ((private."current_role"() = 'admin'::text) AND ((id = ( SELECT auth.uid() AS uid)) OR (admin_id = ( SELECT auth.uid() AS uid)))) OR ((private."current_role"() = 'employee'::text) AND ((id = private.current_admin_id()) OR ((admin_id = private.current_admin_id()) AND (role = ANY (ARRAY['employee'::text, 'customer'::text]))))) OR ((private."current_role"() = 'customer'::text) AND ((id = private.current_admin_id()) OR ((admin_id = private.current_admin_id()) AND (role = 'employee'::text))))));
drop policy if exists "profiles_update_authorized" on public.profiles;
create policy "profiles_update_authorized" on public.profiles for update to authenticated using (((id = ( SELECT auth.uid() AS uid)) OR ((private."current_role"() = 'admin'::text) AND (admin_id = ( SELECT auth.uid() AS uid))) OR ((private."current_role"() = 'employee'::text) AND (role = 'customer'::text) AND (admin_id = private.current_admin_id())))) with check (((id = ( SELECT auth.uid() AS uid)) OR ((private."current_role"() = 'admin'::text) AND (admin_id = ( SELECT auth.uid() AS uid))) OR ((private."current_role"() = 'employee'::text) AND (role = 'customer'::text) AND (admin_id = private.current_admin_id()))));
drop policy if exists "receipts_delete_staff" on storage.objects;
create policy "receipts_delete_staff" on storage.objects for delete to authenticated using (((bucket_id = 'receipts'::text) AND (private."current_role"() = ANY (ARRAY['admin'::text, 'employee'::text])) AND ((storage.foldername(name))[1] = (private.current_admin_id())::text)));
drop policy if exists "receipts_insert_staff" on storage.objects;
create policy "receipts_insert_staff" on storage.objects for insert to authenticated with check (((bucket_id = 'receipts'::text) AND (private."current_role"() = ANY (ARRAY['admin'::text, 'employee'::text])) AND ((storage.foldername(name))[1] = (private.current_admin_id())::text)));
drop policy if exists "receipts_select" on storage.objects;
create policy "receipts_select" on storage.objects for select to authenticated using (((bucket_id = 'receipts'::text) AND ((storage.foldername(name))[1] = (private.current_admin_id())::text) AND ((private."current_role"() = ANY (ARRAY['admin'::text, 'employee'::text])) OR ((private."current_role"() = 'customer'::text) AND ((storage.foldername(name))[2] = (( SELECT auth.uid() AS uid))::text)))));
drop policy if exists "receipts_update_staff" on storage.objects;
create policy "receipts_update_staff" on storage.objects for update to authenticated using (((bucket_id = 'receipts'::text) AND (private."current_role"() = ANY (ARRAY['admin'::text, 'employee'::text])) AND ((storage.foldername(name))[1] = (private.current_admin_id())::text))) with check (((bucket_id = 'receipts'::text) AND (private."current_role"() = ANY (ARRAY['admin'::text, 'employee'::text])) AND ((storage.foldername(name))[1] = (private.current_admin_id())::text)));

drop trigger if exists debts_financial_audit on public.debts;
CREATE TRIGGER debts_financial_audit AFTER INSERT OR DELETE OR UPDATE ON public.debts FOR EACH ROW EXECUTE FUNCTION private.audit_debt_financial_event();
drop trigger if exists debts_populate_financial_reference on public.debts;
CREATE TRIGGER debts_populate_financial_reference BEFORE INSERT OR UPDATE OF reference_kind, reference_id ON public.debts FOR EACH ROW EXECUTE FUNCTION private.populate_financial_reference();
drop trigger if exists debts_set_updated_at on public.debts;
CREATE TRIGGER debts_set_updated_at BEFORE UPDATE ON public.debts FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
drop trigger if exists notifications_guard_update on public.notifications;
CREATE TRIGGER notifications_guard_update BEFORE UPDATE ON public.notifications FOR EACH ROW EXECUTE FUNCTION private.guard_notification_update();
drop trigger if exists payments_financial_audit on public.payments;
CREATE TRIGGER payments_financial_audit AFTER INSERT OR DELETE OR UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION private.audit_payment_financial_event();
drop trigger if exists payments_populate_financial_reference on public.payments;
CREATE TRIGGER payments_populate_financial_reference BEFORE INSERT OR UPDATE OF reference_kind, reference_id ON public.payments FOR EACH ROW EXECUTE FUNCTION private.populate_financial_reference();
drop trigger if exists guard_profile_authority_fields on public.profiles;
CREATE TRIGGER guard_profile_authority_fields BEFORE INSERT OR UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION private.guard_profile_authority_fields();
drop trigger if exists profiles_guard_update on public.profiles;
CREATE TRIGGER profiles_guard_update BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION private.guard_profile_update();
drop trigger if exists profiles_set_updated_at on public.profiles;
CREATE TRIGGER profiles_set_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
drop trigger if exists profiles_validate_admin_link on public.profiles;
CREATE TRIGGER profiles_validate_admin_link BEFORE INSERT OR UPDATE OF role, admin_id ON public.profiles FOR EACH ROW EXECUTE FUNCTION private.validate_profile_admin_link();

grant DELETE, INSERT, SELECT, UPDATE on table public.debts to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public.debts to service_role;
grant SELECT on table public.financial_events to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public.financial_events to service_role;
grant DELETE, INSERT, SELECT, UPDATE on table public.notifications to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public.notifications to service_role;
grant DELETE, INSERT, SELECT, UPDATE on table public.payments to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public.payments to service_role;
grant SELECT on table public.profiles to authenticated;
grant DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public.profiles to service_role;

revoke execute on all functions in schema public from public, anon, authenticated;
revoke execute on all functions in schema private from public, anon;
grant usage on schema private to authenticated, service_role;
grant execute on all functions in schema private to authenticated, service_role;
grant execute on function public.get_my_telegram_credentials() to authenticated;
grant execute on function public.get_my_telegram_credentials() to service_role;
grant execute on function public.get_telegram_credentials_for_service(uuid) to service_role;
grant execute on function public.list_active_markets() to anon;
grant execute on function public.list_active_markets() to authenticated;
grant execute on function public.list_active_markets() to service_role;
grant execute on function public.record_payment(uuid, numeric, text, text, uuid) to authenticated;
grant execute on function public.record_payment(uuid, numeric, text, text, uuid) to service_role;
grant execute on function public.set_my_telegram_credentials(text, text) to authenticated;
grant execute on function public.set_my_telegram_credentials(text, text) to service_role;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types) values ('receipts','receipts',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf']::text[]) on conflict (id) do update set name=excluded.name, public=excluded.public, file_size_limit=excluded.file_size_limit, allowed_mime_types=excluded.allowed_mime_types;

