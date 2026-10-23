-- [crm] P2-09e: canned reply management, gated on 'templates.manage' -- a
-- canned reply is exactly what that permission already describes ("Create
-- and edit message templates"), just not a Meta-approved one. By default
-- that's admin + marketing, echoing the dropped upstream policy's
-- admins-manage/members-read split without hardcoding a tier.

create function crm.create_canned_reply(
  p_organization_id uuid,
  p_name text,
  p_content text
) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_id uuid;
begin
  perform crm.require_permission(p_organization_id, 'templates.manage');

  insert into crm.canned_replies (organization_id, name, content)
  values (p_organization_id, trim(p_name), trim(p_content))
  returning id into v_id;

  return v_id;
end;
$$;

create function crm.update_canned_reply(
  p_id uuid,
  p_name text,
  p_content text
) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(
    (select r.organization_id from crm.canned_replies r where r.id = p_id),
    'templates.manage'
  );

  update crm.canned_replies
  set name = trim(p_name), content = trim(p_content)
  where id = p_id;
end;
$$;

create function crm.delete_canned_reply(p_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(
    (select r.organization_id from crm.canned_replies r where r.id = p_id),
    'templates.manage'
  );

  delete from crm.canned_replies where id = p_id;
end;
$$;
