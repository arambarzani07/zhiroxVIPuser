begin;

do $test$
declare
  v_admin_a uuid := '00000000-0000-0000-0000-000000000101';
  v_admin_b uuid := '00000000-0000-0000-0000-000000000201';
  v_employee_ok uuid := '00000000-0000-0000-0000-000000000111';
  v_employee_no uuid := '00000000-0000-0000-0000-000000000112';
  v_customer_a uuid := '00000000-0000-0000-0000-000000000121';
  v_customer_b uuid := '00000000-0000-0000-0000-000000000221';
  v_outbox_a uuid;
  v_outbox_b uuid;
  v_sub uuid;
begin
  if to_regclass('public.customer_push_link_tokens') is null
     or to_regclass('public.customer_push_subscriptions') is null
     or to_regclass('public.notification_outbox') is null
     or to_regclass('public.notification_deliveries') is null
     or to_regclass('public.customer_push_rate_limits') is null then
    raise exception 'customer push schema missing';
  end if;

  insert into auth.users(
    id,aud,role,email,encrypted_password,email_confirmed_at,
    raw_app_meta_data,raw_user_meta_data,created_at,updated_at
  ) values
    (v_admin_a,'authenticated','authenticated','push-admin-a@test.local','',now(),'{}','{}',now(),now()),
    (v_admin_b,'authenticated','authenticated','push-admin-b@test.local','',now(),'{}','{}',now(),now()),
    (v_employee_ok,'authenticated','authenticated','push-emp-ok@test.local','',now(),'{}','{}',now(),now()),
    (v_employee_no,'authenticated','authenticated','push-emp-no@test.local','',now(),'{}','{}',now(),now()),
    (v_customer_a,'authenticated','authenticated','push-cust-a@test.local','',now(),'{}','{}',now(),now()),
    (v_customer_b,'authenticated','authenticated','push-cust-b@test.local','',now(),'{}','{}',now(),now());

  insert into public.profiles(
    id,name,phone,role,market_name,admin_id,created_by,approved,active,can_send_notifications
  ) values
    (v_admin_a,'Admin A','push-admin-a','admin','Market A',null,v_admin_a,true,true,true),
    (v_admin_b,'Admin B','push-admin-b','admin','Market B',null,v_admin_b,true,true,true),
    (v_employee_ok,'Employee OK','push-emp-ok','employee','',v_admin_a,v_admin_a,true,true,true),
    (v_employee_no,'Employee NO','push-emp-no','employee','',v_admin_a,v_admin_a,true,true,false),
    (v_customer_a,'Customer A','push-cust-a','customer','',v_admin_a,v_admin_a,true,true,false),
    (v_customer_b,'Customer B','push-cust-b','customer','',v_admin_b,v_admin_b,true,true,false);

  perform public.manage_customer_push_link(
    v_admin_a, v_customer_a, repeat('a',64), now()+interval '15 minutes'
  );
  perform public.manage_customer_push_link(
    v_employee_ok, v_customer_a, repeat('b',64), now()+interval '15 minutes'
  );

  begin
    perform public.manage_customer_push_link(
      v_employee_no, v_customer_a, repeat('c',64), now()+interval '15 minutes'
    );
    raise exception 'employee without notification permission was allowed';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.manage_customer_push_link(
      v_admin_a, v_customer_b, repeat('d',64), now()+interval '15 minutes'
    );
    raise exception 'cross-tenant push link was allowed';
  exception when insufficient_privilege then null;
  end;

  perform public.manage_customer_push_link(
    v_admin_a, v_customer_a, repeat('e',64), now()+interval '15 minutes'
  );
  perform public.redeem_customer_push_subscription_service(
    repeat('e',64),'https://push.example/device-a','p256-a','auth-a',repeat('1',64),'ua','ios'
  );

  begin
    perform public.redeem_customer_push_subscription_service(
      repeat('e',64),'https://push.example/device-b','p256-b','auth-b',repeat('2',64),'ua','ios'
    );
    raise exception 'used token was accepted twice';
  exception when no_data_found then null;
  end;

  perform public.manage_customer_push_link(
    v_admin_a, v_customer_a, repeat('f',64), now()-interval '1 minute'
  );
  begin
    perform public.redeem_customer_push_subscription_service(
      repeat('f',64),'https://push.example/device-c','p256-c','auth-c',repeat('3',64),'ua','android'
    );
    raise exception 'expired token was accepted';
  exception when no_data_found then null;
  end;

  select id into v_sub
  from public.customer_push_subscriptions
  where endpoint='https://push.example/device-a' and active=true;

  v_outbox_a := public.enqueue_customer_push_event_service(
    v_admin_a,v_customer_a,'debt_created','00000000-0000-0000-0000-000000000301',
    'debt_created:00000000-0000-0000-0000-000000000301',
    '{"amount":1000,"currency":"IQD","remaining_iqd":1000,"market_name":"Market A","occurred_at":"2026-09-17T00:00:00Z"}'::jsonb
  );
  v_outbox_b := public.enqueue_customer_push_event_service(
    v_admin_a,v_customer_a,'debt_created','00000000-0000-0000-0000-000000000301',
    'debt_created:00000000-0000-0000-0000-000000000301',
    '{"amount":9999,"currency":"IQD","remaining_iqd":9999,"market_name":"changed","occurred_at":"2026-09-17T00:00:00Z"}'::jsonb
  );

  if v_outbox_a <> v_outbox_b then
    raise exception 'idempotent enqueue returned different event ids';
  end if;
  if (select payload->>'amount' from public.notification_outbox where id=v_outbox_a) <> '1000' then
    raise exception 'duplicate enqueue mutated immutable payload';
  end if;

  begin
    perform public.enqueue_customer_push_event_service(
      v_admin_a,v_customer_a,'debt_updated','00000000-0000-0000-0000-000000000302',
      'debt_updated:00000000-0000-0000-0000-000000000302','{}'::jsonb
    );
    raise exception 'unsupported event type accepted';
  exception when check_violation then null;
  end;

  insert into public.notification_deliveries(outbox_id,subscription_id)
  values(v_outbox_a,v_sub);
  begin
    insert into public.notification_deliveries(outbox_id,subscription_id)
    values(v_outbox_a,v_sub);
    raise exception 'duplicate delivery pair accepted';
  exception when unique_violation then null;
  end;

  if has_table_privilege('authenticated','public.customer_push_subscriptions','SELECT')
     or has_table_privilege('authenticated','public.customer_push_subscriptions','INSERT')
     or has_table_privilege('anon','public.customer_push_subscriptions','SELECT') then
    raise exception 'client retained direct subscription table privilege';
  end if;
end
$test$;

rollback;
select 'customer QR web push regression passed' as result;
