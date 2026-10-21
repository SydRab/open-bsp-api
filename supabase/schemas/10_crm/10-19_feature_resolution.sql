-- Feature resolution (P1-09). Table: 10-18.
--
-- Whether an organization has a feature: the platform kill switch beats a
-- per-organization override, which beats the tier the organization is
-- subscribed to (billing.subscriptions.tier_id). No subscription at all =
-- no billing = every feature is available, the same fallback
-- billing.check_limit already uses for usage caps.

create function crm.has_feature(p_organization_id uuid, p_feature_key text)
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_kill_switch boolean;
  v_override boolean;
  v_tier_id text;
begin
  -- Same access rule as crm.get_setting: a signed-in caller must belong to
  -- the organization, so this cannot be used to probe another tenant's plan.
  perform crm.assert_can_read_settings(p_organization_id);

  select f.kill_switch into v_kill_switch
  from crm.features f
  where f.key = p_feature_key;
  if not found then
    raise exception 'unknown feature %', p_feature_key using errcode = '22023';
  end if;
  if v_kill_switch then
    return false;
  end if;

  select o.enabled into v_override
  from crm.organization_features o
  where o.organization_id = p_organization_id
    and o.feature_key = p_feature_key
    and (o.expires_at is null or o.expires_at > now());
  if found then
    return v_override;
  end if;

  select s.tier_id into v_tier_id
  from billing.subscriptions s
  where s.organization_id = p_organization_id;
  if not found then
    return true;
  end if;

  return exists (
    select 1 from crm.tier_features tf
    where tf.tier_id = v_tier_id and tf.feature_key = p_feature_key
  );
end;
$$;

create function crm.require_feature(p_organization_id uuid, p_feature_key text)
returns void
language plpgsql
stable
security definer
set search_path to ''
as $$
begin
  if not crm.has_feature(p_organization_id, p_feature_key) then
    raise exception 'your plan does not include %', (
      select f.label from crm.features f where f.key = p_feature_key
    ) using errcode = '42501';
  end if;
end;
$$;

-- Every feature with its effective value for the caller's organization, why
-- (kill_switch | override | tier | unrestricted), and — when not enabled —
-- the lowest tier that would include it. Feeds Settings → Plan & features
-- and the locked module switches on Rules & modules.
create function crm.get_features(p_organization_id uuid)
returns table (
  key text,
  category text,
  label text,
  description text,
  enabled boolean,
  source text,
  override_reason text,
  override_expires_at timestamp with time zone,
  unlocks_at_tier text
)
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_tier_id text;
begin
  perform crm.assert_can_read_settings(p_organization_id);

  select s.tier_id into v_tier_id
  from billing.subscriptions s
  where s.organization_id = p_organization_id;

  return query
  select
    f.key, f.category, f.label, f.description,
    crm.has_feature(p_organization_id, f.key),
    case
      when f.kill_switch then 'kill_switch'
      when o.feature_key is not null then 'override'
      when v_tier_id is null then 'unrestricted'
      else 'tier'
    end,
    o.reason,
    o.expires_at,
    (
      select tf.tier_id from crm.tier_features tf
      join billing.tiers t on t.id = tf.tier_id
      where tf.feature_key = f.key
      order by t.level asc
      limit 1
    )
  from crm.features f
  left join crm.organization_features o
    on o.organization_id = p_organization_id
   and o.feature_key = f.key
   and (o.expires_at is null or o.expires_at > now())
  order by f.sort_order, f.key;
end;
$$;

-- Platform only (service_role; the super-admin console, P1-10, calls it).
-- Overrides a feature for one organization: a beta, a comp, a block.
-- expires_at is optional; once past, the tier default applies again.
create function crm.set_organization_feature(
  p_organization_id uuid,
  p_feature_key text,
  p_enabled boolean,
  p_reason text default null,
  p_expires_at timestamp with time zone default null
) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'only the platform can override features'
      using errcode = '42501';
  end if;

  if not exists (select 1 from crm.features f where f.key = p_feature_key) then
    raise exception 'unknown feature %', p_feature_key using errcode = '22023';
  end if;

  insert into crm.organization_features (
    organization_id, feature_key, enabled, reason, expires_at
  ) values (
    p_organization_id, p_feature_key, p_enabled, p_reason, p_expires_at
  )
  on conflict (organization_id, feature_key) do update
    set enabled = excluded.enabled,
        reason = excluded.reason,
        expires_at = excluded.expires_at,
        updated_at = now();
end;
$$;

-- Removes an organization's override; the tier default applies again.
create function crm.clear_organization_feature(
  p_organization_id uuid,
  p_feature_key text
) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'only the platform can override features'
      using errcode = '42501';
  end if;

  delete from crm.organization_features
  where organization_id = p_organization_id and feature_key = p_feature_key;
end;
$$;

-- Platform only. An emergency off switch for everyone, regardless of plan or
-- override. Not organization-scoped, so it is not written to the (per
-- organization) audit log; crm.features.updated_at is its record.
create function crm.set_feature_kill_switch(p_feature_key text, p_enabled boolean)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'only the platform can use the kill switch'
      using errcode = '42501';
  end if;

  update crm.features set kill_switch = p_enabled where key = p_feature_key;
  if not found then
    raise exception 'unknown feature %', p_feature_key using errcode = '22023';
  end if;
end;
$$;
