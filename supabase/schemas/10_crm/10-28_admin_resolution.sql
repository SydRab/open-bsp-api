-- Super-admin console functions (P1-10). Table: 10-27. Triggers: 10-29.
--
-- Two kinds of function here:
--   * read-only (list_tenants, list_platform_admins, get_support_access,
--     get_platform_audit_log) trust the caller wholesale, like
--     crm.purge_organizations already does — they are reachable only by
--     service_role (10-40's blanket grant gives authenticated/anon nothing),
--     and the crm-admin edge function is what checked crm.is_platform_admin
--     before ever calling them.
--   * mutating functions additionally take the acting admin's id explicitly
--     (service-role calls carry no auth.uid()) and re-check it is a real
--     platform admin — defense in depth against an edge-function bug, and
--     it is what attributes the action in both audit logs.
--
-- Functions normally gated by crm.require_permission (tenant permissions)
-- cannot simply be called as bare service_role: crm.require_permission →
-- crm.get_permitted_orgs falls through to public.get_authorized_orgs, which
-- raises "authentication required" when there is neither a JWT nor an
-- api-key header — confirmed by hand. crm.admin_upgrade_organization_pack
-- and crm.set_organization_tier below are thin admin-gated replacements for
-- the two tenant-facing actions this console needs
-- (crm.upgrade_organization_pack, a raw billing.subscriptions update).
-- crm.get_settings has the SAME problem one level down: its own top-level
-- gate (assert_can_read_settings) bypasses for service_role, but it also
-- computes `can_edit` per row via crm.has_permission, which has no such
-- bypass — confirmed by hand too. crm.admin_get_tenant_config below reads
-- crm.resolve_setting directly instead (no permission check at all; the
-- gating crm.get_setting/get_settings add on top is exactly the
-- organization.manage check this admin snapshot has no business asking for).
-- crm.get_features / crm.apply_pack have no such gate
-- (crm.has_feature's assert_can_read_settings bypasses for service_role, and
-- apply_pack has no permission check at all — it runs for brand-new
-- organizations too), so crm.admin_get_tenant_config calls them directly.

-- Self-check only: an authenticated (or anon/api-key) caller may ask about
-- themselves, not enumerate anyone else's admin status. service_role may
-- pass any id (the edge function checks the real caller before acting on
-- their behalf).
create function crm.is_platform_admin(p_user_id uuid default auth.uid())
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $$
begin
  if auth.role() <> 'service_role' and p_user_id is distinct from auth.uid() then
    raise exception 'can only check your own admin status' using errcode = '42501';
  end if;

  return p_user_id is not null
    and exists (select 1 from crm.platform_admins a where a.user_id = p_user_id);
end;
$$;

create function crm.require_platform_admin(p_admin_id uuid) returns void
language plpgsql
stable
security definer
set search_path to ''
as $$
begin
  if p_admin_id is null
    or not exists (select 1 from crm.platform_admins a where a.user_id = p_admin_id) then
    raise exception 'only platform admins can do this' using errcode = '42501';
  end if;
end;
$$;

create function crm.write_platform_audit(
  p_admin_id uuid,
  p_action text,
  p_target_type text default null,
  p_target_id text default null,
  p_details jsonb default '{}'::jsonb
) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  insert into crm.platform_audit_log (actor_user_id, action, target_type, target_id, details)
  values (p_admin_id, p_action, p_target_type, p_target_id, coalesce(p_details, '{}'::jsonb));
end;
$$;

-- Admins ------------------------------------------------------------------------

create function crm.list_platform_admins()
returns table (
  user_id uuid, email text, granted_at timestamp with time zone,
  granted_by uuid, granted_by_email text
)
language sql
stable
security definer
set search_path to ''
as $$
  select a.user_id, u.email, a.granted_at, a.granted_by, gu.email
  from crm.platform_admins a
  join auth.users u on u.id = a.user_id
  left join auth.users gu on gu.id = a.granted_by
  order by a.granted_at;
$$;

create function crm.grant_platform_admin(p_email text, p_granted_by uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_user_id uuid;
begin
  perform crm.require_platform_admin(p_granted_by);

  select id into v_user_id from auth.users where lower(email) = lower(trim(p_email));
  if v_user_id is null then
    raise exception 'no user with that email' using errcode = 'P0002';
  end if;

  insert into crm.platform_admins (user_id, granted_by)
  values (v_user_id, p_granted_by)
  on conflict (user_id) do nothing;

  perform crm.write_platform_audit(
    p_granted_by, 'platform_admin.granted', 'user', v_user_id::text,
    jsonb_build_object('email', lower(trim(p_email)))
  );
end;
$$;

create function crm.revoke_platform_admin(p_user_id uuid, p_revoked_by uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_count int;
begin
  perform crm.require_platform_admin(p_revoked_by);

  select count(*) into v_count from crm.platform_admins;
  if v_count <= 1 and exists (
    select 1 from crm.platform_admins where user_id = p_user_id
  ) then
    raise exception 'cannot remove the last platform admin' using errcode = '22023';
  end if;

  delete from crm.platform_admins where user_id = p_user_id;
  if found then
    perform crm.write_platform_audit(p_revoked_by, 'platform_admin.revoked', 'user', p_user_id::text);
  end if;
end;
$$;

-- Tenants -------------------------------------------------------------------------

create function crm.list_tenants(p_search text default null)
returns table (
  organization_id uuid,
  name text,
  slug text,
  status text,
  tier_id text,
  tier_name text,
  seats_used numeric,
  seats_cap numeric,
  pack_key text,
  pack_version int,
  latest_pack_version int,
  created_at timestamp with time zone
)
language sql
stable
security definer
set search_path to ''
as $$
  select
    o.id, o.name, p.slug, p.status,
    s.tier_id, t.name,
    coalesce(u.quantity, 0), tp.cap,
    op.pack_key, op.version,
    (select max(pv.version) from crm.pack_versions pv where pv.pack_key = op.pack_key),
    o.created_at
  from public.organizations o
  join crm.organization_profiles p on p.organization_id = o.id
  left join billing.subscriptions s on s.organization_id = o.id
  left join billing.tiers t on t.id = s.tier_id
  left join billing.usage u
    on u.organization_id = o.id and u.product_id = 'members' and u.interval = 'lifetime'
  left join billing.tiers_products tp
    on tp.tier_id = s.tier_id and tp.product_id = 'members'
  left join crm.organization_packs op on op.organization_id = o.id
  where p_search is null
    or o.name ilike '%' || p_search || '%'
    or p.slug ilike '%' || p_search || '%'
  order by o.created_at desc;
$$;

create function crm.set_organization_tier(
  p_organization_id uuid,
  p_tier_id text,
  p_admin_id uuid
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_before text;
begin
  perform crm.require_platform_admin(p_admin_id);

  if not exists (select 1 from billing.tiers t where t.id = p_tier_id and t.active) then
    raise exception 'unknown or inactive tier %', p_tier_id using errcode = '22023';
  end if;

  select tier_id into v_before from billing.subscriptions where organization_id = p_organization_id;

  if v_before is null then
    insert into billing.subscriptions (organization_id, tier_id)
    values (p_organization_id, p_tier_id);
  else
    update billing.subscriptions set tier_id = p_tier_id where organization_id = p_organization_id;
  end if;

  perform crm.write_platform_audit(
    p_admin_id, 'organization.tier_changed', 'organization', p_organization_id::text,
    jsonb_build_object('before', v_before, 'after', p_tier_id)
  );
  perform crm.write_audit(
    p_organization_id, 'organization.tier_changed', 'organization', p_organization_id::text,
    jsonb_build_object('before', v_before, 'after', p_tier_id)
  );
end;
$$;

-- crm.upgrade_organization_pack without the tenant organization.manage
-- check (see the file comment); otherwise identical, so the pack_item table
-- change still fires crm.audit_organization_packs (10-21) as normal.
create function crm.admin_upgrade_organization_pack(
  p_organization_id uuid,
  p_version int,
  p_admin_id uuid
) returns int
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_current crm.organization_packs;
  v_target int;
begin
  perform crm.require_platform_admin(p_admin_id);

  select * into v_current
  from crm.organization_packs
  where organization_id = p_organization_id;

  if not found then
    raise exception 'organization has no pack' using errcode = 'P0002';
  end if;

  v_target := coalesce(
    p_version,
    (select max(version) from crm.pack_versions where pack_key = v_current.pack_key)
  );

  perform crm.apply_pack(p_organization_id, v_current.pack_key, v_target);

  perform crm.write_platform_audit(
    p_admin_id, 'organization.pack_upgraded', 'organization', p_organization_id::text,
    jsonb_build_object('pack', v_current.pack_key, 'version', v_target)
  );

  return v_target;
end;
$$;

-- Support access -------------------------------------------------------------------

create function crm.has_active_support_access(p_organization_id uuid, p_admin_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select exists (
    select 1 from crm.support_access_grants g
    where g.organization_id = p_organization_id
      and g.admin_id = p_admin_id
      and g.revoked_at is null
      and g.expires_at > now()
  );
$$;

-- p_hours is capped at a week: "time-limited" is the point of this grant.
create function crm.grant_support_access(
  p_organization_id uuid,
  p_admin_id uuid,
  p_reason text,
  p_hours int default 24
) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_id uuid;
begin
  perform crm.require_platform_admin(p_admin_id);

  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'a reason is required' using errcode = '22023';
  end if;
  if p_hours is null or p_hours < 1 or p_hours > 168 then
    raise exception 'hours must be between 1 and 168 (one week)' using errcode = '22023';
  end if;
  if not exists (select 1 from public.organizations o where o.id = p_organization_id) then
    raise exception 'organization not found' using errcode = 'P0002';
  end if;

  insert into crm.support_access_grants (organization_id, admin_id, reason, expires_at)
  values (p_organization_id, p_admin_id, trim(p_reason), now() + make_interval(hours => p_hours))
  returning id into v_id;

  perform crm.write_platform_audit(
    p_admin_id, 'support_access.granted', 'organization', p_organization_id::text,
    jsonb_build_object('reason', trim(p_reason), 'hours', p_hours)
  );

  return v_id;
end;
$$;

create function crm.revoke_support_access(p_grant_id uuid, p_admin_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_org uuid;
begin
  perform crm.require_platform_admin(p_admin_id);

  update crm.support_access_grants
  set revoked_at = now()
  where id = p_grant_id and revoked_at is null
  returning organization_id into v_org;

  if not found then
    raise exception 'grant not found or already revoked' using errcode = 'P0002';
  end if;

  perform crm.write_platform_audit(p_admin_id, 'support_access.revoked', 'organization', v_org::text);
end;
$$;

create function crm.get_support_access(p_organization_id uuid default null)
returns table (
  id uuid,
  organization_id uuid,
  organization_name text,
  admin_id uuid,
  admin_email text,
  reason text,
  granted_at timestamp with time zone,
  expires_at timestamp with time zone,
  revoked_at timestamp with time zone,
  active boolean
)
language sql
stable
security definer
set search_path to ''
as $$
  select
    g.id, g.organization_id, o.name, g.admin_id, u.email, g.reason,
    g.granted_at, g.expires_at, g.revoked_at,
    g.revoked_at is null and g.expires_at > now()
  from crm.support_access_grants g
  join public.organizations o on o.id = g.organization_id
  join auth.users u on u.id = g.admin_id
  where p_organization_id is null or g.organization_id = p_organization_id
  order by g.granted_at desc;
$$;

-- Reading a tenant's configuration -------------------------------------------------

-- Settings and features, not message or contact content — see the file
-- comment for why crm.get_settings/get_features are safe to call directly.
create function crm.admin_get_tenant_config(p_organization_id uuid, p_admin_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
begin
  perform crm.require_platform_admin(p_admin_id);
  if not crm.has_active_support_access(p_organization_id, p_admin_id) then
    raise exception 'no active support-access grant for this organization'
      using errcode = '42501';
  end if;

  return jsonb_build_object(
    'profile', (
      select to_jsonb(p) from crm.organization_profiles p
      where p.organization_id = p_organization_id
    ),
    'roles', (
      select jsonb_agg(jsonb_build_object(
        'key', r.key, 'name', r.name,
        'permissions', (
          select jsonb_agg(rp.permission) from crm.role_permissions rp
          where rp.role_id = r.id
        )
      ))
      from crm.roles r where r.organization_id = p_organization_id
    ),
    'settings', (
      select jsonb_agg(jsonb_build_object(
        'key', d.key, 'category', d.category, 'label', d.label,
        'value', r.value, 'source', r.source, 'is_locked', d.is_locked
      ))
      from crm.setting_definitions d
      cross join lateral crm.resolve_setting(p_organization_id, d.key) r
    ),
    'features', (
      select jsonb_agg(to_jsonb(f)) from crm.get_features(p_organization_id) f
    ),
    'pack_items', (
      select jsonb_agg(jsonb_build_object(
        'kind', i.kind, 'key', i.item_key, 'value', i.value, 'customized', i.is_customized
      ))
      from crm.organization_pack_items i where i.organization_id = p_organization_id
    )
  );
end;
$$;

-- Same shape as crm.get_audit_log, gated by a support-access grant instead
-- of the tenant's own audit.view permission (which the admin does not and
-- should not hold) — kept as its own query rather than reusing
-- get_audit_log, whose own crm.require_permission would reject a bare
-- service-role caller (see the file comment).
create function crm.admin_get_audit_log(
  p_organization_id uuid,
  p_admin_id uuid,
  p_before_id bigint default null,
  p_limit int default 50
) returns table (
  id bigint,
  created_at timestamp with time zone,
  actor_type text,
  actor_agent_id uuid,
  actor_name text,
  action text,
  target_type text,
  target_id text,
  target_name text,
  details jsonb
)
language plpgsql
stable
security definer
set search_path to ''
as $$
begin
  perform crm.require_platform_admin(p_admin_id);
  if not crm.has_active_support_access(p_organization_id, p_admin_id) then
    raise exception 'no active support-access grant for this organization'
      using errcode = '42501';
  end if;

  return query
  select
    l.id, l.created_at, l.actor_type, l.actor_agent_id,
    coalesce(actor.name, ak.name), l.action, l.target_type, l.target_id,
    coalesce(member.name, r.name), l.details
  from crm.audit_log l
  left join public.agents actor on actor.id = l.actor_agent_id
  left join public.api_keys ak on ak.id = l.actor_api_key_id
  left join public.agents member
    on l.target_type = 'member'
   and member.organization_id = l.organization_id
   and member.id::text = l.target_id
  left join crm.roles r
    on l.target_type = 'role'
   and r.organization_id = l.organization_id
   and r.id::text = l.target_id
  where l.organization_id = p_organization_id
    and (p_before_id is null or l.id < p_before_id)
  order by l.id desc
  limit least(greatest(coalesce(p_limit, 50), 1), 200);
end;
$$;

create function crm.get_platform_audit_log(
  p_before_id bigint default null,
  p_limit int default 50
) returns table (
  id bigint,
  created_at timestamp with time zone,
  actor_email text,
  action text,
  target_type text,
  target_id text,
  details jsonb
)
language sql
stable
security definer
set search_path to ''
as $$
  select l.id, l.created_at, u.email, l.action, l.target_type, l.target_id, l.details
  from crm.platform_audit_log l
  join auth.users u on u.id = l.actor_user_id
  where p_before_id is null or l.id < p_before_id
  order by l.id desc
  limit least(greatest(coalesce(p_limit, 50), 1), 200);
$$;
