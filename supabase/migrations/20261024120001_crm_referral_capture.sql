alter table "crm"."contacts" add column "first_touch_at" timestamp with time zone;

alter table "crm"."contacts" add column "first_touch_referral" jsonb;

alter table "crm"."contacts" add column "last_touch_at" timestamp with time zone;

alter table "crm"."contacts" add column "last_touch_referral" jsonb;

alter table "public"."conversations" add column "referral" jsonb;

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.touch_contact_referral()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_contact uuid;
  v_referral jsonb := new.content->'referral';
begin
  select ca.contact_id into v_contact
  from crm.contact_addresses ca
  where ca.organization_id = new.organization_id
    and ca.service = new.service
    and ca.address = new.conversation_address;

  if v_contact is null then
    return new;
  end if;

  update crm.contacts
  set
    first_touch_referral = case
      when first_touch_at is null or new.timestamp < first_touch_at
        then v_referral
      else first_touch_referral
    end,
    first_touch_at = case
      when first_touch_at is null or new.timestamp < first_touch_at
        then new.timestamp
      else first_touch_at
    end,
    last_touch_referral = case
      when last_touch_at is null or new.timestamp > last_touch_at
        then v_referral
      else last_touch_referral
    end,
    last_touch_at = case
      when last_touch_at is null or new.timestamp > last_touch_at
        then new.timestamp
      else last_touch_at
    end
  where id = v_contact;

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.update_conversation_referral()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update public.conversations
  set referral = new.content->'referral'
  where id = new.conversation_id;

  return new;
end;
$function$
;

CREATE TRIGGER touch_contact_referral AFTER INSERT ON public.messages FOR EACH ROW WHEN (((new.sender_address IS NOT NULL) AND ((new.content -> 'referral'::text) IS NOT NULL))) EXECUTE FUNCTION crm.touch_contact_referral();

CREATE TRIGGER update_conversation_referral AFTER INSERT ON public.messages FOR EACH ROW WHEN (((new.sender_address IS NOT NULL) AND ((new.content -> 'referral'::text) IS NOT NULL))) EXECUTE FUNCTION public.update_conversation_referral();


