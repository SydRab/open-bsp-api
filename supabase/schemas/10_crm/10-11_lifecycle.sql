-- Tenant lifecycle (P1-01): slug, creation hook, suspend/reactivate (platform),
-- soft delete with a grace period and cancel (owner), hard delete (platform).

-- How long a deletion request waits before the organization is purged.
create function crm.deletion_grace_period() returns interval
language sql
immutable
set search_path to ''
as $$
  select interval '30 days';
$$;

-- A unique slug derived from the name: lowercase ASCII letters and digits
-- joined by hyphens. Names with no ASCII letters (e.g. Devanagari) fall back
-- to 'org'. A random suffix resolves collisions.
create function crm.generate_slug(p_name text) returns text
language plpgsql
volatile
security definer
set search_path to ''
as $$
declare
  v_base text;
  v_slug text;
begin
  v_base := regexp_replace(lower(coalesce(p_name, '')), '[^a-z0-9]+', '-', 'g');
  v_base := trim(both '-' from left(trim(both '-' from v_base), 40));

  if length(v_base) < 3 then
    v_base := 'org';
  end if;

  v_slug := v_base;

  while exists (
    select 1 from crm.organization_profiles where slug = v_slug
  ) loop
    v_slug := v_base || '-' || substr(md5(gen_random_uuid()::text), 1, 6);
  end loop;

  return v_slug;
end;
$$;

-- The eight preset roles, copied into one organization with their default
-- permissions. The owner role is locked and holds every permission.
create function crm.create_preset_roles(p_organization_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  insert into crm.roles (
    organization_id, key, name, description, tier, lead_scope, is_preset,
    is_locked, sort_order
  )
  select
    p_organization_id, pr.key, pr.name, pr.description, pr.tier,
    pr.lead_scope, true, pr.key = 'owner', pr.sort_order
  from crm.preset_roles pr
  on conflict (organization_id, key) do nothing;

  insert into crm.role_permissions (organization_id, role_id, permission)
  select r.organization_id, r.id, prp.permission
  from crm.roles r
  join crm.preset_role_permissions prp on prp.role_key = r.key
  where r.organization_id = p_organization_id
    and r.key <> 'owner'
  on conflict do nothing;

  insert into crm.role_permissions (organization_id, role_id, permission)
  select r.organization_id, r.id, pm.key
  from crm.roles r
  cross join crm.permissions pm
  where r.organization_id = p_organization_id
    and r.key = 'owner'
  on conflict do nothing;
end;
$$;

-- Members of an organization that is not active cannot see it through any
-- API (get_authorized_orgs filters it out), so the UI asks here to explain
-- why: the suspended banner and the pending-deletion banner.
create function crm.get_my_organization_statuses()
returns table (
  organization_id uuid,
  name text,
  status text,
  suspended_reason text,
  purge_after timestamp with time zone,
  can_cancel_deletion boolean
)
language sql
stable
security definer
set search_path to ''
as $$
  select
    o.id,
    o.name,
    p.status,
    p.suspended_reason,
    p.purge_after,
    p.status = 'pending_deletion' and a.role = 'owner'
  from public.agents a
  join public.organizations o on o.id = a.organization_id
  join crm.organization_profiles p on p.organization_id = o.id
  where a.user_id = auth.uid()
    and a.deleted_at is null
    and p.status <> 'active'
  order by o.name;
$$;

-- Platform only (service_role; the super-admin console in P1-10 calls it).
create function crm.suspend_organization(
  p_organization_id uuid,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  update crm.organization_profiles
  set status = 'suspended',
      suspended_at = now(),
      suspended_reason = p_reason
  where organization_id = p_organization_id
    and status = 'active';

  if not found then
    raise exception 'organization is not active'
      using errcode = '22023';
  end if;
end;
$$;

-- Platform only.
create function crm.reactivate_organization(p_organization_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  update crm.organization_profiles
  set status = 'active',
      suspended_at = null,
      suspended_reason = null
  where organization_id = p_organization_id
    and status = 'suspended';

  if not found then
    raise exception 'organization is not suspended'
      using errcode = '22023';
  end if;
end;
$$;

-- Soft delete, by a member holding organization.delete (owners, by default).
-- Access stops at once; the data is purged after the grace period.
create function crm.request_organization_deletion(p_organization_id uuid)
returns timestamp with time zone
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_purge_after timestamp with time zone := now() + crm.deletion_grace_period();
begin
  perform crm.require_permission(p_organization_id, 'organization.delete');

  update crm.organization_profiles
  set status = 'pending_deletion',
      deletion_requested_at = now(),
      deletion_requested_by = (crm.caller_agent(p_organization_id)).id,
      purge_after = v_purge_after
  where organization_id = p_organization_id
    and status = 'active';

  return v_purge_after;
end;
$$;

-- Any owner may cancel during the grace period. Checked on the tier directly:
-- permissions resolve to nothing while the organization is not active.
create function crm.cancel_organization_deletion(p_organization_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if (crm.caller_agent(p_organization_id)).role is distinct from 'owner' then
    raise exception 'only an owner can cancel the deletion'
      using errcode = '42501';
  end if;

  update crm.organization_profiles
  set status = 'active',
      deletion_requested_at = null,
      deletion_requested_by = null,
      purge_after = null
  where organization_id = p_organization_id
    and status = 'pending_deletion';

  if not found then
    raise exception 'organization is not pending deletion'
      using errcode = '22023';
  end if;
end;
$$;

-- Platform only: hard-deletes every organization whose grace period has
-- passed. Upstream foreign keys cascade from public.organizations.
create function crm.purge_organizations() returns int
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_count int;
begin
  delete from public.organizations o
  using crm.organization_profiles p
  where p.organization_id = o.id
    and p.status = 'pending_deletion'
    and p.purge_after <= now();

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Optional 2FA gate for owner/admin tiers. Turning it on requires the caller
-- to be on an aal2 session themselves, so nobody can lock themselves out.
create function crm.set_require_mfa_for_admins(
  p_organization_id uuid,
  p_required boolean
) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(p_organization_id, 'organization.manage');

  if p_required and coalesce(auth.jwt()->>'aal', 'aal1') <> 'aal2' then
    raise exception 'enable two-factor authentication on your own account first'
      using errcode = '42501';
  end if;

  update crm.organization_profiles
  set require_mfa_for_admins = p_required
  where organization_id = p_organization_id;
end;
$$;
