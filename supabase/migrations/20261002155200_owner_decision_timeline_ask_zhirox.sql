create or replace function public.ask_owner_telegram_os_service(p_owner_user_id uuid, p_text text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_result jsonb;
  v_raw text := btrim(coalesce(p_text,''));
  v_text text;
  v_ctx private.owner_telegram_os_context%rowtype;
  v_decision_id uuid;
  v_timeline jsonb;
  v_decision jsonb;
  v_lifecycle jsonb;
  v_event jsonb;
  v_message text;
  v_label text;
  v_actor text;
  v_when text;
  v_extra text;
begin
  v_text := lower(v_raw);
  v_text := replace(replace(replace(v_text,'ي','ی'),'ى','ی'),'ك','ک');
  v_text := regexp_replace(v_text,'[[:space:]]+',' ','g');

  if v_text ~ '(^| )(timeline|lifecycle|مێژوو|مێژووی)( |$)' then
    select * into v_ctx
    from private.owner_telegram_os_context c
    where c.owner_user_id=p_owner_user_id;

    if v_ctx.expires_at is not null and v_ctx.expires_at>now()
       and (v_ctx.last_entity_type='decision' or v_ctx.last_intent like 'decision%') then
      begin
        v_decision_id := nullif(v_ctx.last_entity_id,'')::uuid;
      exception when others then
        begin
          v_decision_id := nullif(v_ctx.last_evidence->>'id','')::uuid;
        exception when others then v_decision_id := null; end;
      end;
    end if;

    if v_decision_id is null then
      return jsonb_build_object(
        'ok',true,'intent','decision_timeline_help','confidence','high',
        'message','🧭 Decision Timeline\n\nسەرەتا Decision ـێک بکەرەوە، پاشان بنووسە «مێژوو» یان timeline.'
      );
    end if;

    v_timeline := public.get_owner_decision_timeline_service(p_owner_user_id,v_decision_id,12);
    if coalesce((v_timeline->>'ok')::boolean,false) is not true then
      return jsonb_build_object('ok',false,'intent','decision_timeline','confidence','high','message','Decision ـەکە نەدۆزرایەوە.');
    end if;

    v_decision := coalesce(v_timeline->'decision','{}'::jsonb);
    v_lifecycle := coalesce(v_timeline->'lifecycle','{}'::jsonb);
    v_message := '🧭 Decision Timeline • ' || coalesce(v_decision->>'title','Decision') || E'\n\n' ||
      'Status: ' || coalesce(v_lifecycle->>'status','—') || E'\n' ||
      'Episode: ' || coalesce(to_char((v_lifecycle->>'episode_started_at')::timestamptz at time zone 'Asia/Baghdad','YYYY-MM-DD HH24:MI'),'—') || E'\n\n';

    for v_event in select value from jsonb_array_elements(coalesce(v_timeline->'events','[]'::jsonb)) loop
      v_label := case v_event->>'event_type'
        when 'created' then '🟢 دروستبوو'
        when 'acknowledged' then '✅ Acknowledged'
        when 'snoozed' then '💤 Snoozed'
        when 'reopened' then '🔓 Reopened'
        when 'resolved' then '🟩 Auto-resolved'
        when 'reactivated' then '🔁 Reactivated'
        when 'evidence_changed' then '🔎 Evidence changed'
        else '• ' || coalesce(v_event->>'event_type','event')
      end;
      v_actor := case when v_event->>'actor_type'='owner' then 'Owner' else 'System' end;
      begin
        v_when := to_char((v_event->>'created_at')::timestamptz at time zone 'Asia/Baghdad','MM-DD HH24:MI');
      exception when others then v_when := '—'; end;
      v_extra := '';
      if v_event->>'event_type'='resolved' and coalesce((v_event->'evidence'->>'resolution_verified')::boolean,false) then
        v_extra := ' • verified';
      elsif v_event->>'event_type'='snoozed' and nullif(v_event->'metadata'->>'snoozed_until','') is not null then
        begin
          v_extra := ' → ' || to_char((v_event->'metadata'->>'snoozed_until')::timestamptz at time zone 'Asia/Baghdad','MM-DD HH24:MI');
        exception when others then v_extra := ''; end;
      end if;
      v_message := v_message || v_label || ' • ' || v_when || ' • ' || v_actor || v_extra || E'\n';
    end loop;

    v_message := v_message || E'\n🔒 Timeline read-only ـە؛ هیچ financial write ـێک ناکات.';

    update private.owner_telegram_os_context
    set last_intent='decision_timeline',last_entity_type='decision',last_entity_id=v_decision_id::text,
        last_entity_name=coalesce(v_decision->>'title',last_entity_name),last_evidence=v_decision,
        last_question=v_raw,expires_at=now()+interval '30 minutes',updated_at=now()
    where owner_user_id=p_owner_user_id;

    return jsonb_build_object(
      'ok',true,'intent','decision_timeline','confidence','high','message',v_message,
      'evidence',v_decision,'timeline',v_timeline,
      'entity',jsonb_build_object('type','decision','id',v_decision_id,'name',coalesce(v_decision->>'title','Decision'))
    );
  end if;

  v_result := public.ask_owner_telegram_os_phase2_service(p_owner_user_id,p_text);

  if lower(trim(coalesce(p_text,'')))='help' and coalesce(v_result->>'intent','')='help' then
    v_result := jsonb_set(v_result,'{intent}',to_jsonb('brief_help'::text),true);
  end if;

  if coalesce(v_result->>'intent','')='decision_detail' then
    v_result := jsonb_set(
      v_result,'{message}',
      to_jsonb(coalesce(v_result->>'message','') || E'\n\n🧭 بۆ مێژووی lifecycle بنووسە «مێژوو» یان timeline.'),true
    );
  end if;

  return v_result;
end;
$$;

revoke all on function public.ask_owner_telegram_os_service(uuid,text) from public, anon, authenticated;
grant execute on function public.ask_owner_telegram_os_service(uuid,text) to service_role;