-- Permission helpers (P1-02). Every crm policy and every crm function that
-- checks authority goes through crm.get_permitted_orgs / crm.has_permission.
--
-- Resolution for a signed-in user, per organization:
--   1. an active membership (agents row, deleted_at null),
--   2. in an ACTIVE organization (not suspended, not pending deletion),
--   3. passing the optional 2FA gate (owner/admin tiers need an aal2 session
--      when the organization requires it),
--   4. the member override for the permission if one exists, else whether
--      the member's role holds it.
--
-- API keys (no auth.uid()) are tier-only until scoped keys arrive (P9-01):
-- a key holds a permission when its tier reaches the permission's min_tier.
-- That keeps every upstream API-key integration working unchanged.

-- Set-returning so a policy can write `organization_id in (select
-- crm.get_permitted_orgs('x'))`, which Postgres evaluates once per query (an
-- InitPlan) instead of once per row.
create function crm.get_permitted_orgs(p_permission text) returns setof uuid
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_min_tier public.role;
begin
  if auth.uid() is not null then
    return query
    select a.organization_id
    from public.agents a
    join crm.member_roles mr on mr.agent_id = a.id
    join crm.roles r on r.id = mr.role_id
    join crm.organization_profiles p on p.organization_id = a.organization_id
    left join crm.member_permission_overrides o
      on o.agent_id = a.id and o.permission = p_permission
    where a.user_id = auth.uid()
      and a.deleted_at is null
      and p.status = 'active'
      and (
        not p.require_mfa_for_admins
        or r.tier = 'member'
        or coalesce(auth.jwt()->>'aal', 'aal1') = 'aal2'
      )
      and coalesce(
        o.granted,
        exists (
          select 1 from crm.role_permissions rp
          where rp.role_id = mr.role_id and rp.permission = p_permission
        )
      );
    return;
  end if;

  select pm.min_tier into v_min_tier
  from crm.permissions pm
  where pm.key = p_permission;

  if not found then
    return;
  end if;

  -- Raises 'authentication required' when there is no key either, exactly as
  -- the upstream policies do for the same request.
  return query select public.get_authorized_orgs(v_min_tier);
end;
$$;

create function crm.has_permission(p_organization_id uuid, p_permission text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select p_organization_id in (select crm.get_permitted_orgs(p_permission));
$$;

-- The caller's effective permissions in one organization — what the UI uses
-- to show or hide actions. The database stays the enforcer.
create function crm.my_permissions(p_organization_id uuid) returns setof text
language sql
stable
security definer
set search_path to ''
as $$
  select pm.key
  from crm.permissions pm
  where crm.has_permission(p_organization_id, pm.key)
  order by pm.sort_order, pm.key;
$$;

-- Connected accounts the caller may NOT see because of their number-access
-- scope (crm.member_address_access). Members without any rows see
-- everything, so this is empty for them and for API keys. A member's own
-- personal account is never hidden from them.
create function crm.get_hidden_addresses()
returns table (organization_id uuid, service public.service, address text)
language sql
stable
security definer
set search_path to ''
as $$
  select oa.organization_id, oa.service, oa.address
  from public.agents a
  join public.organizations_addresses oa
    on oa.organization_id = a.organization_id
  where a.user_id = auth.uid()
    and a.deleted_at is null
    and oa.service <> 'local'
    and oa.agent_id is distinct from a.id
    and exists (
      select 1 from crm.member_address_access m where m.agent_id = a.id
    )
    and not exists (
      select 1 from crm.member_address_access m
      where m.agent_id = a.id
        and m.service = oa.service
        and m.address = oa.address
    );
$$;

-- Whether the caller would hold organization.manage-tier access in this org
-- if they verified a TOTP code right now (P1-11). crm.get_permitted_orgs
-- silently drops an org when aal2 is required but missing — indistinguishable
-- from "you don't have this role at all" — so the UI calls this separately
-- to decide between a generic "no permission" state and a 2FA step-up
-- prompt. Read-only, no write path; mirrors get_permitted_orgs' own aal2
-- condition exactly, just inverted and scoped to one org/caller.
create function crm.needs_mfa_step_up(p_organization_id uuid) returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select exists (
    select 1
    from public.agents a
    join crm.member_roles mr on mr.agent_id = a.id
    join crm.roles r on r.id = mr.role_id
    join crm.organization_profiles p on p.organization_id = a.organization_id
    where a.organization_id = p_organization_id
      and a.user_id = auth.uid()
      and a.deleted_at is null
      and p.status = 'active'
      and p.require_mfa_for_admins
      and r.tier <> 'member'
      and coalesce(auth.jwt()->>'aal', 'aal1') <> 'aal2'
  );
$$;

-- The caller's active, non-deleted agent row in an organization, or null.
create function crm.caller_agent(p_organization_id uuid) returns public.agents
language sql
stable
security definer
set search_path to ''
as $$
  select a.* from public.agents a
  where a.organization_id = p_organization_id
    and a.user_id = auth.uid()
    and a.deleted_at is null;
$$;

create function crm.require_permission(
  p_organization_id uuid,
  p_permission text
) returns void
language plpgsql
stable
security definer
set search_path to ''
as $$
begin
  if p_organization_id is null
    or not crm.has_permission(p_organization_id, p_permission) then
    raise exception 'permission % required', p_permission
      using errcode = '42501';
  end if;
end;
$$;
