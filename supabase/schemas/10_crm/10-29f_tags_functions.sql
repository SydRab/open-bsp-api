-- [crm] P2-09b: tag management. Gated on 'conversations.view' rather than a
-- new permission -- every role from viewer upward already has it, tagging
-- is a low-stakes organizational action (not a send, not a destructive
-- op), and a dedicated 'conversations.manage' permission would mean a
-- default on/off decision for all 8 preset roles plus an extra row in the
-- admin console's role editor for a feature this small. Revisit if tag
-- management ever needs to be restricted more tightly than viewing is.

create function crm.create_tag(p_organization_id uuid, p_name text) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_id uuid;
begin
  perform crm.require_permission(p_organization_id, 'conversations.view');

  insert into crm.tags (organization_id, name)
  values (p_organization_id, trim(p_name))
  returning id into v_id;

  return v_id;
end;
$$;

create function crm.rename_tag(p_tag_id uuid, p_name text) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(
    (select t.organization_id from crm.tags t where t.id = p_tag_id),
    'conversations.view'
  );

  update crm.tags set name = trim(p_name) where id = p_tag_id;
end;
$$;

create function crm.set_tag_color(p_tag_id uuid, p_color text) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(
    (select t.organization_id from crm.tags t where t.id = p_tag_id),
    'conversations.view'
  );

  update crm.tags set color = p_color where id = p_tag_id;
end;
$$;

create function crm.delete_tag(p_tag_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(
    (select t.organization_id from crm.tags t where t.id = p_tag_id),
    'conversations.view'
  );

  delete from crm.tags where id = p_tag_id;
end;
$$;

-- Adds (p_tagged true) or removes a tag from a conversation. Idempotent
-- either way (on conflict do nothing / a delete that matches zero rows is
-- not an error) -- same reasoning as crm.set_team_member.
create function crm.set_conversation_tag(
  p_conversation_id uuid,
  p_tag_id uuid,
  p_tagged boolean
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_org uuid := (
    select c.organization_id from public.conversations c
    where c.id = p_conversation_id
  );
begin
  perform crm.require_permission(v_org, 'conversations.view');

  if not p_tagged then
    delete from crm.conversation_tags
    where conversation_id = p_conversation_id and tag_id = p_tag_id;
    return;
  end if;

  if not exists (
    select 1 from crm.tags t
    where t.id = p_tag_id and t.organization_id = v_org
  ) then
    raise exception 'tag not found' using errcode = '22023';
  end if;

  insert into crm.conversation_tags (organization_id, conversation_id, tag_id)
  values (v_org, p_conversation_id, p_tag_id)
  on conflict do nothing;
end;
$$;
