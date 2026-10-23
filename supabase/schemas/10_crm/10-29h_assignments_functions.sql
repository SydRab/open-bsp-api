-- [crm] P2-09c: assign/transfer/unassign. Gated on 'messages.send' rather
-- than 'conversations.view' (the gate tags used): assignment is an
-- operational inbox action -- whoever can actually work a conversation can
-- also claim it or hand it off -- not a passive organizational label like a
-- tag. This also excludes read-only 'viewer' and 'marketing' (which has
-- conversations.view but not messages.send), matching their role
-- descriptions better than reusing conversations.view would have.
--
-- One gate for all three operations (claim, reassign away from someone
-- else, unassign) -- no extra rule letting only admins reassign work that
-- isn't theirs. Revisit if that turns out to be too permissive in practice.

create function crm.assign_conversation(
  p_conversation_id uuid,
  p_agent_id uuid
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
  perform crm.require_permission(v_org, 'messages.send');

  if not exists (
    select 1 from public.agents a
    where a.id = p_agent_id
      and a.organization_id = v_org
      and a.deleted_at is null
  ) then
    raise exception 'agent not found' using errcode = '22023';
  end if;

  insert into crm.conversation_assignments (organization_id, conversation_id, agent_id)
  values (v_org, p_conversation_id, p_agent_id)
  on conflict (conversation_id) do update set agent_id = excluded.agent_id;
end;
$$;

create function crm.unassign_conversation(p_conversation_id uuid) returns void
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
  perform crm.require_permission(v_org, 'messages.send');

  delete from crm.conversation_assignments where conversation_id = p_conversation_id;
end;
$$;
