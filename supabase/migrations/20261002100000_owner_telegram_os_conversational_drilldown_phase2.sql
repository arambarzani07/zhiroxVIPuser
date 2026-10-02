alter table private.owner_telegram_os_context
  add column if not exists last_entity_type text,
  add column if not exists last_entity_id text,
  add column if not exists last_entity_name text,
  add column if not exists last_list_type text,
  add column if not exists last_result_items jsonb not null default '[]'::jsonb,
  add column if not exists last_recommendations jsonb not null default '[]'::jsonb;

create or replace function public.ask_owner_telegram_os_phase2_service(
  p_owner_user_id uuid,
  p_text text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_raw text := btrim(coalesce(p_text,''));
  v_text text;
  v_ctx private.owner_telegram_os_context%rowtype;
  v_base jsonb;
  v_intent text;
  v_evidence jsonb := '{}'::jsonb;
  v_overview jsonb;
  v_market jsonb;
  v_decision private.owner_decisions%rowtype;
  v_message text := '';
  v_actions jsonb := '[]'::jsonb;
  v_elem jsonb;
  v_action_text text;
  v_n integer := 0;
  v_health text;
  v_queue int;
  v_retry int;
  v_dead int;
  v_risk_high int;
  v_risk_critical int;
  v_tg_failed int;
  v_receipt_failed int;
  v_statement_failed int;
  v_decisions jsonb;
  v_o jsonb;
  v_entity_id uuid;
begin
  if not exists (
    select 1 from public.profiles p
    where p.id = p_owner_user_id
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'owner_required' using errcode='42501';
  end if;

  if v_raw = '' then v_raw := 'help'; end if;
  v_text := lower(v_raw);
  v_text := replace(replace(replace(v_text,'ي','ی'),'ى','ی'),'ك','ک');
  v_text := regexp_replace(v_text, '[[:space:]]+', ' ', 'g');

  select * into v_ctx
  from private.owner_telegram_os_context c
  where c.owner_user_id = p_owner_user_id;

  if v_text ~ 'وردەکاری|زیاتر|detail|details|more|بەڵگە|evidence|proof' then
    if v_ctx.expires_at is not null and v_ctx.expires_at > now()
       and v_ctx.last_market_id is not null then
      v_overview := public.get_system_owner_autopilot_overview_service('', 'all', 1, 100);
      select value into v_market
      from jsonb_array_elements(coalesce(v_overview->'items','[]'::jsonb))
      where value->>'market_id' = v_ctx.last_market_id::text
      limit 1;

      if v_market is not null then
        v_health := coalesce(v_market #>> '{health,status}','healthy');
        v_queue := coalesce((v_market #>> '{health,active_queue}')::int,0);
        v_retry := coalesce((v_market #>> '{health,retrying}')::int,0);
        v_dead := coalesce((v_market #>> '{health,dead_letter}')::int,0);
        v_risk_high := coalesce((v_market #>> '{risk,high}')::int,0);
        v_risk_critical := coalesce((v_market #>> '{risk,critical}')::int,0);
        v_tg_failed := coalesce((v_market #>> '{telegram,failed}')::int,0);
        v_receipt_failed := coalesce((v_market #>> '{receipts,failed}')::int,0);
        v_statement_failed := coalesce((v_market #>> '{statements,failed}')::int,0);

        v_message := '🔎 Evidence Card • ' || coalesce(v_market->>'market_name','مارکێت') || E'\n\n' ||
          'Health: ' || v_health || E'\n' ||
          '🤖 AutoPilot: ' || case when coalesce((v_market #>> '{autopilot,enabled}')::boolean,false) then 'ON' else 'OFF' end ||
          ' • ' || coalesce(v_market #>> '{autopilot,mode}','—') || E'\n' ||
          '⚙️ Queue ' || v_queue || ' • Retry ' || v_retry || ' • Dead-letter ' || v_dead || E'\n' ||
          '🛡️ High Risk ' || v_risk_high || ' • Critical ' || v_risk_critical || E'\n' ||
          '📨 Telegram failed ' || v_tg_failed || E'\n' ||
          '📄 Receipt failed ' || v_receipt_failed || ' • Statement failed ' || v_statement_failed || E'\n' ||
          '🔔 Notification failed ' || coalesce(v_market #>> '{notifications,failed}','0') || E'\n' ||
          '🧾 Recent issue count ' || coalesce(v_market->>'issue_count',
             case when jsonb_typeof(v_market->'recent_issues')='array' then jsonb_array_length(v_market->'recent_issues')::text else '0' end) || E'\n\n' ||
          '💡 بڵێ «چی پێشنیار دەکەیت؟» بۆ هەنگاوە safe ـەکان.';

        v_evidence := v_market;
        update private.owner_telegram_os_context
        set last_intent='market_detail', last_entity_type='market', last_entity_id=v_ctx.last_market_id::text,
            last_entity_name=coalesce(v_market->>'market_name',v_ctx.last_market_name), last_evidence=v_evidence,
            last_question=v_raw, expires_at=now()+interval '30 minutes', updated_at=now()
        where owner_user_id=p_owner_user_id;

        return jsonb_build_object('ok',true,'intent','market_detail','confidence','high','message',v_message,
          'evidence',v_evidence,'entity',jsonb_build_object('type','market','id',v_ctx.last_market_id,'name',coalesce(v_market->>'market_name',v_ctx.last_market_name)));
      end if;
    end if;

    if v_ctx.expires_at is not null and v_ctx.expires_at > now()
       and (v_ctx.last_entity_type='decision' or v_ctx.last_intent in ('decision_detail','decisions')) then
      begin
        v_entity_id := nullif(v_ctx.last_entity_id,'')::uuid;
      exception when others then
        begin v_entity_id := nullif(v_ctx.last_evidence->>'id','')::uuid;
        exception when others then v_entity_id := null; end;
      end;

      if v_entity_id is not null then
        select * into v_decision
        from private.owner_decisions d
        where d.id=v_entity_id and d.owner_user_id=p_owner_user_id
        limit 1;
      end if;

      if v_decision.id is not null then
        v_message := '📥 Decision Evidence Card' || E'\n\n' ||
          case v_decision.severity when 'critical' then '🔴 ' when 'warning' then '🟠 ' else '🔵 ' end || v_decision.title || E'\n' ||
          coalesce(v_decision.body,'') || E'\n\n' ||
          'Kind: ' || v_decision.kind || E'\n' ||
          'Status: ' || v_decision.status || E'\n' ||
          'First seen: ' || v_decision.first_seen_at::text || E'\n' ||
          'Last seen: ' || v_decision.last_seen_at::text || E'\n\n' ||
          '💡 بڵێ «چی پێشنیار دەکەیت؟» بۆ recommended actions.';
        v_evidence := to_jsonb(v_decision);
        update private.owner_telegram_os_context
        set last_intent='decision_detail', last_entity_type='decision', last_entity_id=v_decision.id::text,
            last_entity_name=v_decision.title, last_evidence=v_evidence, last_recommendations=v_decision.recommended_actions,
            last_question=v_raw, expires_at=now()+interval '30 minutes', updated_at=now()
        where owner_user_id=p_owner_user_id;
        return jsonb_build_object('ok',true,'intent','decision_detail','confidence','high','message',v_message,
          'evidence',v_evidence,'entity',jsonb_build_object('type','decision','id',v_decision.id,'name',v_decision.title));
      end if;
    end if;
  end if;

  if v_text ~ 'پێشنیار|چی بکەم|چی بکرێ|recommend|what should|next step' then
    if v_ctx.expires_at is not null and v_ctx.expires_at > now() and v_ctx.last_market_id is not null then
      v_overview := public.get_system_owner_autopilot_overview_service('', 'all', 1, 100);
      select value into v_market
      from jsonb_array_elements(coalesce(v_overview->'items','[]'::jsonb))
      where value->>'market_id' = v_ctx.last_market_id::text limit 1;
      if v_market is not null then
        v_health := coalesce(v_market #>> '{health,status}','healthy');
        v_queue := coalesce((v_market #>> '{health,active_queue}')::int,0);
        v_retry := coalesce((v_market #>> '{health,retrying}')::int,0);
        v_dead := coalesce((v_market #>> '{health,dead_letter}')::int,0);
        v_risk_critical := coalesce((v_market #>> '{risk,critical}')::int,0);
        v_tg_failed := coalesce((v_market #>> '{telegram,failed}')::int,0);

        v_actions := '[]'::jsonb;
        if v_dead > 0 then v_actions := v_actions || jsonb_build_array('Dead-letter ـەکان بپشکنە و تەنها job ـی idempotent بە Safe Retry بگەڕێنەوە.'); end if;
        if v_retry > 0 or v_queue > 0 then v_actions := v_actions || jsonb_build_array('Queue/Retry ـەکان و oldest job بپشکنە؛ recovery ـی خۆکار چاودێری بکە.'); end if;
        if v_risk_critical > 0 then v_actions := v_actions || jsonb_build_array('Critical Risk ـەکان بخوێنەوە و evidence ـی customer ـەکان پشکنە؛ هیچ financial action ـێک خۆکار مەکە.'); end if;
        if v_tg_failed > 0 then v_actions := v_actions || jsonb_build_array('Telegram failure ـەکان بەپێی recipient/config group بکە و revoked/unlinked chat ـەکان جیا بکەرەوە.'); end if;
        if jsonb_array_length(v_actions)=0 then v_actions := jsonb_build_array('هیچ هەنگاوی فوری پێویست نییە؛ دۆخ Healthy ـە و چاودێری بەردەوام بە.'); end if;

        v_message := '💡 Safe Recommendations • ' || coalesce(v_market->>'market_name','مارکێت');
        v_n := 0;
        for v_elem in select value from jsonb_array_elements(v_actions) loop
          v_n := v_n + 1;
          v_message := v_message || E'\n' || v_n || '. ' || trim(both '"' from v_elem::text);
        end loop;
        v_message := v_message || E'\n\n🔒 ئەمانە پێشنیارن؛ هیچ action ـێک لە Telegram خۆکار جێبەجێ نەکرا.';

        update private.owner_telegram_os_context set last_intent='market_recommendation', last_entity_type='market',
          last_entity_id=v_ctx.last_market_id::text, last_entity_name=coalesce(v_market->>'market_name',v_ctx.last_market_name),
          last_recommendations=v_actions, last_question=v_raw, expires_at=now()+interval '30 minutes', updated_at=now()
        where owner_user_id=p_owner_user_id;
        return jsonb_build_object('ok',true,'intent','market_recommendation','confidence','high','message',v_message,
          'recommendations',v_actions,'entity',jsonb_build_object('type','market','id',v_ctx.last_market_id,'name',coalesce(v_market->>'market_name',v_ctx.last_market_name)));
      end if;
    end if;

    if v_ctx.expires_at is not null and v_ctx.expires_at > now()
       and (v_ctx.last_entity_type='decision' or v_ctx.last_intent='decision_detail') then
      begin v_entity_id := nullif(v_ctx.last_entity_id,'')::uuid; exception when others then v_entity_id := null; end;
      if v_entity_id is not null then
        select * into v_decision from private.owner_decisions d
        where d.id=v_entity_id and d.owner_user_id=p_owner_user_id limit 1;
      end if;
      if v_decision.id is not null then
        v_actions := coalesce(v_decision.recommended_actions,'[]'::jsonb);
        if jsonb_typeof(v_actions)<>'array' or jsonb_array_length(v_actions)=0 then
          v_actions := jsonb_build_array('Evidence ـەکە پشکنە.','Market/record ـی پەیوەندیدار بکەرەوە.','تەنها دوای پشتڕاستکردنەوە action ـی هەستیار پەسند بکە.');
        end if;
        v_message := '💡 Recommended Actions • ' || v_decision.title;
        v_n := 0;
        for v_elem in select value from jsonb_array_elements(v_actions) loop
          v_n := v_n + 1;
          if jsonb_typeof(v_elem)='object' then
            v_action_text := coalesce(v_elem->>'label',v_elem->>'title',v_elem->>'action',v_elem::text);
          else
            v_action_text := trim(both '"' from v_elem::text);
          end if;
          v_message := v_message || E'\n' || v_n || '. ' || v_action_text;
        end loop;
        v_message := v_message || E'\n\n🔒 پێشنیارەکان read-only ـن و هیچ approval/write خۆکار ناکەن.';
        update private.owner_telegram_os_context set last_intent='decision_recommendation',
          last_entity_type='decision', last_entity_id=v_decision.id::text, last_entity_name=v_decision.title,
          last_recommendations=v_actions, last_question=v_raw, expires_at=now()+interval '30 minutes',updated_at=now()
        where owner_user_id=p_owner_user_id;
        return jsonb_build_object('ok',true,'intent','decision_recommendation','confidence','high','message',v_message,
          'recommendations',v_actions,'entity',jsonb_build_object('type','decision','id',v_decision.id,'name',v_decision.title));
      end if;
    end if;

    v_overview := public.get_owner_executive_brief_service(p_owner_user_id);
    v_o := coalesce(v_overview->'current','{}'::jsonb);
    v_decisions := coalesce(v_overview->'decisions','{}'::jsonb);
    v_actions := '[]'::jsonb;
    if coalesce((v_o->>'dead_letter')::int,0)>0 then v_actions := v_actions || jsonb_build_array('Dead-letter ـەکان سەرەتا پشکنە.'); end if;
    if coalesce((v_o->>'attention')::int,0)>0 then v_actions := v_actions || jsonb_build_array('مارکێتە Attention ـەکان یەک بە یەک بکەرەوە و evidence ببینە.'); end if;
    if coalesce((v_o->>'risk_critical')::int,0)>0 then v_actions := v_actions || jsonb_build_array('Critical Risk ـەکان review بکە.'); end if;
    if coalesce((v_decisions->>'total')::int,0)>0 then v_actions := v_actions || jsonb_build_array('Decision Inbox ـەکە بەپێی Critical سپس Warning پشکنە.'); end if;
    if jsonb_array_length(v_actions)=0 then v_actions := jsonb_build_array('هیچ هەنگاوی فوری پێویست نییە؛ هەموو metric ـە گرنگەکان سالم دیارن.'); end if;
    v_message := '💡 ZHIROX • Next Safe Steps';
    v_n := 0;
    for v_elem in select value from jsonb_array_elements(v_actions) loop
      v_n := v_n + 1; v_message := v_message || E'\n' || v_n || '. ' || trim(both '"' from v_elem::text);
    end loop;
    v_message := v_message || E'\n\n🔒 هیچ action ـێک خۆکار جێبەجێ نەکرا.';
    return jsonb_build_object('ok',true,'intent','general_recommendation','confidence','high','message',v_message,'recommendations',v_actions);
  end if;

  v_base := public.ask_owner_telegram_os_service(p_owner_user_id,v_raw);
  v_intent := coalesce(v_base->>'intent','help');
  v_evidence := coalesce(v_base->'evidence','{}'::jsonb);

  update private.owner_telegram_os_context c
  set last_entity_type = case
        when v_intent in ('market_status','market_why') then 'market'
        when v_intent='decision_detail' then 'decision'
        else c.last_entity_type end,
      last_entity_id = case
        when v_intent in ('market_status','market_why') then nullif(v_base->>'market_id','')
        when v_intent='decision_detail' then nullif(v_evidence->>'id','')
        else c.last_entity_id end,
      last_entity_name = case
        when v_intent in ('market_status','market_why') then nullif(v_base->>'market_name','')
        when v_intent='decision_detail' then nullif(v_evidence->>'title','')
        else c.last_entity_name end,
      last_list_type = case when v_intent in ('decisions','problem_markets') then v_intent else c.last_list_type end,
      last_result_items = case
        when v_intent in ('decisions','problem_markets') and jsonb_typeof(v_evidence->'items')='array' then v_evidence->'items'
        else c.last_result_items end,
      last_recommendations = case
        when v_intent='decision_detail' and jsonb_typeof(v_evidence->'recommended_actions')='array' then v_evidence->'recommended_actions'
        else c.last_recommendations end,
      expires_at = now()+interval '30 minutes', updated_at=now()
  where c.owner_user_id=p_owner_user_id;

  return v_base || jsonb_build_object(
    'phase',2,
    'context',jsonb_build_object(
      'entity_type',case when v_intent in ('market_status','market_why') then 'market' when v_intent='decision_detail' then 'decision' else null end,
      'expires_in_minutes',30
    )
  );
end;
$function$;

revoke all on function public.ask_owner_telegram_os_phase2_service(uuid,text) from public,anon,authenticated;
grant execute on function public.ask_owner_telegram_os_phase2_service(uuid,text) to service_role;
