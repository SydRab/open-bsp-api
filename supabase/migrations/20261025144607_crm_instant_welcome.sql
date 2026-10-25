alter table "crm"."contacts" add column "welcome_sent_at" timestamp with time zone;

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm._ensure_lead(p_organization_id uuid, p_contact_id uuid, p_source text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lead crm.leads;
  v_id uuid;
begin
  select * into v_lead from crm.leads
  where organization_id = p_organization_id and contact_id = p_contact_id;

  if found then
    -- Reopen rule: dropped/unqualified can come back to open (a lead
    -- messaging again is still working the same pursuit). converted is
    -- terminal -- a repeat inquiry from an already-enrolled contact is a
    -- different scenario (upsell/renewal) this phase's strict
    -- one-lead-per-contact dedupe isn't designed for.
    if v_lead.status in ('dropped', 'unqualified') then
      update crm.leads
      set status = 'open', drop_reason_id = null
      where id = v_lead.id;

      perform crm.write_audit(
        p_organization_id, 'lead.reopened', 'lead', v_lead.id::text,
        jsonb_build_object('from_status', v_lead.status)
      );
    end if;

    return v_lead.id;
  end if;

  insert into crm.leads (organization_id, contact_id, source)
  values (p_organization_id, p_contact_id, p_source)
  returning id into v_id;

  perform crm.write_audit(
    p_organization_id, 'lead.created', 'lead', v_id::text,
    jsonb_build_object('source', p_source)
  );

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.z_apply_language_choice()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.z_welcome_and_create_lead()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.find_or_create_lead(p_organization_id uuid, p_contact_id uuid, p_source text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(p_organization_id, 'deals.edit');

  return crm._ensure_lead(p_organization_id, p_contact_id, p_source);
end;
$function$
;

CREATE TRIGGER z_apply_language_choice AFTER INSERT ON public.messages FOR EACH ROW WHEN ((new.sender_address IS NOT NULL)) EXECUTE FUNCTION crm.z_apply_language_choice();

CREATE TRIGGER z_welcome_and_create_lead AFTER INSERT ON public.messages FOR EACH ROW WHEN ((new.sender_address IS NOT NULL)) EXECUTE FUNCTION crm.z_welcome_and_create_lead();


