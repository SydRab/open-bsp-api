-- [crm] P3-03: instant welcome -- on a contact's first-ever inbound
-- message, ensure a lead exists (crm._ensure_lead, 10-29n) and, if the org
-- has opted in (messaging.instant_welcome, off by default), send a
-- language-choice buttons message. Entirely a database trigger, same as
-- P3-01's referral capture -- the insert below is a PLAIN public.messages
-- row, so it flows through the existing single send choke point
-- (_shared/send_policy.ts, called from whatsapp-dispatcher) exactly like
-- any other outbound message, with no new code there needed: the window
-- is open (a fresh inbound message is what just opened it), and this
-- isn't a template, so the marketing-only checks in checkSendPolicy don't
-- apply either.
--
-- "z_" so this fires AFTER crm.touch_contact_referral and public.
-- update_conversation_referral (alphabetical trigger order on the same
-- event) -- crm.contacts.first_touch_referral must already be set on this
-- exact message before this reads it to decide the lead's source.
create function crm.z_welcome_and_create_lead() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_contact_id uuid;
  v_contact crm.contacts;
  v_is_new_lead boolean;
  v_source text;
  v_welcome_on boolean;
begin
  select ca.contact_id into v_contact_id
  from crm.contact_addresses ca
  where ca.organization_id = new.organization_id
    and ca.service = new.service
    and ca.address = new.conversation_address;

  if v_contact_id is null then
    return new;
  end if;

  select * into v_contact from crm.contacts where id = v_contact_id;

  v_is_new_lead := not exists (
    select 1 from crm.leads
    where organization_id = new.organization_id and contact_id = v_contact_id
  );

  v_source := case
    when v_contact.first_touch_referral->>'source_type' = 'ad' then 'ctwa_ad'
    when v_contact.first_touch_referral->>'source_type' = 'post' then 'ctwa_post'
    else 'organic'
  end;

  perform crm._ensure_lead(new.organization_id, v_contact_id, v_source);

  if
    v_is_new_lead
    and new.service = 'whatsapp'
    and v_contact.welcome_sent_at is null
  then
    v_welcome_on := coalesce(
      (crm.get_setting(new.organization_id, 'messaging.instant_welcome') #>> '{}')::boolean,
      false
    );

    if v_welcome_on then
      insert into public.messages (
        organization_id, conversation_id, service, organization_address,
        conversation_address, content
      )
      values (
        new.organization_id, new.conversation_id, new.service, new.organization_address,
        new.conversation_address,
        jsonb_build_object(
          'version', '1',
          'type', 'data',
          'kind', 'interactive_buttons',
          'data', jsonb_build_object(
            'body',
            'Welcome! Please choose your preferred language.' || E'\n' ||
              'नमस्ते! कृपया अपनी पसंदीदा भाषा चुनें।',
            'buttons', jsonb_build_array(
              jsonb_build_object('id', 'lang_en', 'title', 'English'),
              jsonb_build_object('id', 'lang_hi', 'title', 'हिंदी')
            )
          )
        )
      );

      update crm.contacts set welcome_sent_at = now() where id = v_contact_id;
    end if;
  end if;

  return new;
end;
$$;

create trigger z_welcome_and_create_lead
after insert
on public.messages
for each row
when (new.sender_address is not null)
execute function crm.z_welcome_and_create_lead();

-- The other half: when the contact answers with one of the language
-- buttons, record their choice on crm.contacts.locale (P1-06, "for
-- templates and disclaimers") and send a short confirmation in that
-- language -- the same plain-insert mechanism as the welcome itself.
create function crm.z_apply_language_choice() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_contact_id uuid;
  -- Inbound replies to OUR sent interactive_buttons message arrive typed
  -- kind "interactive", data.type "button_reply" (Meta's own wire shape,
  -- stored as-is -- see message_types.ts's InteractivePart). Self-
  -- describing ids (lang_en/lang_hi, assigned when we sent the buttons)
  -- are what correlate the reply, not a reply-to/context match.
  v_button_id text := new.content->'data'->'button_reply'->>'id';
  v_locale text;
  v_confirmation text;
begin
  if new.content->>'kind' is distinct from 'interactive'
    or new.content->'data'->>'type' is distinct from 'button_reply'
    or v_button_id not in ('lang_en', 'lang_hi')
  then
    return new;
  end if;

  select ca.contact_id into v_contact_id
  from crm.contact_addresses ca
  where ca.organization_id = new.organization_id
    and ca.service = new.service
    and ca.address = new.conversation_address;

  if v_contact_id is null then
    return new;
  end if;

  v_locale := case v_button_id when 'lang_en' then 'en' else 'hi' end;
  v_confirmation := case v_button_id
    when 'lang_en' then 'Thanks! We will continue in English.'
    else 'धन्यवाद! हम हिंदी में जारी रखेंगे।'
  end;

  update crm.contacts set locale = v_locale where id = v_contact_id;

  insert into public.messages (
    organization_id, conversation_id, service, organization_address,
    conversation_address, content
  )
  values (
    new.organization_id, new.conversation_id, new.service, new.organization_address,
    new.conversation_address,
    jsonb_build_object(
      'version', '1', 'type', 'text', 'kind', 'text', 'text', v_confirmation
    )
  );

  return new;
end;
$$;

create trigger z_apply_language_choice
after insert
on public.messages
for each row
when (new.sender_address is not null)
execute function crm.z_apply_language_choice();
