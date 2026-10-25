set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm._send_nudge(p_state crm.lead_qualification_state)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_max_nudges int;
  v_lead crm.leads;
  v_question crm.organization_pack_items;
  v_address crm.contact_addresses;
  v_conversation public.conversations;
begin
  v_max_nudges := coalesce(
    ((select r.value from crm.resolve_setting(p_state.organization_id, 'qualification.max_nudges') r) #>> '{}')::int,
    2
  );
  if p_state.nudge_count >= v_max_nudges then
    return;
  end if;

  select * into v_lead from crm.leads where id = p_state.lead_id;
  if not found or v_lead.status <> 'open' then
    -- The lead moved on (converted/dropped by a human) -- stop silently.
    update crm.lead_qualification_state set completed_at = now() where lead_id = p_state.lead_id;
    return;
  end if;

  select * into v_question from crm.organization_pack_items
  where organization_id = p_state.organization_id and kind = 'qualification_question'
    and item_key = p_state.current_question_key;
  if not found then
    return;
  end if;

  select * into v_address from crm.contact_addresses
  where organization_id = p_state.organization_id and contact_id = v_lead.contact_id
  order by created_at desc
  limit 1;
  if not found then
    return;
  end if;

  select * into v_conversation from public.conversations
  where organization_id = p_state.organization_id
    and service = v_address.service and address = v_address.address
  order by last_inbound_at desc nulls last
  limit 1;
  if not found then
    return;
  end if;

  perform crm._send_qualification_question(
    p_state.organization_id, v_lead.contact_id, v_conversation.id, v_address.service,
    v_conversation.organization_address, v_address.address, v_question, true
  );

  update crm.lead_qualification_state
  set nudge_count = nudge_count + 1, last_nudged_at = now(), asked_at = now()
  where lead_id = p_state.lead_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.sweep_qualification_nudges()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_state crm.lead_qualification_state;
begin
  for v_state in
    select s.*
    from crm.lead_qualification_state s
    where s.completed_at is null
      and s.asked_at <= now() - make_interval(hours => coalesce(
        ((select r.value from crm.resolve_setting(s.organization_id, 'qualification.question_timeout_hours') r) #>> '{}')::int,
        6
      ))
  loop
    perform crm._send_nudge(v_state);
  end loop;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.z_run_qualification_engine()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_contact_id uuid;
  v_auto_start boolean;
  v_source text;
  v_lead crm.leads;
  v_state crm.lead_qualification_state;
  v_next_question crm.organization_pack_items;
  v_answer_question_key text;
  v_answer_value text;
  v_question_item crm.organization_pack_items;
  v_field_key text;
  v_field_def jsonb;
  v_value_json jsonb;
  v_error text;
begin
  select ca.contact_id into v_contact_id
  from crm.contact_addresses ca
  where ca.organization_id = new.organization_id
    and ca.service = new.service
    and ca.address = new.conversation_address;

  if v_contact_id is null then
    return new;
  end if;

  v_auto_start := coalesce(
    ((select r.value from crm.resolve_setting(new.organization_id, 'qualification.auto_start') r) #>> '{}')::boolean,
    false
  );

  select * into v_lead from crm.leads
  where organization_id = new.organization_id and contact_id = v_contact_id;

  if not found then
    if not v_auto_start then
      return new;
    end if;
    select case
      when c.first_touch_referral->>'source_type' = 'ad' then 'ctwa_ad'
      when c.first_touch_referral->>'source_type' = 'post' then 'ctwa_post'
      else 'organic'
    end into v_source
    from crm.contacts c where c.id = v_contact_id;

    perform crm._ensure_lead(new.organization_id, v_contact_id, v_source);

    select * into v_lead from crm.leads
    where organization_id = new.organization_id and contact_id = v_contact_id;
  end if;

  select * into v_state from crm.lead_qualification_state where lead_id = v_lead.id;

  if not found then
    if not v_auto_start or v_lead.status <> 'open' then
      return new;
    end if;

    select * into v_next_question
    from crm._next_qualification_question(new.organization_id, v_contact_id);
    if v_next_question is null then
      return new;
    end if;

    insert into crm.lead_qualification_state (lead_id, organization_id, current_question_key, asked_at)
    values (v_lead.id, new.organization_id, v_next_question.item_key, now());

    perform crm.write_audit(
      new.organization_id, 'lead.qualification_started', 'lead', v_lead.id::text, '{}'::jsonb
    );
    perform crm._send_qualification_question(
      new.organization_id, v_contact_id, new.conversation_id, new.service,
      new.organization_address, new.conversation_address, v_next_question
    );
    return new;
  end if;

  if v_state.completed_at is not null then
    return new;
  end if;

  v_answer_question_key := null;
  v_answer_value := null;

  if new.content->>'kind' = 'interactive' then
    if new.content->'data'->>'type' = 'button_reply' then
      v_answer_question_key := split_part(new.content->'data'->'button_reply'->>'id', '::', 1);
      v_answer_value := split_part(new.content->'data'->'button_reply'->>'id', '::', 2);
    elsif new.content->'data'->>'type' = 'list_reply' then
      v_answer_question_key := split_part(new.content->'data'->'list_reply'->>'id', '::', 1);
      v_answer_value := split_part(new.content->'data'->'list_reply'->>'id', '::', 2);
    end if;
  end if;

  if v_answer_question_key is distinct from v_state.current_question_key
    or v_answer_value is null or v_answer_value = ''
  then
    perform crm._send_nudge(v_state);
    return new;
  end if;

  select * into v_question_item from crm.organization_pack_items
  where organization_id = new.organization_id and kind = 'qualification_question'
    and item_key = v_answer_question_key;
  if not found then
    perform crm._send_nudge(v_state);
    return new;
  end if;

  v_field_key := v_question_item.value->>'field';
  v_field_def := crm.custom_field_definition(new.organization_id, 'contact', v_field_key);
  v_value_json := case when v_field_def->>'type' = 'multi_select'
    then to_jsonb(array[v_answer_value])
    else to_jsonb(v_answer_value) end;
  v_error := crm.custom_field_value_error(v_field_def, v_value_json);

  if v_error is not null then
    -- A stale or tampered tap (e.g. an archived option) -- treat it the
    -- same as any other unrecognized reply.
    perform crm._send_nudge(v_state);
    return new;
  end if;

  update crm.contacts
  set custom_fields = custom_fields || jsonb_build_object(v_field_key, v_value_json)
  where id = v_contact_id;

  perform crm.write_audit(
    new.organization_id, 'lead.answer_recorded', 'lead', v_lead.id::text,
    jsonb_build_object('question_key', v_answer_question_key, 'field', v_field_key, 'value', v_value_json)
  );

  select * into v_next_question
  from crm._next_qualification_question(new.organization_id, v_contact_id);

  if v_next_question is null then
    perform crm._score_and_complete_qualification(new.organization_id, v_lead.id, v_contact_id);
  else
    update crm.lead_qualification_state
    set current_question_key = v_next_question.item_key, asked_at = now(),
        nudge_count = 0, last_nudged_at = null
    where lead_id = v_lead.id;

    perform crm._send_qualification_question(
      new.organization_id, v_contact_id, new.conversation_id, new.service,
      new.organization_address, new.conversation_address, v_next_question
    );
  end if;

  return new;
end;
$function$
;


