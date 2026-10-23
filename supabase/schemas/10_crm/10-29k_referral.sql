-- [crm] P3-01: Click-to-WhatsApp referral capture, the lead-level half.
-- public.conversations.referral (02-03/03-05) is a simple "latest" cache;
-- this is the rigorous one -- first_touch/last_touch on crm.contacts,
-- correct regardless of the order webhooks are actually delivered in (a
-- real possibility, same caution P2-08 took with message statuses).
create function crm.touch_contact_referral() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

-- On public.messages, not crm.contacts -- same cross-schema-trigger
-- precedent as crm.after_insert_on_contacts_addresses (10-24), which also
-- attaches a crm function to an upstream table's insert.
create trigger touch_contact_referral
after insert
on public.messages
for each row
when (new.sender_address is not null and new.content->'referral' is not null)
execute function crm.touch_contact_referral();
