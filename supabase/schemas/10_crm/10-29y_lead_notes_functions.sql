-- [crm] P3-07e: lead note CRUD, gated on deals.edit (the same bar every
-- other lead-working action uses since P3-02) plus the lead_scope
-- visibility check crm._lead_visible_to_caller (P3-07d) already
-- centralizes. Not author-locked -- any member who can work the lead can
-- edit or delete any note on it, same shared-collaboration model
-- conversation-level internal notes (P2-09a) already use (team-editable,
-- not author-only), stated plainly rather than guessed.

create function crm.create_lead_note(p_lead_id uuid, p_body text) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_org uuid;
  v_self uuid;
  v_id uuid;
begin
  select l.organization_id into v_org from crm.leads l where l.id = p_lead_id;
  if v_org is null then
    raise exception 'lead not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_org, 'deals.edit');

  if not crm._lead_visible_to_caller(p_lead_id) then
    raise exception 'lead not found' using errcode = 'P0002';
  end if;

  v_self := (crm.caller_agent(v_org)).id;

  insert into crm.lead_notes (organization_id, lead_id, author_agent_id, body)
  values (v_org, p_lead_id, v_self, trim(p_body))
  returning id into v_id;

  perform crm.write_audit(
    v_org, 'lead.note_created', 'lead', p_lead_id::text,
    jsonb_build_object('note_id', v_id)
  );

  return v_id;
end;
$$;

create function crm.update_lead_note(p_id uuid, p_body text) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_note crm.lead_notes;
begin
  select * into v_note from crm.lead_notes where id = p_id;
  if not found then
    raise exception 'note not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_note.organization_id, 'deals.edit');

  if not crm._lead_visible_to_caller(v_note.lead_id) then
    raise exception 'note not found' using errcode = 'P0002';
  end if;

  update crm.lead_notes set body = trim(p_body) where id = p_id;

  perform crm.write_audit(
    v_note.organization_id, 'lead.note_updated', 'lead', v_note.lead_id::text,
    jsonb_build_object('note_id', p_id)
  );
end;
$$;

create function crm.delete_lead_note(p_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_note crm.lead_notes;
begin
  select * into v_note from crm.lead_notes where id = p_id;
  if not found then
    raise exception 'note not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_note.organization_id, 'deals.edit');

  if not crm._lead_visible_to_caller(v_note.lead_id) then
    raise exception 'note not found' using errcode = 'P0002';
  end if;

  delete from crm.lead_notes where id = p_id;

  perform crm.write_audit(
    v_note.organization_id, 'lead.note_deleted', 'lead', v_note.lead_id::text,
    jsonb_build_object('note_id', p_id)
  );
end;
$$;
