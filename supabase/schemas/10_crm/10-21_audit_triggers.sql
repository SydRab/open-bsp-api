-- Audit triggers (P1-08). Each turns a row change into one crm.audit_log
-- entry through crm.write_audit (10-14). Triggers, not calls inside the crm
-- functions, so every path is covered: the crm functions, upstream screens,
-- API keys and the platform.
--
-- Actions written here:
--   organization.created, organization.profile_updated, organization.suspended,
--   organization.reactivated, organization.deletion_requested,
--   organization.deletion_cancelled, organization.mfa_requirement_changed
--   member.joined, member.deactivated, member.reactivated, member.role_changed,
--   member.lead_scope_changed, member.permission_override_set,
--   member.permission_override_removed, member.number_access_granted,
--   member.number_access_revoked
--   role.permission_granted, role.permission_revoked
--   invitation.created, invitation.accepted, invitation.rejected,
--   invitation.revoked
--   pack.applied, pack.upgraded, pack.item_updated, pack.item_reset

-- Append-only guard ------------------------------------------------------------

create trigger append_only
before update or delete
on crm.audit_log
for each row
execute function crm.before_change_on_audit_log();

create trigger append_only_truncate
before truncate
on crm.audit_log
for each statement
execute function crm.before_change_on_audit_log();

-- Organization -----------------------------------------------------------------

create function crm.audit_organization_profiles() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_before jsonb := '{}'::jsonb;
  v_after jsonb := '{}'::jsonb;
  v_field text;
begin
  if tg_op = 'INSERT' then
    perform crm.write_audit(
      new.organization_id, 'organization.created', 'organization',
      new.organization_id::text,
      jsonb_build_object(
        'slug', new.slug, 'timezone', new.timezone, 'locale', new.locale
      )
    );
    return null;
  end if;

  if new.status is distinct from old.status then
    perform crm.write_audit(
      new.organization_id,
      case
        when new.status = 'suspended' then 'organization.suspended'
        when new.status = 'pending_deletion' then 'organization.deletion_requested'
        when old.status = 'suspended' then 'organization.reactivated'
        else 'organization.deletion_cancelled'
      end,
      'organization',
      new.organization_id::text,
      jsonb_strip_nulls(jsonb_build_object(
        'reason', new.suspended_reason,
        'purge_after', new.purge_after
      ))
    );
  end if;

  -- The fields a tenant edits: profile (P1-01) and business details (P1-07).
  for v_field in select unnest(array[
    'slug', 'timezone', 'locale', 'legal_name', 'address', 'support_email',
    'support_phone', 'website', 'registrations'
  ]) loop
    if to_jsonb(new)->v_field is distinct from to_jsonb(old)->v_field then
      v_before := v_before || jsonb_build_object(v_field, to_jsonb(old)->v_field);
      v_after := v_after || jsonb_build_object(v_field, to_jsonb(new)->v_field);
    end if;
  end loop;

  if v_after <> '{}'::jsonb then
    perform crm.write_audit(
      new.organization_id, 'organization.profile_updated', 'organization',
      new.organization_id::text,
      jsonb_build_object('before', v_before, 'after', v_after)
    );
  end if;

  if new.require_mfa_for_admins is distinct from old.require_mfa_for_admins then
    perform crm.write_audit(
      new.organization_id, 'organization.mfa_requirement_changed',
      'organization', new.organization_id::text,
      jsonb_build_object('required', new.require_mfa_for_admins)
    );
  end if;

  return null;
end;
$$;

create trigger audit
after insert or update
on crm.organization_profiles
for each row
execute function crm.audit_organization_profiles();

create function crm.audit_organizations() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.name is distinct from old.name then
    perform crm.write_audit(
      new.id, 'organization.profile_updated', 'organization', new.id::text,
      jsonb_build_object(
        'before', jsonb_build_object('name', old.name),
        'after', jsonb_build_object('name', new.name)
      )
    );
  end if;

  return null;
end;
$$;

create trigger crm_audit_organization
after update of name
on public.organizations
for each row
execute function crm.audit_organizations();

-- Members ----------------------------------------------------------------------

-- People only: an agent without user_id is an AI agent, not a membership.
create function crm.audit_agents() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_action text;
begin
  if new.user_id is null then
    return null;
  end if;

  if tg_op = 'INSERT' then
    v_action := 'member.joined';
  elsif old.deleted_at is null and new.deleted_at is not null then
    v_action := 'member.deactivated';
  elsif old.deleted_at is not null and new.deleted_at is null then
    v_action := 'member.reactivated';
  else
    return null;
  end if;

  perform crm.write_audit(
    new.organization_id, v_action, 'member', new.id::text,
    jsonb_build_object('name', new.name)
  );

  return null;
end;
$$;

create trigger crm_audit_membership
after insert or update of deleted_at
on public.agents
for each row
execute function crm.audit_agents();

create function crm.audit_member_roles() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if tg_op = 'INSERT' or new.role_id is distinct from old.role_id then
    perform crm.write_audit(
      new.organization_id, 'member.role_changed', 'member', new.agent_id::text,
      jsonb_build_object(
        'before', case when tg_op = 'UPDATE' then jsonb_build_object(
          'role', (select r.key from crm.roles r where r.id = old.role_id)
        ) end,
        'after', jsonb_build_object(
          'role', (select r.key from crm.roles r where r.id = new.role_id)
        )
      )
    );
  end if;

  if tg_op = 'UPDATE' and new.lead_scope is distinct from old.lead_scope then
    perform crm.write_audit(
      new.organization_id, 'member.lead_scope_changed', 'member',
      new.agent_id::text,
      jsonb_build_object(
        'before', jsonb_build_object('lead_scope', old.lead_scope),
        'after', jsonb_build_object('lead_scope', new.lead_scope)
      )
    );
  end if;

  return null;
end;
$$;

create trigger audit
after insert or update of role_id, lead_scope
on crm.member_roles
for each row
execute function crm.audit_member_roles();

create function crm.audit_member_permission_overrides() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if tg_op = 'DELETE' then
    perform crm.write_audit(
      old.organization_id, 'member.permission_override_removed', 'member',
      old.agent_id::text,
      jsonb_build_object('permission', old.permission)
    );
  elsif tg_op = 'INSERT' or new.granted is distinct from old.granted then
    perform crm.write_audit(
      new.organization_id, 'member.permission_override_set', 'member',
      new.agent_id::text,
      jsonb_build_object('permission', new.permission, 'granted', new.granted)
    );
  end if;

  return null;
end;
$$;

create trigger audit
after insert or update or delete
on crm.member_permission_overrides
for each row
execute function crm.audit_member_permission_overrides();

-- `address` is the organization's own business number or account id, not a
-- contact's.
create function crm.audit_member_address_access() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if tg_op = 'DELETE' then
    perform crm.write_audit(
      old.organization_id, 'member.number_access_revoked', 'member',
      old.agent_id::text,
      jsonb_build_object('service', old.service, 'address', old.address)
    );
  else
    perform crm.write_audit(
      new.organization_id, 'member.number_access_granted', 'member',
      new.agent_id::text,
      jsonb_build_object('service', new.service, 'address', new.address)
    );
  end if;

  return null;
end;
$$;

create trigger audit
after insert or delete
on crm.member_address_access
for each row
execute function crm.audit_member_address_access();

-- Roles ------------------------------------------------------------------------

-- Rows that disappear with their role (a cascade) are not separate events.
create function crm.audit_role_permissions() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if tg_op = 'INSERT' then
    perform crm.write_audit(
      new.organization_id, 'role.permission_granted', 'role', new.role_id::text,
      jsonb_build_object(
        'permission', new.permission,
        'role', (select r.key from crm.roles r where r.id = new.role_id)
      )
    );
  elsif exists (select 1 from crm.roles r where r.id = old.role_id) then
    perform crm.write_audit(
      old.organization_id, 'role.permission_revoked', 'role', old.role_id::text,
      jsonb_build_object(
        'permission', old.permission,
        'role', (select r.key from crm.roles r where r.id = old.role_id)
      )
    );
  end if;

  return null;
end;
$$;

create trigger audit
after insert or delete
on crm.role_permissions
for each row
execute function crm.audit_role_permissions();

-- Invitations ------------------------------------------------------------------

-- Deferred to the end of the transaction: crm.invite_member adds the crm role
-- (crm.invitation_roles) right after the invitation row, and the entry should
-- name it. Invitations made any other way are logged the same, without one.
create function crm.audit_invitation_created() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm.write_audit(
    new.organization_id, 'invitation.created', 'invitation', new.id::text,
    jsonb_strip_nulls(jsonb_build_object(
      'email', new.email,
      'tier', new.role,
      'role', (
        select r.key
        from crm.invitation_roles ir
        join crm.roles r on r.id = ir.role_id
        where ir.invitation_id = new.id
      )
    ))
  );

  return null;
end;
$$;

create constraint trigger crm_audit_invitation_created
after insert
on public.invitations
deferrable initially deferred
for each row
execute function crm.audit_invitation_created();

create function crm.audit_invitation_status() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.status is distinct from old.status
    and new.status in ('accepted', 'rejected', 'revoked') then
    perform crm.write_audit(
      new.organization_id, 'invitation.' || new.status, 'invitation',
      new.id::text,
      jsonb_build_object('email', new.email)
    );
  end if;

  return null;
end;
$$;

create trigger crm_audit_invitation_status
after update of status
on public.invitations
for each row
execute function crm.audit_invitation_status();

-- Packs ------------------------------------------------------------------------

create function crm.audit_organization_packs() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if tg_op = 'INSERT' then
    perform crm.write_audit(
      new.organization_id, 'pack.applied', 'pack', new.pack_key,
      jsonb_build_object('pack', new.pack_key, 'version', new.version)
    );
  elsif new.version is distinct from old.version then
    perform crm.write_audit(
      new.organization_id, 'pack.upgraded', 'pack', new.pack_key,
      jsonb_build_object(
        'pack', new.pack_key,
        'before', jsonb_build_object('version', old.version),
        'after', jsonb_build_object('version', new.version)
      )
    );
  end if;

  return null;
end;
$$;

create trigger audit
after insert or update of version
on crm.organization_packs
for each row
execute function crm.audit_organization_packs();

-- A tenant's own edit. Rows rewritten by a pack upgrade (pack_value changes)
-- are covered by pack.upgraded.
create function crm.audit_organization_pack_items() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.value is not distinct from old.value
    or new.pack_value is distinct from old.pack_value then
    return null;
  end if;

  -- Custom fields (P1-06) have their own actions: edited, archived, restored.
  if new.kind = 'custom_field' then
    perform crm.write_audit(
      new.organization_id,
      case
        when coalesce((new.value->>'archived')::boolean, false)
          and not coalesce((old.value->>'archived')::boolean, false)
          then 'custom_field.archived'
        when coalesce((old.value->>'archived')::boolean, false)
          and not coalesce((new.value->>'archived')::boolean, false)
          then 'custom_field.restored'
        else 'custom_field.updated'
      end,
      'custom_field',
      new.item_key,
      jsonb_build_object('before', old.value, 'after', new.value)
    );
    return null;
  end if;

  perform crm.write_audit(
    new.organization_id,
    case
      when new.value is not distinct from new.pack_value then 'pack.item_reset'
      else 'pack.item_updated'
    end,
    'pack_item',
    new.id::text,
    jsonb_build_object(
      'kind', new.kind,
      'key', new.item_key,
      'before', old.value,
      'after', new.value
    )
  );

  return null;
end;
$$;

create trigger audit
after update of value
on crm.organization_pack_items
for each row
execute function crm.audit_organization_pack_items();
