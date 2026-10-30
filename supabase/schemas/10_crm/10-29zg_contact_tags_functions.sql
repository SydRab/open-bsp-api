-- [crm] P3-11b: tag/untag a contact. Gated on `contacts.edit`
-- ("Add and edit contacts and leads," P1-02) -- a different bar than
-- crm.set_conversation_tag's `conversations.view` (P2-09b's own
-- deliberate "tagging is low-stakes" choice for THAT entity), because
-- this one touches a contact's own organizational metadata, which is
-- exactly what `contacts.edit` already names. The shared crm.tags
-- catalog itself (create/rename/recolor/delete) is untouched -- still
-- gated `conversations.view`, same as P2-09b left it.
create function crm.set_contact_tag(
  p_contact_id uuid,
  p_tag_id uuid,
  p_tagged boolean
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_org uuid := (
    select c.organization_id from crm.contacts c where c.id = p_contact_id
  );
begin
  if v_org is null then
    raise exception 'contact not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_org, 'contacts.edit');

  if not p_tagged then
    delete from crm.contact_tags
    where contact_id = p_contact_id and tag_id = p_tag_id;
    return;
  end if;

  if not exists (
    select 1 from crm.tags t where t.id = p_tag_id and t.organization_id = v_org
  ) then
    raise exception 'tag not found' using errcode = '22023';
  end if;

  insert into crm.contact_tags (organization_id, contact_id, tag_id)
  values (v_org, p_contact_id, p_tag_id)
  on conflict do nothing;
end;
$$;
