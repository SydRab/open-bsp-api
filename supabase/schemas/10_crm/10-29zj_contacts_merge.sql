-- [crm] P3-11d: merge two contacts into one -- the last P3-11 sub-phase.
-- Fully greenfield: no merged_into/alias/dedupe concept existed anywhere
-- before this (confirmed during P3-11's own up-front research). Addresses
-- move to the primary contact: crm.contact_addresses' own PK is
-- (organization_id, service, address), so a contact's addresses are
-- always disjoint from another contact's in the same org -- reassigning
-- can never collide. Routing is address-based (/contacts/$addressId), not
-- contact-id based, so every old link to an absorbed address still
-- resolves correctly afterwards, with no redirect/tombstone needed.
--
-- If both contacts already have their own lead, the merge is refused --
-- confirmed with the user: merging two full leads (deal history, notes,
-- tasks, SLA/assignment state) correctly is a separate, much bigger
-- feature, not guessed at here. A contact with zero or one lead between
-- the pair merges freely either way, and that lead (if any) follows its
-- contact to the primary.
create function crm.merge_contacts(
  p_primary_contact_id uuid,
  p_secondary_contact_id uuid
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_primary crm.contacts;
  v_secondary crm.contacts;
  v_primary_leads int;
  v_secondary_leads int;
begin
  if p_primary_contact_id = p_secondary_contact_id then
    raise exception 'cannot merge a contact with itself' using errcode = '22023';
  end if;

  select * into v_primary from crm.contacts where id = p_primary_contact_id;
  select * into v_secondary from crm.contacts where id = p_secondary_contact_id;
  if v_primary is null or v_secondary is null then
    raise exception 'contact not found' using errcode = 'P0002';
  end if;
  if v_primary.organization_id <> v_secondary.organization_id then
    raise exception 'contacts belong to different organizations' using errcode = '22023';
  end if;

  perform crm.require_permission(v_primary.organization_id, 'contacts.edit');

  select count(*) into v_primary_leads from crm.leads where contact_id = p_primary_contact_id;
  select count(*) into v_secondary_leads from crm.leads where contact_id = p_secondary_contact_id;
  if v_primary_leads > 0 and v_secondary_leads > 0 then
    raise exception
      'both contacts already have their own lead -- resolve that conflict manually before merging'
      using errcode = '55000';
  end if;

  update crm.contact_addresses
  set contact_id = p_primary_contact_id
  where contact_id = p_secondary_contact_id;

  -- At most one side has a lead (checked above), so this never collides
  -- with crm.leads' own unique (organization_id, contact_id).
  update crm.leads
  set contact_id = p_primary_contact_id
  where contact_id = p_secondary_contact_id;

  insert into crm.contact_tags (organization_id, contact_id, tag_id)
  select organization_id, p_primary_contact_id, tag_id
  from crm.contact_tags
  where contact_id = p_secondary_contact_id
  on conflict do nothing;

  -- Fields/name/locale: primary wins on conflict, secondary only fills a
  -- gap -- the same "merge in place" precedent CSV import (P3-11c)
  -- established. Touch (first|last)_touch together, never one alone: a
  -- referral and its own timestamp must stay paired to the same event.
  update crm.contacts set
    display_name = coalesce(v_primary.display_name, v_secondary.display_name),
    locale = coalesce(v_primary.locale, v_secondary.locale),
    custom_fields = v_secondary.custom_fields || v_primary.custom_fields,
    welcome_sent_at = coalesce(v_primary.welcome_sent_at, v_secondary.welcome_sent_at),
    first_touch_at = case
      when v_primary.first_touch_at is null then v_secondary.first_touch_at
      when v_secondary.first_touch_at is null then v_primary.first_touch_at
      else least(v_primary.first_touch_at, v_secondary.first_touch_at)
    end,
    first_touch_referral = case
      when v_primary.first_touch_at is null then v_secondary.first_touch_referral
      when v_secondary.first_touch_at is null then v_primary.first_touch_referral
      when v_secondary.first_touch_at < v_primary.first_touch_at then v_secondary.first_touch_referral
      else v_primary.first_touch_referral
    end,
    last_touch_at = case
      when v_primary.last_touch_at is null then v_secondary.last_touch_at
      when v_secondary.last_touch_at is null then v_primary.last_touch_at
      else greatest(v_primary.last_touch_at, v_secondary.last_touch_at)
    end,
    last_touch_referral = case
      when v_primary.last_touch_at is null then v_secondary.last_touch_referral
      when v_secondary.last_touch_at is null then v_primary.last_touch_referral
      when v_secondary.last_touch_at > v_primary.last_touch_at then v_secondary.last_touch_referral
      else v_primary.last_touch_referral
    end
  where id = p_primary_contact_id;

  delete from crm.contacts where id = p_secondary_contact_id;

  perform crm.write_audit(
    v_primary.organization_id, 'contact.merged', 'contact', p_primary_contact_id::text,
    jsonb_build_object('merged_contact_id', p_secondary_contact_id)
  );
end;
$$;
