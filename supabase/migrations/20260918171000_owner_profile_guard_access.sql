-- Permit System Owner RPCs to change platform-level Admin metadata only.
-- The Owner still cannot modify market business content or Admin identity/permissions.

create or replace function private.guard_profile_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  actor_role text;
  actor_admin uuid;
  actor_can_add boolean := false;
  actor_can_limit boolean := false;
  actor_can_due boolean := false;
  actor_is_owner boolean := false;
begin
  if actor is null then
    return new;
  end if;

  select p.role,
         case when p.role = 'admin' then p.id else p.admin_id end,
         p.can_add_customers,
         p.can_set_debt_limit,
         p.can_set_due_date,
         coalesce(p.is_system_owner, false)
    into actor_role, actor_admin, actor_can_add, actor_can_limit, actor_can_due,
         actor_is_owner
  from public.profiles p
  where p.id = actor;

  -- System Owner may change only platform/account lifecycle metadata on
  -- non-owner Admin profiles. Identity, market profile fields and all
  -- business permissions remain immutable through this path.
  if actor_is_owner
     and old.role = 'admin'
     and coalesce(old.is_system_owner, false) = false then
    if new.id is distinct from old.id
       or new.name is distinct from old.name
       or new.father_name is distinct from old.father_name
       or new.grandfather_name is distinct from old.grandfather_name
       or new.phone is distinct from old.phone
       or new.role is distinct from old.role
       or new.market_name is distinct from old.market_name
       or new.admin_id is distinct from old.admin_id
       or new.created_by is distinct from old.created_by
       or new.approved is distinct from old.approved
       or new.debt_limit is distinct from old.debt_limit
       or new.debt_duration is distinct from old.debt_duration
       or new.can_add_customers is distinct from old.can_add_customers
       or new.can_set_debt_limit is distinct from old.can_set_debt_limit
       or new.can_set_due_date is distinct from old.can_set_due_date
       or new.can_edit_debts is distinct from old.can_edit_debts
       or new.can_send_notifications is distinct from old.can_send_notifications
       or new.telegram_chat_id is distinct from old.telegram_chat_id
       or new.is_system_owner is distinct from old.is_system_owner
       or new.can_view_customers is distinct from old.can_view_customers
       or new.can_edit_customers is distinct from old.can_edit_customers
       or new.can_delete_customers is distinct from old.can_delete_customers
       or new.can_view_debts is distinct from old.can_view_debts
       or new.can_add_debts is distinct from old.can_add_debts
       or new.can_delete_debts is distinct from old.can_delete_debts
       or new.can_record_payments is distinct from old.can_record_payments
       or new.can_view_financial_reports is distinct from old.can_view_financial_reports
       or new.can_export_data is distinct from old.can_export_data
       or new.can_import_data is distinct from old.can_import_data
    then
      raise exception 'system owner may only change platform account metadata';
    end if;
    return new;
  end if;

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
$$;
