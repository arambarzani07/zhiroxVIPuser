create or replace function public.ask_owner_telegram_os_service(
  p_owner_user_id uuid,
  p_text text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_raw text := btrim(coalesce(p_text,''));
  v_text text;
  v_ctx jsonb := '{}'::jsonb;
  v_overview jsonb;
  v_o jsonb := '{}'::jsonb;
  v_items jsonb := '[]'::jsonb;
  v_market jsonb;
  v_market_match jsonb := null;
  v_market_name text;
  v_market_norm text;
  v_market_short text;
  v_admin_norm text;
  v_problem_items jsonb := '[]'::jsonb;
  v_brief jsonb;
  v_decisions jsonb;
  v_changes jsonb;
  v_evidence jsonb := '{}'::jsonb;
  v_message text := '';
  v_intent text := 'help';
  v_confidence text := 'high';
  v_status text;
  v_idx integer := 0;
  v_selected jsonb;
  v_context_items jsonb;
  v_context_market_id uuid;
  v_n integer;
  v_delta jsonb;
  v_notifications jsonb;
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

  v_text := lower(v_raw);
  v_text := replace(replace(replace(v_text,'ي','ی'),'ى','ی'),'ك','ک');
  v_text := regexp_replace(v_text, '[[:space:]]+', ' ', 'g');

  v_ctx := public.get_owner_telegram_os_context_service(p_owner_user_id);
  v_overview := public.get_system_owner_autopilot_overview_v2_service('', 'all', 1, 100);
  v_o := coalesce(v_overview->'overview','{}'::jsonb);
  v_items := coalesce(v_overview->'items','[]'::jsonb);

  for v_market in select value from jsonb_array_elements(v_items)
  loop
    v_market_name := coalesce(v_market->>'market_name','');
    v_market_norm := lower(replace(replace(replace(v_market_name,'ي','ی'),'ى','ی'),'ك','ک'));
    v_market_short := regexp_replace(v_market_norm, '^(سوپەرمارکێتی|سوپەرمارکێت|مارکێتی|مارکێت)[[:space:]]+', '', 'g');
    v_admin_norm := lower(replace(replace(replace(coalesce(v_market->>'admin_name',''),'ي','ی'),'ى','ی'),'ك','ک'));
    if (char_length(v_market_norm) >= 2 and position(v_market_norm in v_text) > 0)
       or (char_length(v_market_short) >= 2 and position(v_market_short in v_text) > 0)
       or (char_length(v_admin_norm) >= 3 and position(v_admin_norm in v_text) > 0) then
      v_market_match := v_market;
      exit;
    end if;
  end loop;

  if coalesce((v_ctx->>'active')::boolean,false) then
    if v_text ~ '(^| )(یەکەم|1|١)( |$)' then v_idx := 1;
    elsif v_text ~ '(^| )(دووەم|2|٢)( |$)' then v_idx := 2;
    elsif v_text ~ '(^| )(سێیەم|3|٣)( |$)' then v_idx := 3;
    elsif v_text ~ '(^| )(چوارەم|4|٤)( |$)' then v_idx := 4;
    elsif v_text ~ '(^| )(پێنجەم|5|٥)( |$)' then v_idx := 5;
    end if;

    if v_idx > 0 then
      v_context_items := coalesce(v_ctx #> '{last_evidence,items}','[]'::jsonb);
      if jsonb_typeof(v_context_items)='array' and jsonb_array_length(v_context_items) >= v_idx then
        v_selected := v_context_items->(v_idx-1);
        if v_selected ? 'market_id' then
          v_market_match := v_selected;
        elsif v_selected ? 'title' then
          v_intent := 'decision_detail';
          v_message := '📥 ' || coalesce(v_selected->>'title','Decision') || E'\n\n' ||
                       coalesce(v_selected->>'body','وردەکاریی زیاتر بەردەست نییە.') || E'\n\n' ||
                       '🔎 Evidence: ' || coalesce((v_selected->'evidence')::text,'{}') || E'\n' ||
                       'ℹ️ ئەمە تەنها خوێندنەوەیە؛ هیچ action ـێک خۆکار ناکرێت.';
          v_evidence := v_selected;
          perform public.set_owner_telegram_os_context_service(
            p_owner_user_id,v_intent,null,null,v_raw,v_evidence
          );
          return jsonb_build_object('ok',true,'intent',v_intent,'confidence','high','message',v_message,'evidence',v_evidence);
        end if;
      end if;
    end if;
  end if;

  if v_text ~ 'بۆچی|why' then
    v_intent := 'why';
    if coalesce((v_ctx->>'active')::boolean,false) and nullif(v_ctx->>'last_market_id','') is not null then
      begin v_context_market_id := (v_ctx->>'last_market_id')::uuid; exception when others then v_context_market_id := null; end;
      if v_context_market_id is not null then
        select value into v_market_match
        from jsonb_array_elements(v_items)
        where value->>'market_id' = v_context_market_id::text
        limit 1;
      end if;
    end if;

    if v_market_match is not null then
      v_status := coalesce(v_market_match #>> '{health,status}','healthy');
      v_message := '🔎 بۆچی • ' || coalesce(v_market_match->>'market_name','مارکێت') || E'\n\n' ||
        'Health: ' || v_status || E'\n' ||
        'Queue: ' || coalesce(v_market_match #>> '{health,active_queue}','0') ||
        ' • Retry: ' || coalesce(v_market_match #>> '{health,retrying}','0') ||
        ' • Dead-letter: ' || coalesce(v_market_match #>> '{health,dead_letter}','0') || E'\n' ||
        'Risk High: ' || coalesce(v_market_match #>> '{risk,high}','0') ||
        ' • Critical: ' || coalesce(v_market_match #>> '{risk,critical}','0') || E'\n' ||
        'Telegram failed: ' || coalesce(v_market_match #>> '{telegram,failed}','0') ||
        ' • Receipt failed: ' || coalesce(v_market_match #>> '{receipts,failed}','0') ||
        ' • Statement failed: ' || coalesce(v_market_match #>> '{statements,failed}','0');
      if v_status='healthy'
         and coalesce((v_market_match #>> '{health,active_queue}')::int,0)=0
         and coalesce((v_market_match #>> '{health,retrying}')::int,0)=0
         and coalesce((v_market_match #>> '{health,dead_letter}')::int,0)=0
         and coalesce((v_market_match #>> '{risk,critical}')::int,0)=0 then
        v_message := v_message || E'\n\n✅ هۆکاری Healthy بوون: queue/retry/dead-letter و critical risk ئێستا صفرن.';
      else
        v_message := v_message || E'\n\n⚠️ ئەو metric ـانەی سەرەوە evidence ـی دۆخەکەن.';
      end if;
      v_evidence := v_market_match;
      perform public.set_owner_telegram_os_context_service(
        p_owner_user_id,'market_why',(v_market_match->>'market_id')::uuid,v_market_match->>'market_name',v_raw,v_evidence
      );
      return jsonb_build_object('ok',true,'intent','market_why','confidence','high','message',v_message,'evidence',v_evidence,
        'market_id',v_market_match->>'market_id','market_name',v_market_match->>'market_name');
    end if;

    if coalesce((v_ctx->>'active')::boolean,false) and v_ctx->>'last_intent' in ('decisions','decision_detail') then
      v_selected := coalesce(v_ctx #> '{last_evidence,item}', v_ctx->'last_evidence');
      if v_selected is not null and v_selected <> '{}'::jsonb then
        v_message := '🔎 هۆکاری بڕیار/ئاگادارییەکە' || E'\n\n' ||
          coalesce(v_selected->>'body',v_selected->>'title','وردەکاری بەردەست نییە.') || E'\n\nEvidence: ' ||
          coalesce((v_selected->'evidence')::text,'{}');
        return jsonb_build_object('ok',true,'intent','decision_why','confidence','high','message',v_message,'evidence',v_selected);
      end if;
    end if;

    v_brief := public.get_owner_executive_brief_service(p_owner_user_id);
    v_o := coalesce(v_brief->'current','{}'::jsonb);
    v_message := '🔎 بۆچی دۆخی ئێستا ئەمەیە؟' || E'\n\n' ||
      'Attention: ' || coalesce(v_o->>'attention','0') ||
      ' • Degraded: ' || coalesce(v_o->>'degraded','0') || E'\n' ||
      'Queue: ' || coalesce(v_o->>'active_queue','0') ||
      ' • Retry: ' || coalesce(v_o->>'retrying','0') ||
      ' • Dead-letter: ' || coalesce(v_o->>'dead_letter','0') || E'\n' ||
      'High Risk: ' || coalesce(v_o->>'risk_high','0') ||
      ' • Critical Risk: ' || coalesce(v_o->>'risk_critical','0') || E'\n\n' ||
      'ئەم metric ـانە evidence ـی live ـی Executive Brief ـن.';
    v_evidence := jsonb_build_object('overview',v_o,'decisions',v_brief->'decisions');
    perform public.set_owner_telegram_os_context_service(p_owner_user_id,'brief_why',null,null,v_raw,v_evidence);
    return jsonb_build_object('ok',true,'intent','brief_why','confidence','high','message',v_message,'evidence',v_evidence);
  end if;

  if v_market_match is not null then
    v_intent := 'market_status';
    v_status := coalesce(v_market_match #>> '{health,status}','healthy');
    v_message := '🏪 ' || coalesce(v_market_match->>'market_name','مارکێت') || E'\n\n' ||
      'Health: ' || v_status || E'\n' ||
      '🤖 AutoPilot: ' || case when coalesce((v_market_match #>> '{autopilot,enabled}')::boolean,false) then 'ON' else 'OFF' end ||
      ' • ' || coalesce(v_market_match #>> '{autopilot,mode}','—') || E'\n' ||
      '⚙️ Queue ' || coalesce(v_market_match #>> '{health,active_queue}','0') ||
      ' • Retry ' || coalesce(v_market_match #>> '{health,retrying}','0') ||
      ' • Dead ' || coalesce(v_market_match #>> '{health,dead_letter}','0') || E'\n' ||
      '🛡️ Risk ' || coalesce(v_market_match #>> '{risk,total}','0') ||
      ' • High ' || coalesce(v_market_match #>> '{risk,high}','0') ||
      ' • Critical ' || coalesce(v_market_match #>> '{risk,critical}','0') || E'\n' ||
      '📨 Telegram linked ' || coalesce(v_market_match #>> '{telegram,linked_customers}','0') ||
      ' • Failed ' || coalesce(v_market_match #>> '{telegram,failed}','0') || E'\n' ||
      '📄 Receipts failed ' || coalesce(v_market_match #>> '{receipts,failed}','0') ||
      ' • Statements failed ' || coalesce(v_market_match #>> '{statements,failed}','0') || E'\n' ||
      '🔔 Notifications failed ' || coalesce(v_market_match #>> '{notifications,failed}','0') || E'\n\n' ||
      'بڵێ «بۆچی؟» بۆ evidence ـی دۆخەکە.';
    v_evidence := v_market_match;
    perform public.set_owner_telegram_os_context_service(
      p_owner_user_id,v_intent,(v_market_match->>'market_id')::uuid,v_market_match->>'market_name',v_raw,v_evidence
    );
    return jsonb_build_object('ok',true,'intent',v_intent,'confidence','high','message',v_message,'evidence',v_evidence,
      'market_id',v_market_match->>'market_id','market_name',v_market_match->>'market_name');
  end if;

  if v_text ~ 'چی گۆڕ|گۆڕاو|changes|what changed' then
    v_intent := 'changes';
    v_changes := public.get_owner_changes_since_last_check_service(p_owner_user_id,true);
    v_delta := coalesce(v_changes->'delta','{}'::jsonb);
    v_notifications := coalesce(v_changes->'notifications','[]'::jsonb);
    v_message := '🔄 ZHIROX • چی گۆڕاوە؟' || E'\n' ||
      'لە ' || coalesce(v_changes->>'since','—') || ' تا ئێستا' || E'\n\n' ||
      'Attention ' || coalesce(v_delta->>'attention','0') ||
      ' • Degraded ' || coalesce(v_delta->>'degraded','0') || E'\n' ||
      'Queue ' || coalesce(v_delta->>'active_queue','0') ||
      ' • Retry ' || coalesce(v_delta->>'retrying','0') ||
      ' • Dead-letter ' || coalesce(v_delta->>'dead_letter','0') || E'\n' ||
      'High Risk ' || coalesce(v_delta->>'risk_high','0') ||
      ' • Critical Risk ' || coalesce(v_delta->>'risk_critical','0') || E'\n' ||
      '🔔 Event/Alert نوێ: ' || coalesce(v_changes->>'notification_count','0');
    if jsonb_array_length(v_notifications)=0 and
       coalesce((v_delta->>'attention')::int,0)=0 and
       coalesce((v_delta->>'degraded')::int,0)=0 and
       coalesce((v_delta->>'active_queue')::int,0)=0 and
       coalesce((v_delta->>'retrying')::int,0)=0 and
       coalesce((v_delta->>'dead_letter')::int,0)=0 and
       coalesce((v_delta->>'risk_high')::int,0)=0 and
       coalesce((v_delta->>'risk_critical')::int,0)=0 then
      v_message := v_message || E'\n\n✅ هیچ گۆڕانکارییەکی گرنگ نییە.';
    end if;
    v_evidence := jsonb_build_object('delta',v_delta,'notifications',v_notifications);
    perform public.set_owner_telegram_os_context_service(p_owner_user_id,v_intent,null,null,v_raw,v_evidence);
    return jsonb_build_object('ok',true,'intent',v_intent,'confidence','high','message',v_message,'evidence',v_evidence);
  end if;

  if v_text ~ 'بڕیار|decision|پەسند|approval' then
    v_intent := 'decisions';
    v_decisions := public.get_owner_decision_inbox_service(p_owner_user_id,10);
    v_message := '📥 ZHIROX • Decision Inbox' || E'\n\n' ||
      'Total: ' || coalesce(v_decisions->>'total','0') ||
      ' • Critical: ' || coalesce(v_decisions->>'critical','0') ||
      ' • Warning: ' || coalesce(v_decisions->>'warning','0');
    if coalesce((v_decisions->>'total')::int,0)=0 then
      v_message := v_message || E'\n\n✅ ئێستا هیچ بڕیارێکی چالاک پێویست نییە.';
    else
      v_n := 0;
      for v_selected in select value from jsonb_array_elements(coalesce(v_decisions->'items','[]'::jsonb))
      loop
        v_n := v_n + 1;
        exit when v_n > 5;
        v_message := v_message || E'\n\n' || v_n || '. ' ||
          case coalesce(v_selected->>'severity','info') when 'critical' then '🔴 ' when 'warning' then '🟠 ' else '🔵 ' end ||
          coalesce(v_selected->>'title','Decision');
      end loop;
      v_message := v_message || E'\n\nبڵێ «یەکەم»، «دووەم»... بۆ وردەکاری.';
    end if;
    v_evidence := jsonb_build_object('items',coalesce(v_decisions->'items','[]'::jsonb),'summary',v_decisions - 'items');
    perform public.set_owner_telegram_os_context_service(p_owner_user_id,v_intent,null,null,v_raw,v_evidence);
    return jsonb_build_object('ok',true,'intent',v_intent,'confidence','high','message',v_message,'evidence',v_evidence);
  end if;

  if (v_text ~ 'کام مارکێت' and v_text ~ 'کێشە|سەرنج|ناسا|خراپ') or v_text ~ 'problem markets|attention markets' then
    v_intent := 'problem_markets';
    select coalesce(jsonb_agg(value),'[]'::jsonb) into v_problem_items
    from jsonb_array_elements(v_items)
    where coalesce(value #>> '{health,status}','healthy') <> 'healthy';
    if jsonb_array_length(v_problem_items)=0 then
      v_message := '🏪 مارکێتە پێویست بە سەرنجەکان' || E'\n\n✅ ئێستا هەموو مارکێتەکان Healthy ـن.';
    else
      v_message := '🏪 مارکێتە پێویست بە سەرنجەکان';
      v_n := 0;
      for v_market in select value from jsonb_array_elements(v_problem_items)
      loop
        v_n := v_n + 1;
        exit when v_n > 5;
        v_message := v_message || E'\n' || v_n || '. ' || coalesce(v_market->>'market_name','مارکێت') ||
          ' — ' || coalesce(v_market #>> '{health,status}','attention');
      end loop;
      v_message := v_message || E'\n\nبڵێ «یەکەم»، «دووەم»... بۆ وردەکاری.';
    end if;
    v_evidence := jsonb_build_object('items',v_problem_items,'overview',v_o);
    perform public.set_owner_telegram_os_context_service(p_owner_user_id,v_intent,null,null,v_raw,v_evidence);
    return jsonb_build_object('ok',true,'intent',v_intent,'confidence','high','message',v_message,'evidence',v_evidence);
  end if;

  if v_text ~ 'ڕیسک|ریسک|risk' then
    v_intent := 'risk';
    v_message := '🛡️ ZHIROX • Risk Pulse' || E'\n\n' ||
      'Total: ' || coalesce(v_o->>'risk_total','0') || E'\n' ||
      'High: ' || coalesce(v_o->>'risk_high','0') || E'\n' ||
      'Critical: ' || coalesce(v_o->>'risk_critical','0') || E'\n\n' ||
      case when coalesce((v_o->>'risk_critical')::int,0)=0 then '✅ Critical risk ئێستا صفرە.' else '⚠️ Critical risk هەیە؛ Decision Inbox بپشکنە.' end;
    v_evidence := jsonb_build_object('overview',v_o);
    perform public.set_owner_telegram_os_context_service(p_owner_user_id,v_intent,null,null,v_raw,v_evidence);
    return jsonb_build_object('ok',true,'intent',v_intent,'confidence','high','message',v_message,'evidence',v_evidence);
  end if;

  if v_text ~ 'ئەمڕۆ چی گرنگ|چی گرنگ|کورتە|brief|executive|دۆخی گشتی' then
    v_intent := 'brief';
    v_brief := public.get_owner_executive_brief_service(p_owner_user_id);
    v_o := coalesce(v_brief->'current','{}'::jsonb);
    v_decisions := coalesce(v_brief->'decisions','{}'::jsonb);
    v_delta := coalesce(v_brief->'delta_24h','{}'::jsonb);
    v_message := '🧠 ZHIROX • Executive Brief' || E'\n\n' ||
      '🏪 Markets ' || coalesce(v_o->>'total_markets','0') ||
      ' • Healthy ' || coalesce(v_o->>'healthy','0') ||
      ' • Attention ' || coalesce(v_o->>'attention','0') || E'\n' ||
      '⚙️ Queue ' || coalesce(v_o->>'active_queue','0') ||
      ' • Retry ' || coalesce(v_o->>'retrying','0') ||
      ' • Dead ' || coalesce(v_o->>'dead_letter','0') || E'\n' ||
      '🛡️ Risk High ' || coalesce(v_o->>'risk_high','0') ||
      ' • Critical ' || coalesce(v_o->>'risk_critical','0') || E'\n' ||
      '📥 Decisions ' || coalesce(v_decisions->>'total','0') || E'\n\n' ||
      case when coalesce((v_o->>'attention')::int,0)=0
                 and coalesce((v_o->>'dead_letter')::int,0)=0
                 and coalesce((v_o->>'risk_critical')::int,0)=0
                 and coalesce((v_decisions->>'total')::int,0)=0
           then '✅ ئێستا هیچ بابەتێکی فوری پێویستی بە هەنگاوی Owner نییە.'
           else '⚠️ یەک یان زیاتر بابەت پێویستی بە سەرنج هەیە؛ بڵێ «بڕیارەکان» یان «کام مارکێت کێشەی هەیە؟».' end ||
      E'\n\nبڵێ «بۆچی؟» بۆ evidence.';
    v_evidence := jsonb_build_object('overview',v_o,'decisions',v_decisions,'delta',v_delta,'items',coalesce(v_brief->'markets','[]'::jsonb));
    perform public.set_owner_telegram_os_context_service(p_owner_user_id,v_intent,null,null,v_raw,v_evidence);
    return jsonb_build_object('ok',true,'intent',v_intent,'confidence','high','message',v_message,'evidence',v_evidence);
  end if;

  if v_text ~ 'health|دۆخ|autopilot|ئۆتۆپایلۆت|سیستەم' then
    v_intent := 'health';
    v_message := '📊 ZHIROX • Live Health' || E'\n\n' ||
      '🏪 Healthy ' || coalesce(v_o->>'healthy','0') ||
      ' • Degraded ' || coalesce(v_o->>'degraded','0') ||
      ' • Attention ' || coalesce(v_o->>'attention','0') || E'\n' ||
      '⚙️ Queue ' || coalesce(v_o->>'active_queue','0') ||
      ' • Retry ' || coalesce(v_o->>'retrying','0') ||
      ' • Failed ' || coalesce(v_o->>'failed','0') ||
      ' • Dead-letter ' || coalesce(v_o->>'dead_letter','0') || E'\n' ||
      '🤖 AutoPilot ON ' || coalesce(v_o->>'autopilot_enabled','0') ||
      ' • OFF ' || coalesce(v_o->>'autopilot_disabled','0') || E'\n\n' ||
      'بڵێ «بۆچی؟» بۆ evidence.';
    v_evidence := jsonb_build_object('overview',v_o,'items',v_items);
    perform public.set_owner_telegram_os_context_service(p_owner_user_id,v_intent,null,null,v_raw,v_evidence);
    return jsonb_build_object('ok',true,'intent',v_intent,'confidence','high','message',v_message,'evidence',v_evidence);
  end if;

  v_intent := 'help';
  v_confidence := 'low';
  v_message := '💬 Ask ZHIROX' || E'\n\n' ||
    'بە زمانی ئاسایی بپرسە. نموونە:' || E'\n' ||
    '• «ئەمڕۆ چی گرنگە؟»' || E'\n' ||
    '• «کام مارکێت کێشەی هەیە؟»' || E'\n' ||
    '• «دۆخی کانی چنار چیە؟»' || E'\n' ||
    '• «ڕیسک چۆنە؟»' || E'\n' ||
    '• «چی گۆڕاوە؟»' || E'\n' ||
    '• «بڕیارەکانم پیشان بدە»' || E'\n' ||
    '• دواتر بڵێ «بۆچی؟» بۆ evidence.' || E'\n\n' ||
    '🔒 ئەم وەشانە read-only ـە و هیچ financial write ـێک خۆکار ناکات.';
  v_evidence := jsonb_build_object('supported_intents',jsonb_build_array('brief','health','problem_markets','market_status','risk','changes','decisions','why'));
  perform public.set_owner_telegram_os_context_service(p_owner_user_id,v_intent,null,null,v_raw,v_evidence);
  return jsonb_build_object('ok',true,'intent',v_intent,'confidence',v_confidence,'message',v_message,'evidence',v_evidence);
end;
$$;

revoke all on function public.ask_owner_telegram_os_service(uuid,text) from public, anon, authenticated;
grant execute on function public.ask_owner_telegram_os_service(uuid,text) to service_role;
