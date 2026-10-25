-- [crm] P3-04: qualification engine functions.
--
-- Scoring catalog management (set/delete a score or threshold) is gated on
-- 'organization.manage', the same bar P3-02 used for the lead catalogs --
-- "configure org settings," no new permission.
--
-- The engine itself (starting, resuming, answering, nudging) runs from a
-- database trigger (crm.z_run_qualification_engine, below) with no member/
-- JWT context, so its internal functions (prefixed _) skip permission
-- checks entirely -- the same reasoning crm._ensure_lead (10-29n, P3-03)
-- already established for a pure system side effect.

-- Platform defaults -> one org's editable copy, the same shape crm.
-- seed_lead_catalogs (P3-02) uses. Called from crm.after_insert_on_
-- organizations (10-20_triggers.sql), after seed_lead_catalogs so crm.
-- lead_qualities already has rows to resolve quality_key against.
create function crm.seed_qualification_scoring(p_organization_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_pack_key text;
begin
  select pack_key into v_pack_key
  from crm.organization_packs
  where organization_id = p_organization_id;

  -- No pack applied (e.g. mid-migration) -- same no-op guard crm.
  -- apply_default_pack already uses.
  if v_pack_key is null then
    return;
  end if;

  insert into crm.qualification_question_scores (organization_id, field_key, answer_value, points)
  select p_organization_id, s.field_key, s.answer_value, s.points
  from crm.preset_qualification_question_scores s
  where s.pack_key = v_pack_key
  on conflict (organization_id, field_key, answer_value) do nothing;

  insert into crm.qualification_score_thresholds (organization_id, min_score, quality_id, status)
  select p_organization_id, t.min_score, q.id, t.status
  from crm.preset_qualification_score_thresholds t
  join crm.lead_qualities q
    on q.organization_id = p_organization_id and q.key = t.quality_key
  where t.pack_key = v_pack_key
  on conflict (organization_id, min_score) do nothing;
end;
$$;

-- Scoring catalog CRUD (organization.manage) ----------------------------------------------

create function crm.set_qualification_question_score(
  p_organization_id uuid,
  p_field_key text,
  p_answer_value text,
  p_points int
) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_id uuid;
begin
  perform crm.require_permission(p_organization_id, 'organization.manage');

  insert into crm.qualification_question_scores (organization_id, field_key, answer_value, points)
  values (p_organization_id, p_field_key, p_answer_value, p_points)
  on conflict (organization_id, field_key, answer_value) do update
    set points = excluded.points
  returning id into v_id;

  return v_id;
end;
$$;

create function crm.delete_qualification_question_score(p_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(
    (select organization_id from crm.qualification_question_scores where id = p_id),
    'organization.manage'
  );

  delete from crm.qualification_question_scores where id = p_id;
end;
$$;

create function crm.set_score_threshold(
  p_organization_id uuid,
  p_min_score int,
  p_quality_id uuid,
  p_status text
) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_id uuid;
begin
  perform crm.require_permission(p_organization_id, 'organization.manage');

  if p_status not in ('qualified', 'unqualified') then
    raise exception 'status must be qualified or unqualified' using errcode = '22023';
  end if;
  if p_quality_id is not null and not exists (
    select 1 from crm.lead_qualities where id = p_quality_id and organization_id = p_organization_id
  ) then
    raise exception 'quality not found' using errcode = '22023';
  end if;

  insert into crm.qualification_score_thresholds (organization_id, min_score, quality_id, status)
  values (p_organization_id, p_min_score, p_quality_id, p_status)
  on conflict (organization_id, min_score) do update
    set quality_id = excluded.quality_id, status = excluded.status
  returning id into v_id;

  return v_id;
end;
$$;

create function crm.delete_score_threshold(p_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(
    (select organization_id from crm.qualification_score_thresholds where id = p_id),
    'organization.manage'
  );

  delete from crm.qualification_score_thresholds where id = p_id;
end;
$$;

-- Engine internals (unchecked -- see header note) ------------------------------------------

-- The next pack question this contact hasn't answered yet, in the pack's
-- own sort_order. Skipping already-answered fields (by key, in crm.
-- contacts.custom_fields) is what makes this resumable: a process restart,
-- an out-of-order reply, or a field someone filled in some other way all
-- converge on the same next question.
create function crm._next_qualification_question(
  p_organization_id uuid,
  p_contact_id uuid
) returns crm.organization_pack_items
language sql
stable
security definer
set search_path to ''
as $$
  select i.*
  from crm.organization_pack_items i
  join crm.contacts c on c.id = p_contact_id
  where i.organization_id = p_organization_id
    and i.kind = 'qualification_question'
    and not i.removed_from_pack
    and not (c.custom_fields ? (i.value->>'field'))
  order by i.sort_order
  limit 1;
$$;

-- Sends one question as buttons (<=3 options) or a list (<=10): the only
-- two shapes this task builds, matching every current question's field --
-- WhatsApp Flow delivery (already built generically, P2-06) is left for
-- whichever future question needs a richer form. A plain public.messages
-- insert, same choke-point trick as P3-03's welcome: it flows through
-- _shared/send_policy.ts automatically regardless of what inserted it.
create function crm._send_qualification_question(
  p_organization_id uuid,
  p_contact_id uuid,
  p_conversation_id uuid,
  p_service public.service,
  p_organization_address text,
  p_conversation_address text,
  p_question crm.organization_pack_items,
  p_is_nudge boolean default false
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_locale text;
  v_field_key text := p_question.value->>'field';
  v_field jsonb;
  v_options jsonb;
  v_option_count int;
  v_prompt text;
  v_rows jsonb;
  v_content jsonb;
begin
  select coalesce(c.locale, 'en') into v_locale from crm.contacts c where c.id = p_contact_id;

  v_field := crm.custom_field_definition(p_organization_id, 'contact', v_field_key);
  v_options := coalesce(v_field->'options', '[]'::jsonb);
  v_option_count := jsonb_array_length(v_options);

  if v_option_count = 0 or v_option_count > 10 then
    -- Not a choice field, or more options than a list can hold -- a pack
    -- configuration problem, not a runtime one. Nothing to send.
    return;
  end if;

  v_prompt := coalesce(p_question.value->'prompt'->>v_locale, p_question.value->'prompt'->>'en', '');
  if p_is_nudge then
    v_prompt := case when v_locale = 'hi'
      then 'सिर्फ़ चेक कर रहे हैं। ' || v_prompt
      else 'Just checking in. ' || v_prompt end;
  end if;

  select jsonb_agg(jsonb_build_object(
    'id', p_question.item_key || '::' || (o->>'value'),
    'title', coalesce(o->'label'->>v_locale, o->'label'->>'en')
  ))
  into v_rows
  from jsonb_array_elements(v_options) o;

  if v_option_count <= 3 then
    v_content := jsonb_build_object(
      'version', '1', 'type', 'data', 'kind', 'interactive_buttons',
      'data', jsonb_build_object('body', v_prompt, 'buttons', v_rows)
    );
  else
    v_content := jsonb_build_object(
      'version', '1', 'type', 'data', 'kind', 'interactive_list',
      'data', jsonb_build_object(
        'body', v_prompt,
        'button', case when v_locale = 'hi' then 'चुनें' else 'Choose' end,
        'sections', jsonb_build_array(jsonb_build_object(
          'title', case when v_locale = 'hi' then 'विकल्प' else 'Options' end,
          'rows', v_rows
        ))
      )
    );
  end if;

  insert into public.messages (
    organization_id, conversation_id, service, organization_address,
    conversation_address, content
  ) values (
    p_organization_id, p_conversation_id, p_service, p_organization_address,
    p_conversation_address, v_content
  );
end;
$$;

-- Sums points for every answer already on the contact (matching a select's
-- exact value or a multi_select's containment -- no join to field defs
-- needed, so this works regardless of how a value got there), picks the
-- highest min_score band the total clears, and applies it. A lead that
-- moved on (no longer 'open', e.g. a human already converted/dropped it)
-- is left untouched -- only the state row closes, so the engine stops.
create function crm._score_and_complete_qualification(
  p_organization_id uuid,
  p_lead_id uuid,
  p_contact_id uuid
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_fields jsonb;
  v_score int;
  v_band crm.qualification_score_thresholds;
begin
  select custom_fields into v_fields from crm.contacts where id = p_contact_id;

  select coalesce(sum(s.points), 0) into v_score
  from crm.qualification_question_scores s
  where s.organization_id = p_organization_id
    and (
      v_fields->s.field_key = to_jsonb(s.answer_value)
      or (
        jsonb_typeof(v_fields->s.field_key) = 'array'
        and v_fields->s.field_key @> to_jsonb(array[s.answer_value])
      )
    );

  select * into v_band
  from crm.qualification_score_thresholds
  where organization_id = p_organization_id and min_score <= v_score
  order by min_score desc
  limit 1;

  update crm.leads
  set score = v_score,
      quality_id = v_band.quality_id,
      status = coalesce(v_band.status, status)
  where id = p_lead_id and status = 'open';

  perform crm.write_audit(
    p_organization_id, 'lead.qualification_completed', 'lead', p_lead_id::text,
    jsonb_build_object('score', v_score, 'status', v_band.status, 'quality_id', v_band.quality_id)
  );

  update crm.lead_qualification_state
  set completed_at = now(), current_question_key = null
  where lead_id = p_lead_id;
end;
$$;

-- Re-sends the currently pending question, within the org's nudge budget
-- (qualification.max_nudges, default 2). Past the budget, this silently
-- does nothing -- confirmed with the user: leave the lead open for manual
-- follow-up, no automatic drop. Shared by both callers: the inline trigger
-- (an unrecognized reply) and the timeout sweep (crm.sweep_qualification_
-- nudges, below) -- one place decides "has this lead been nudged enough."
create function crm._send_nudge(p_state crm.lead_qualification_state) returns void
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

-- pg_cron sweep (schedule: a hand-written migration, same imperative
-- exception CLAUDE.md already documents for cron.schedule). Pure SQL, no
-- edge-function round-trip -- mirrors crm.purge_webhook_events' pattern.
create function crm.sweep_qualification_nudges() returns void
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

-- The trigger: starts qualification on a lead's first inbound message (if
-- qualification.auto_start is on), records a recognized button/list
-- answer and advances, or nudges on anything else. Calls crm._ensure_lead
-- itself (same derivation P3-03's z_welcome_and_create_lead uses) instead
-- of relying on trigger firing order, so it works whichever of the two
-- public.messages triggers runs first.
create function crm.z_run_qualification_engine() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

create trigger z_run_qualification_engine
after insert
on public.messages
for each row
when (new.sender_address is not null)
execute function crm.z_run_qualification_engine();
