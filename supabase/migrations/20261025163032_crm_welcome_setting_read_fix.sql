set check_function_bodies = off;

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
      ((select r.value from crm.resolve_setting(new.organization_id, 'messaging.instant_welcome') r) #>> '{}')::boolean,
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


