-- Members, roles and invitations (P1-02, P1-03). Every function here is
-- SECURITY DEFINER and checks authority itself:
--
--   * the caller needs the permission (members.invite, members.manage,
--     roles.manage) in the target organization, and
--   * nobody acts above their own tier: an admin cannot invite, promote,
--     demote or deactivate an owner, nor grant the owner role. Only owners
--     make owners.
--   * nobody grants a permission they do not hold themselves.
--
-- The upstream last-owner guard still applies: changing a member's crm role
-- updates public.agents.role (10-20), and the upstream trigger refuses to
-- demote the last owner.

-- The preset a member gets when only their tier is known (seeded members,
-- the upstream role editor, invitations made outside crm.invite_member).
-- Least privilege for the member tier.
create function crm.default_role_key(p_tier public.role) returns text
language sql
immutable
set search_path to ''
as $$
  select case p_tier
    when 'owner' then 'owner'
    when 'admin' then 'admin'
    else 'viewer'
  end;
$$;

-- Loads the target member and checks the caller may manage them.
create function crm.assert_can_manage_member(p_agent_id uuid)
returns public.agents
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_target public.agents;
  v_caller public.agents;
begin
  select * into v_target
  from public.agents
  where id = p_agent_id
    and user_id is not null
    and deleted_at is null;

  if not found then
    raise exception 'member not found'
      using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_target.organization_id, 'members.manage');

  v_caller := crm.caller_agent(v_target.organization_id);

  if crm.tier_rank(v_target.role) > crm.tier_rank(v_caller.role) then
    raise exception 'cannot manage a member above your own role'
      using errcode = '42501';
  end if;

  return v_target;
end;
$$;

-- Creates an invitation for a crm role. The upstream row carries the role's
-- tier, crm.invitation_roles the role itself; accepting goes through the
-- upstream public.accept_invitation(), and crm.after_agent_change (10-20)
-- gives the new member this role. The email is sent by the crm-invitations
-- edge function, which calls this first.
create function crm.invite_member(
  p_organization_id uuid,
  p_email text,
  p_role_key text
) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_email text := lower(trim(p_email));
  v_caller public.agents;
  v_role crm.roles;
  v_invitation_id uuid;
begin
  perform crm.require_permission(p_organization_id, 'members.invite');
  v_caller := crm.caller_agent(p_organization_id);

  -- A friendly check for the inviting admin (P1-09): the seat is only truly
  -- consumed, and the limit truly enforced, when the invitee accepts
  -- (crm.track_member_usage, 10-25).
  perform billing.check_limit(p_organization_id, 'members');

  if v_email is null or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'invalid email address'
      using errcode = '22023';
  end if;

  select * into v_role
  from crm.roles
  where organization_id = p_organization_id
    and key = p_role_key;

  if not found then
    raise exception 'unknown role %', p_role_key
      using errcode = '22023';
  end if;

  if crm.tier_rank(v_role.tier) > crm.tier_rank(v_caller.role) then
    raise exception 'cannot invite someone to a role above your own'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.agents a
    join auth.users u on u.id = a.user_id
    where a.organization_id = p_organization_id
      and a.deleted_at is null
      and lower(u.email) = v_email
  ) then
    raise exception 'already a member of this organization'
      using errcode = '23505';
  end if;

  -- A second pending invitation for the same email fails on the upstream
  -- unique index invitations_pending_email_key (23505).
  insert into public.invitations (organization_id, email, role, invited_by)
  values (p_organization_id, v_email, v_role.tier, v_caller.id)
  returning id into v_invitation_id;

  insert into crm.invitation_roles (invitation_id, organization_id, role_id)
  values (v_invitation_id, p_organization_id, v_role.id);

  return v_invitation_id;
end;
$$;

create function crm.revoke_invitation(p_invitation_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_invitation public.invitations;
begin
  select * into v_invitation
  from public.invitations
  where id = p_invitation_id;

  if not found then
    raise exception 'invitation not found'
      using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_invitation.organization_id, 'members.invite');

  if crm.tier_rank(v_invitation.role)
    > crm.tier_rank((crm.caller_agent(v_invitation.organization_id)).role) then
    raise exception 'cannot revoke an invitation above your own role'
      using errcode = '42501';
  end if;

  update public.invitations
  set status = 'revoked'
  where id = p_invitation_id
    and status = 'pending';
end;
$$;

-- The crm role each of the caller's pending invitations offers, for the
-- invitation card. The invitee is not a member yet, so they cannot read the
-- organization's roles; this returns only the name and key of the role on
-- invitations addressed to their own email.
create function crm.get_my_invitation_roles()
returns table (invitation_id uuid, role_key text, role_name text)
language sql
stable
security definer
set search_path to ''
as $$
  select ir.invitation_id, r.key, r.name
  from crm.invitation_roles ir
  join public.invitations i on i.id = ir.invitation_id
  join crm.roles r on r.id = ir.role_id
  where i.status = 'pending'
    and lower(i.email) = lower(auth.jwt()->>'email');
$$;

-- Role change. Moving someone off the owner role is refused by the upstream
-- last-owner guard if they are the last owner.
create function crm.set_member_role(p_agent_id uuid, p_role_key text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_target public.agents := crm.assert_can_manage_member(p_agent_id);
  v_role crm.roles;
begin
  select * into v_role
  from crm.roles
  where organization_id = v_target.organization_id
    and key = p_role_key;

  if not found then
    raise exception 'unknown role %', p_role_key
      using errcode = '22023';
  end if;

  if crm.tier_rank(v_role.tier)
    > crm.tier_rank((crm.caller_agent(v_target.organization_id)).role) then
    raise exception 'cannot grant a role above your own'
      using errcode = '42501';
  end if;

  insert into crm.member_roles (agent_id, organization_id, role_id)
  values (v_target.id, v_target.organization_id, v_role.id)
  on conflict (agent_id) do update
    set role_id = excluded.role_id,
        updated_at = now();
end;
$$;

-- Deactivation is the upstream soft delete (agents.deleted_at): the row and
-- its authorship stay, access ends, and a later invitation revives the same
-- agent. Leaving yourself goes through the upstream "members can delete
-- themselves" path instead.
create function crm.deactivate_member(p_agent_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_target public.agents := crm.assert_can_manage_member(p_agent_id);
begin
  if v_target.user_id = auth.uid() then
    raise exception 'use leave organization to remove yourself'
      using errcode = '22023';
  end if;

  delete from public.agents where id = v_target.id;
end;
$$;

-- Lead visibility override for one member: 'own', 'team', 'all', or null to
-- use the role's default.
create function crm.set_member_lead_scope(p_agent_id uuid, p_lead_scope text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_target public.agents := crm.assert_can_manage_member(p_agent_id);
begin
  update crm.member_roles
  set lead_scope = p_lead_scope,
      updated_at = now()
  where agent_id = v_target.id;
end;
$$;

-- Per-member permission exception. p_granted null removes the override.
create function crm.set_member_permission_override(
  p_agent_id uuid,
  p_permission text,
  p_granted boolean
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_target public.agents := crm.assert_can_manage_member(p_agent_id);
  v_permission crm.permissions;
begin
  select * into v_permission from crm.permissions where key = p_permission;

  if not found then
    raise exception 'unknown permission %', p_permission
      using errcode = '22023';
  end if;

  if p_granted is null then
    delete from crm.member_permission_overrides
    where agent_id = v_target.id and permission = p_permission;
    return;
  end if;

  if p_granted then
    if crm.tier_rank(v_permission.min_tier) > crm.tier_rank(v_target.role) then
      raise exception 'permission % needs the % tier', p_permission, v_permission.min_tier
        using errcode = '22023';
    end if;

    perform crm.require_permission(v_target.organization_id, p_permission);
  end if;

  insert into crm.member_permission_overrides (
    agent_id, organization_id, permission, granted
  )
  values (v_target.id, v_target.organization_id, p_permission, p_granted)
  on conflict (agent_id, permission) do update
    set granted = excluded.granted;
end;
$$;

-- WhatsApp number access. Allowing the first number turns the restriction on
-- for that member; removing the last one turns it off (sees all again).
create function crm.set_member_address_access(
  p_agent_id uuid,
  p_service public.service,
  p_address text,
  p_allowed boolean
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_target public.agents := crm.assert_can_manage_member(p_agent_id);
begin
  if p_allowed then
    insert into crm.member_address_access (
      agent_id, organization_id, service, address
    )
    values (v_target.id, v_target.organization_id, p_service, p_address)
    on conflict do nothing;
  else
    delete from crm.member_address_access
    where agent_id = v_target.id
      and service = p_service
      and address = p_address;
  end if;
end;
$$;

-- Loads a role and checks the caller may edit its permissions.
create function crm.assert_can_edit_role(p_role_id uuid) returns crm.roles
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_role crm.roles;
  v_caller public.agents;
begin
  select * into v_role from crm.roles where id = p_role_id;

  if not found then
    raise exception 'role not found'
      using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_role.organization_id, 'roles.manage');

  if v_role.is_locked then
    raise exception 'the % role cannot be changed', v_role.name
      using errcode = '42501';
  end if;

  v_caller := crm.caller_agent(v_role.organization_id);

  -- Owners edit any unlocked role; everyone else only roles below their own
  -- tier (an admin cannot widen the admin role they hold).
  if v_caller.role <> 'owner'
    and crm.tier_rank(v_role.tier) >= crm.tier_rank(v_caller.role) then
    raise exception 'cannot change a role at or above your own'
      using errcode = '42501';
  end if;

  return v_role;
end;
$$;

-- The per-tenant permission toggle.
create function crm.set_role_permission(
  p_role_id uuid,
  p_permission text,
  p_enabled boolean
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_role crm.roles := crm.assert_can_edit_role(p_role_id);
  v_permission crm.permissions;
begin
  select * into v_permission from crm.permissions where key = p_permission;

  if not found then
    raise exception 'unknown permission %', p_permission
      using errcode = '22023';
  end if;

  if not p_enabled then
    delete from crm.role_permissions
    where role_id = v_role.id and permission = p_permission;
    return;
  end if;

  if crm.tier_rank(v_permission.min_tier) > crm.tier_rank(v_role.tier) then
    raise exception 'permission % needs the % tier', p_permission, v_permission.min_tier
      using errcode = '22023';
  end if;

  perform crm.require_permission(v_role.organization_id, p_permission);

  insert into crm.role_permissions (organization_id, role_id, permission)
  values (v_role.organization_id, v_role.id, p_permission)
  on conflict do nothing;
end;
$$;

-- Back to the preset's defaults. Only for preset roles. Like a toggle, it
-- never hands out a permission the caller does not hold.
create function crm.reset_role_permissions(p_role_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_role crm.roles := crm.assert_can_edit_role(p_role_id);
begin
  if not v_role.is_preset then
    raise exception 'only preset roles have defaults'
      using errcode = '22023';
  end if;

  delete from crm.role_permissions where role_id = v_role.id;

  insert into crm.role_permissions (organization_id, role_id, permission)
  select v_role.organization_id, v_role.id, prp.permission
  from crm.preset_role_permissions prp
  where prp.role_key = v_role.key
    and crm.has_permission(v_role.organization_id, prp.permission);
end;
$$;
