-- Settings engine and teams (P1-04). Tables: 10-06, 10-07. Triggers: 10-22.

-- Checks a value against a setting's schema, a JSON Schema subset:
--   type (boolean | integer | number | string | array | object), enum,
--   minimum / maximum, minLength / maxLength, pattern, minItems / maxItems,
--   items, properties, required, additionalProperties (false only), and our
--   own mustContain: array items that must be present (case-insensitive),
--   which is how compliance minimums like STOP are kept in a list.
-- Returns null when the value is valid, else a message for the user.
create function crm.validate_setting_value(
  p_schema jsonb,
  p_value jsonb,
  p_path text default 'value'
) returns text
language plpgsql
immutable
set search_path to ''
as $$
declare
  v_type text := p_schema->>'type';
  v_actual text := jsonb_typeof(p_value);
  v_number numeric;
  v_text text;
  v_error text;
  v_key text;
  v_item jsonb;
  v_index int := 0;
begin
  if p_value is null or v_actual = 'null' then
    return format('%s is required', p_path);
  end if;

  if v_type = 'integer' then
    if v_actual <> 'number'
      or (p_value #>> '{}')::numeric <> trunc((p_value #>> '{}')::numeric) then
      return format('%s must be a whole number', p_path);
    end if;
  elsif v_type is not null and v_type <> v_actual then
    return format('%s must be a %s', p_path, v_type);
  end if;

  if p_schema ? 'enum'
    and not (p_schema->'enum') @> jsonb_build_array(p_value) then
    return format('%s is not one of the allowed values', p_path);
  end if;

  if v_actual = 'number' then
    v_number := (p_value #>> '{}')::numeric;
    if p_schema ? 'minimum' and v_number < (p_schema->>'minimum')::numeric then
      return format('%s must be at least %s', p_path, p_schema->>'minimum');
    end if;
    if p_schema ? 'maximum' and v_number > (p_schema->>'maximum')::numeric then
      return format('%s must be at most %s', p_path, p_schema->>'maximum');
    end if;
  end if;

  if v_actual = 'string' then
    v_text := p_value #>> '{}';
    if p_schema ? 'minLength' and length(v_text) < (p_schema->>'minLength')::int then
      return format('%s must have at least %s characters', p_path, p_schema->>'minLength');
    end if;
    if p_schema ? 'maxLength' and length(v_text) > (p_schema->>'maxLength')::int then
      return format('%s must have at most %s characters', p_path, p_schema->>'maxLength');
    end if;
    if p_schema ? 'pattern' and v_text !~ (p_schema->>'pattern') then
      return format('%s has the wrong format', p_path);
    end if;
  end if;

  if v_actual = 'array' then
    if p_schema ? 'minItems'
      and jsonb_array_length(p_value) < (p_schema->>'minItems')::int then
      return format('%s must have at least %s items', p_path, p_schema->>'minItems');
    end if;
    if p_schema ? 'maxItems'
      and jsonb_array_length(p_value) > (p_schema->>'maxItems')::int then
      return format('%s must have at most %s items', p_path, p_schema->>'maxItems');
    end if;
    if p_schema ? 'items' then
      for v_item in select * from jsonb_array_elements(p_value) loop
        v_error := crm.validate_setting_value(
          p_schema->'items', v_item, format('%s[%s]', p_path, v_index)
        );
        if v_error is not null then
          return v_error;
        end if;
        v_index := v_index + 1;
      end loop;
    end if;
    if p_schema ? 'mustContain' then
      for v_item in select * from jsonb_array_elements(p_schema->'mustContain') loop
        if not exists (
          select 1 from jsonb_array_elements(p_value) e
          where upper(e #>> '{}') = upper(v_item #>> '{}')
        ) then
          return format('%s must include %s', p_path, v_item #>> '{}');
        end if;
      end loop;
    end if;
  end if;

  if v_actual = 'object' then
    if p_schema ? 'required' then
      for v_key in select * from jsonb_array_elements_text(p_schema->'required') loop
        if not p_value ? v_key then
          return format('%s.%s is required', p_path, v_key);
        end if;
      end loop;
    end if;
    for v_key, v_item in select * from jsonb_each(p_value) loop
      if p_schema->'properties' ? v_key then
        v_error := crm.validate_setting_value(
          p_schema->'properties'->v_key, v_item, format('%s.%s', p_path, v_key)
        );
        if v_error is not null then
          return v_error;
        end if;
      elsif p_schema->'additionalProperties' = 'false'::jsonb then
        return format('%s.%s is not allowed', p_path, v_key);
      end if;
    end loop;
  end if;

  return null;
end;
$$;

-- The effective value of one setting for one organization (and member, for
-- the team and user layers), with the layer it came from. Internal: callers
-- go through get_setting / get_settings, which check access.
--
-- team_conflict: the member is in several teams that set different values.
-- The team layer is then skipped (the organization value applies) and the
-- admin screen flags it.
create function crm.resolve_setting(
  p_organization_id uuid,
  p_key text,
  p_agent_id uuid default null
) returns table (value jsonb, source text, team_conflict boolean)
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_def crm.setting_definitions;
  v_value jsonb;
  v_team_values int;
  v_conflict boolean := false;
begin
  select * into v_def from crm.setting_definitions d where d.key = p_key;
  if not found then
    raise exception 'unknown setting %', p_key using errcode = '22023';
  end if;

  if v_def.is_locked then
    return query select v_def.platform_default, 'platform'::text, false;
    return;
  end if;

  if p_agent_id is not null and 'user' = any(v_def.scopes) then
    select sv.value into v_value
    from crm.setting_values sv
    where sv.organization_id = p_organization_id
      and sv.setting_key = p_key
      and sv.scope = 'user'
      and sv.agent_id = p_agent_id;
    if found then
      return query select v_value, 'user'::text, false;
      return;
    end if;
  end if;

  if p_agent_id is not null and 'team' = any(v_def.scopes) then
    select count(distinct sv.value), min(sv.value::text)::jsonb
    into v_team_values, v_value
    from crm.team_members tm
    join crm.setting_values sv
      on sv.team_id = tm.team_id
     and sv.setting_key = p_key
     and sv.scope = 'team'
    where tm.organization_id = p_organization_id
      and tm.agent_id = p_agent_id;

    if v_team_values = 1 then
      return query select v_value, 'team'::text, false;
      return;
    end if;
    v_conflict := v_team_values > 1;
  end if;

  select sv.value into v_value
  from crm.setting_values sv
  where sv.organization_id = p_organization_id
    and sv.setting_key = p_key
    and sv.scope = 'tenant';
  if found then
    return query select v_value, 'tenant'::text, v_conflict;
    return;
  end if;

  if v_def.pack_item_kind is not null then
    select i.pack_value #> v_def.pack_item_path into v_value
    from crm.organization_pack_items i
    where i.organization_id = p_organization_id
      and i.kind = v_def.pack_item_kind
      and i.item_key = v_def.pack_item_key;
    -- A pack value that breaks the schema (or a platform minimum) is ignored.
    if v_value is not null
      and crm.validate_setting_value(v_def.schema, v_value) is null then
      return query select v_value, 'pack'::text, v_conflict;
      return;
    end if;
  end if;

  return query select v_def.platform_default, 'platform'::text, v_conflict;
end;
$$;

-- Members and API keys of an active organization; the platform for any.
-- Returns the caller's agent in the organization (null for keys and the
-- platform).
create function crm.assert_can_read_settings(p_organization_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path to ''
as $$
begin
  if auth.role() = 'service_role' then
    return null;
  end if;

  if p_organization_id is null
    or p_organization_id not in (select public.get_authorized_orgs('member')) then
    raise exception 'organization not found' using errcode = '42501';
  end if;

  return (crm.caller_agent(p_organization_id)).id;
end;
$$;

-- One setting's effective value. The send path and other features call
-- this. Members get their own team/user layers; the platform (service role)
-- may pass the member to resolve for.
create function crm.get_setting(
  p_organization_id uuid,
  p_key text,
  p_agent_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_agent uuid := crm.assert_can_read_settings(p_organization_id);
begin
  if auth.role() = 'service_role' then
    v_agent := p_agent_id;
  elsif p_agent_id is not null and p_agent_id is distinct from v_agent then
    raise exception 'only the platform can read settings for another member'
      using errcode = '42501';
  end if;

  return (select r.value from crm.resolve_setting(p_organization_id, p_key, v_agent) r);
end;
$$;

-- Every setting with its effective value for the caller, where it came
-- from, and whether the caller may change the organization value. Feeds
-- the settings screen.
create function crm.get_settings(p_organization_id uuid)
returns table (
  key text,
  category text,
  label text,
  description text,
  schema jsonb,
  value jsonb,
  source text,
  is_locked boolean,
  scopes text[],
  tenant_value jsonb,
  can_edit boolean,
  team_conflict boolean,
  sort_order int
)
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_agent uuid := crm.assert_can_read_settings(p_organization_id);
begin
  return query
  select
    d.key, d.category, d.label, d.description, d.schema,
    r.value, r.source, d.is_locked, d.scopes,
    (select sv.value from crm.setting_values sv
     where sv.organization_id = p_organization_id
       and sv.setting_key = d.key
       and sv.scope = 'tenant'),
    not d.is_locked
      and 'tenant' = any(d.scopes)
      and crm.has_permission(p_organization_id, d.edit_permission),
    r.team_conflict,
    d.sort_order
  from crm.setting_definitions d
  cross join lateral crm.resolve_setting(p_organization_id, d.key, v_agent) r
  order by d.sort_order, d.key;
end;
$$;

-- Who may change a setting at a scope, and the row it targets. Shared by
-- set_setting and reset_setting.
--   tenant: the definition's edit_permission;
--   team:   the same, for a team of this organization;
--   user:   anyone for themselves (p_target null or their own agent), the
--           edit_permission for someone else.
-- The platform (service role) skips the permission checks, not the rules.
create function crm.setting_target(
  p_organization_id uuid,
  p_key text,
  p_scope text,
  p_target uuid,
  out team_id uuid,
  out agent_id uuid
)
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_def crm.setting_definitions;
  v_platform boolean := auth.role() = 'service_role';
  v_self uuid;
begin
  select * into v_def from crm.setting_definitions d where d.key = p_key;
  if not found then
    raise exception 'unknown setting %', p_key using errcode = '22023';
  end if;

  if v_def.is_locked then
    raise exception 'this setting is set by the platform and cannot be changed'
      using errcode = '42501';
  end if;

  if not p_scope = any(v_def.scopes) then
    raise exception 'this setting cannot be set per %', p_scope
      using errcode = '22023';
  end if;

  if not v_platform then
    v_self := crm.assert_can_read_settings(p_organization_id);
  end if;

  if p_scope = 'tenant' then
    if p_target is not null then
      raise exception 'an organization setting has no target' using errcode = '22023';
    end if;
    if not v_platform then
      perform crm.require_permission(p_organization_id, v_def.edit_permission);
    end if;
    return;
  end if;

  if p_scope = 'team' then
    if not exists (
      select 1 from crm.teams t
      where t.id = p_target and t.organization_id = p_organization_id
    ) then
      raise exception 'team not found' using errcode = '22023';
    end if;
    if not v_platform then
      perform crm.require_permission(p_organization_id, v_def.edit_permission);
    end if;
    team_id := p_target;
    return;
  end if;

  -- user
  agent_id := coalesce(p_target, v_self);
  if agent_id is null or not exists (
    select 1 from public.agents a
    where a.id = agent_id
      and a.organization_id = p_organization_id
      and a.user_id is not null
      and a.deleted_at is null
  ) then
    raise exception 'member not found' using errcode = '22023';
  end if;
  if not v_platform and agent_id is distinct from v_self then
    perform crm.require_permission(p_organization_id, v_def.edit_permission);
  end if;
end;
$$;

-- Sets a setting at a scope (default: the organization). Refuses locked
-- settings, scopes the setting does not allow, and invalid values.
create function crm.set_setting(
  p_organization_id uuid,
  p_key text,
  p_value jsonb,
  p_scope text default 'tenant',
  p_target uuid default null
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_target record;
  v_error text;
begin
  select * into v_target
  from crm.setting_target(p_organization_id, p_key, p_scope, p_target);

  v_error := crm.validate_setting_value(
    (select d.schema from crm.setting_definitions d where d.key = p_key),
    p_value
  );
  if v_error is not null then
    raise exception '%', v_error using errcode = '22023';
  end if;

  -- Modules are also features (P1-09): a plan can leave one out entirely,
  -- which turning the setting on cannot work around. Turning one off always
  -- works, and resetting (crm.reset_setting) is unaffected.
  if p_key like 'modules.%' and p_value = 'true'::jsonb
    and not crm.has_feature(p_organization_id, substring(p_key from 9)) then
    raise exception 'your plan does not include this module'
      using errcode = '42501';
  end if;

  insert into crm.setting_values (
    organization_id, setting_key, scope, team_id, agent_id, value, updated_by
  ) values (
    p_organization_id, p_key, p_scope, v_target.team_id, v_target.agent_id,
    p_value, (crm.caller_agent(p_organization_id)).id
  )
  on conflict on constraint setting_values_target_key do update
    set value = excluded.value,
        updated_by = excluded.updated_by,
        updated_at = now()
    where crm.setting_values.value is distinct from excluded.value;
end;
$$;

-- Removes the value at a scope, so the next layer down applies again.
create function crm.reset_setting(
  p_organization_id uuid,
  p_key text,
  p_scope text default 'tenant',
  p_target uuid default null
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_target record;
begin
  select * into v_target
  from crm.setting_target(p_organization_id, p_key, p_scope, p_target);

  delete from crm.setting_values sv
  where sv.organization_id = p_organization_id
    and sv.setting_key = p_key
    and sv.scope = p_scope
    and sv.team_id is not distinct from v_target.team_id
    and sv.agent_id is not distinct from v_target.agent_id;
end;
$$;

-- Teams --------------------------------------------------------------------------

create function crm.create_team(p_organization_id uuid, p_name text)
returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_id uuid;
begin
  perform crm.require_permission(p_organization_id, 'members.manage');

  insert into crm.teams (organization_id, name)
  values (p_organization_id, trim(p_name))
  returning id into v_id;

  return v_id;
end;
$$;

create function crm.rename_team(p_team_id uuid, p_name text) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(
    (select t.organization_id from crm.teams t where t.id = p_team_id),
    'members.manage'
  );

  update crm.teams set name = trim(p_name) where id = p_team_id;
end;
$$;

create function crm.delete_team(p_team_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(
    (select t.organization_id from crm.teams t where t.id = p_team_id),
    'members.manage'
  );

  delete from crm.teams where id = p_team_id;
end;
$$;

-- Adds (p_member true) or removes a member. Only active people of the
-- team's organization can join.
create function crm.set_team_member(
  p_team_id uuid,
  p_agent_id uuid,
  p_member boolean
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_org uuid := (select t.organization_id from crm.teams t where t.id = p_team_id);
begin
  perform crm.require_permission(v_org, 'members.manage');

  if not p_member then
    delete from crm.team_members
    where team_id = p_team_id and agent_id = p_agent_id;
    return;
  end if;

  if not exists (
    select 1 from public.agents a
    where a.id = p_agent_id
      and a.organization_id = v_org
      and a.user_id is not null
      and a.deleted_at is null
  ) then
    raise exception 'member not found' using errcode = '22023';
  end if;

  insert into crm.team_members (team_id, organization_id, agent_id)
  values (p_team_id, v_org, p_agent_id)
  on conflict do nothing;
end;
$$;
