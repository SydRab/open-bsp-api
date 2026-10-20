drop policy "managers can edit their orgs pack items" on "crm"."organization_pack_items";


  create table "crm"."setting_definitions" (
    "key" text not null,
    "category" text not null,
    "label" text not null,
    "description" text,
    "schema" jsonb not null,
    "platform_default" jsonb not null,
    "scopes" text[] not null default '{tenant}'::text[],
    "is_locked" boolean not null default false,
    "edit_permission" text not null default 'organization.manage'::text,
    "pack_item_kind" text,
    "pack_item_key" text,
    "pack_item_path" text[] not null default '{}'::text[],
    "sort_order" integer not null default 0,
    "created_at" timestamp with time zone not null default now()
      );


alter table "crm"."setting_definitions" enable row level security;


  create table "crm"."setting_values" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "setting_key" text not null,
    "scope" text not null,
    "team_id" uuid,
    "agent_id" uuid,
    "value" jsonb not null,
    "updated_by" uuid,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."setting_values" enable row level security;


  create table "crm"."team_members" (
    "team_id" uuid not null,
    "organization_id" uuid not null,
    "agent_id" uuid not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "crm"."team_members" enable row level security;


  create table "crm"."teams" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "name" text not null,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."teams" enable row level security;

CREATE UNIQUE INDEX setting_definitions_pkey ON crm.setting_definitions USING btree (key);

CREATE INDEX setting_values_organization_id_key_idx ON crm.setting_values USING btree (organization_id, setting_key);

CREATE UNIQUE INDEX setting_values_pkey ON crm.setting_values USING btree (id);

CREATE UNIQUE INDEX setting_values_target_key ON crm.setting_values USING btree (organization_id, setting_key, scope, team_id, agent_id) NULLS NOT DISTINCT;

CREATE INDEX team_members_agent_id_idx ON crm.team_members USING btree (agent_id);

CREATE INDEX team_members_organization_id_idx ON crm.team_members USING btree (organization_id);

CREATE UNIQUE INDEX team_members_pkey ON crm.team_members USING btree (team_id, agent_id);

CREATE UNIQUE INDEX teams_organization_id_id_key ON crm.teams USING btree (organization_id, id);

CREATE UNIQUE INDEX teams_organization_id_name_key ON crm.teams USING btree (organization_id, name);

CREATE UNIQUE INDEX teams_pkey ON crm.teams USING btree (id);

alter table "crm"."setting_definitions" add constraint "setting_definitions_pkey" PRIMARY KEY using index "setting_definitions_pkey";

alter table "crm"."setting_values" add constraint "setting_values_pkey" PRIMARY KEY using index "setting_values_pkey";

alter table "crm"."team_members" add constraint "team_members_pkey" PRIMARY KEY using index "team_members_pkey";

alter table "crm"."teams" add constraint "teams_pkey" PRIMARY KEY using index "teams_pkey";

alter table "crm"."setting_definitions" add constraint "setting_definitions_edit_permission_fkey" FOREIGN KEY (edit_permission) REFERENCES crm.permissions(key) not valid;

alter table "crm"."setting_definitions" validate constraint "setting_definitions_edit_permission_fkey";

alter table "crm"."setting_definitions" add constraint "setting_definitions_key_check" CHECK ((key ~ '^[a-z_]+(\.[a-z_]+)+$'::text)) not valid;

alter table "crm"."setting_definitions" validate constraint "setting_definitions_key_check";

alter table "crm"."setting_definitions" add constraint "setting_definitions_pack_item_check" CHECK (((pack_item_kind IS NULL) = (pack_item_key IS NULL))) not valid;

alter table "crm"."setting_definitions" validate constraint "setting_definitions_pack_item_check";

alter table "crm"."setting_definitions" add constraint "setting_definitions_scopes_check" CHECK ((scopes <@ ARRAY['tenant'::text, 'team'::text, 'user'::text])) not valid;

alter table "crm"."setting_definitions" validate constraint "setting_definitions_scopes_check";

alter table "crm"."setting_values" add constraint "setting_values_agent_fkey" FOREIGN KEY (organization_id, agent_id) REFERENCES public.agents(organization_id, id) ON DELETE CASCADE not valid;

alter table "crm"."setting_values" validate constraint "setting_values_agent_fkey";

alter table "crm"."setting_values" add constraint "setting_values_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."setting_values" validate constraint "setting_values_organization_id_fkey";

alter table "crm"."setting_values" add constraint "setting_values_scope_check" CHECK ((((scope = 'tenant'::text) AND (team_id IS NULL) AND (agent_id IS NULL)) OR ((scope = 'team'::text) AND (team_id IS NOT NULL) AND (agent_id IS NULL)) OR ((scope = 'user'::text) AND (agent_id IS NOT NULL) AND (team_id IS NULL)))) not valid;

alter table "crm"."setting_values" validate constraint "setting_values_scope_check";

alter table "crm"."setting_values" add constraint "setting_values_setting_key_fkey" FOREIGN KEY (setting_key) REFERENCES crm.setting_definitions(key) ON DELETE CASCADE not valid;

alter table "crm"."setting_values" validate constraint "setting_values_setting_key_fkey";

alter table "crm"."setting_values" add constraint "setting_values_target_key" UNIQUE using index "setting_values_target_key";

alter table "crm"."setting_values" add constraint "setting_values_team_fkey" FOREIGN KEY (organization_id, team_id) REFERENCES crm.teams(organization_id, id) ON DELETE CASCADE not valid;

alter table "crm"."setting_values" validate constraint "setting_values_team_fkey";

alter table "crm"."team_members" add constraint "team_members_agent_fkey" FOREIGN KEY (organization_id, agent_id) REFERENCES public.agents(organization_id, id) ON DELETE CASCADE not valid;

alter table "crm"."team_members" validate constraint "team_members_agent_fkey";

alter table "crm"."team_members" add constraint "team_members_team_fkey" FOREIGN KEY (organization_id, team_id) REFERENCES crm.teams(organization_id, id) ON DELETE CASCADE not valid;

alter table "crm"."team_members" validate constraint "team_members_team_fkey";

alter table "crm"."teams" add constraint "teams_name_check" CHECK (((length(TRIM(BOTH FROM name)) >= 1) AND (length(TRIM(BOTH FROM name)) <= 60))) not valid;

alter table "crm"."teams" validate constraint "teams_name_check";

alter table "crm"."teams" add constraint "teams_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."teams" validate constraint "teams_organization_id_fkey";

alter table "crm"."teams" add constraint "teams_organization_id_id_key" UNIQUE using index "teams_organization_id_id_key";

alter table "crm"."teams" add constraint "teams_organization_id_name_key" UNIQUE using index "teams_organization_id_name_key";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.assert_can_read_settings(p_organization_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.audit_setting_values()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_row crm.setting_values := case when tg_op = 'DELETE' then old else new end;
  v_where jsonb := jsonb_strip_nulls(jsonb_build_object(
    'key', v_row.setting_key,
    'scope', v_row.scope,
    'team_id', v_row.team_id,
    'agent_id', v_row.agent_id
  ));
begin
  if tg_op = 'UPDATE' and new.value is not distinct from old.value then
    return null;
  end if;

  perform crm.write_audit(
    v_row.organization_id,
    case when tg_op = 'DELETE' then 'setting.reset' else 'setting.changed' end,
    'setting',
    v_row.setting_key,
    -- Values are never null (validated), so stripping only drops the side
    -- that does not exist: no before on a first change, no after on a reset.
    v_where || jsonb_strip_nulls(jsonb_build_object(
      'before', case when tg_op <> 'INSERT' then old.value end,
      'after', case when tg_op <> 'DELETE' then new.value end
    ))
  );

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.audit_team_members()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_row crm.team_members := case when tg_op = 'DELETE' then old else new end;
  v_team text := (select t.name from crm.teams t where t.id = v_row.team_id);
begin
  if v_team is null then
    return null;
  end if;

  perform crm.write_audit(
    v_row.organization_id,
    case when tg_op = 'DELETE' then 'team.member_removed' else 'team.member_added' end,
    'member',
    v_row.agent_id::text,
    jsonb_build_object('team', v_team, 'team_id', v_row.team_id)
  );

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.audit_teams()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'INSERT' then
    perform crm.write_audit(
      new.organization_id, 'team.created', 'team', new.id::text,
      jsonb_build_object('name', new.name)
    );
  elsif tg_op = 'DELETE' then
    perform crm.write_audit(
      old.organization_id, 'team.deleted', 'team', old.id::text,
      jsonb_build_object('name', old.name)
    );
  elsif new.name is distinct from old.name then
    perform crm.write_audit(
      new.organization_id, 'team.renamed', 'team', new.id::text,
      jsonb_build_object(
        'before', jsonb_build_object('name', old.name),
        'after', jsonb_build_object('name', new.name)
      )
    );
  end if;

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.create_team(p_organization_id uuid, p_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
begin
  perform crm.require_permission(p_organization_id, 'members.manage');

  insert into crm.teams (organization_id, name)
  values (p_organization_id, trim(p_name))
  returning id into v_id;

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.delete_team(p_team_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(
    (select t.organization_id from crm.teams t where t.id = p_team_id),
    'members.manage'
  );

  delete from crm.teams where id = p_team_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.get_setting(p_organization_id uuid, p_key text, p_agent_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.get_settings(p_organization_id uuid)
 RETURNS TABLE(key text, category text, label text, description text, schema jsonb, value jsonb, source text, is_locked boolean, scopes text[], tenant_value jsonb, can_edit boolean, team_conflict boolean, sort_order integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.rename_team(p_team_id uuid, p_name text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(
    (select t.organization_id from crm.teams t where t.id = p_team_id),
    'members.manage'
  );

  update crm.teams set name = trim(p_name) where id = p_team_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.reset_setting(p_organization_id uuid, p_key text, p_scope text DEFAULT 'tenant'::text, p_target uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.resolve_setting(p_organization_id uuid, p_key text, p_agent_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(value jsonb, source text, team_conflict boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.set_setting(p_organization_id uuid, p_key text, p_value jsonb, p_scope text DEFAULT 'tenant'::text, p_target uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.set_team_member(p_team_id uuid, p_agent_id uuid, p_member boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.setting_target(p_organization_id uuid, p_key text, p_scope text, p_target uuid, OUT team_id uuid, OUT agent_id uuid)
 RETURNS record
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.validate_setting_value(p_schema jsonb, p_value jsonb, p_path text DEFAULT 'value'::text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
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
$function$
;

grant select on table "crm"."setting_definitions" to "anon";

grant select on table "crm"."setting_definitions" to "authenticated";

grant delete on table "crm"."setting_definitions" to "service_role";

grant insert on table "crm"."setting_definitions" to "service_role";

grant references on table "crm"."setting_definitions" to "service_role";

grant select on table "crm"."setting_definitions" to "service_role";

grant trigger on table "crm"."setting_definitions" to "service_role";

grant truncate on table "crm"."setting_definitions" to "service_role";

grant update on table "crm"."setting_definitions" to "service_role";

grant select on table "crm"."setting_values" to "anon";

grant select on table "crm"."setting_values" to "authenticated";

grant delete on table "crm"."setting_values" to "service_role";

grant insert on table "crm"."setting_values" to "service_role";

grant references on table "crm"."setting_values" to "service_role";

grant select on table "crm"."setting_values" to "service_role";

grant trigger on table "crm"."setting_values" to "service_role";

grant truncate on table "crm"."setting_values" to "service_role";

grant update on table "crm"."setting_values" to "service_role";

grant select on table "crm"."team_members" to "anon";

grant select on table "crm"."team_members" to "authenticated";

grant delete on table "crm"."team_members" to "service_role";

grant insert on table "crm"."team_members" to "service_role";

grant references on table "crm"."team_members" to "service_role";

grant select on table "crm"."team_members" to "service_role";

grant trigger on table "crm"."team_members" to "service_role";

grant truncate on table "crm"."team_members" to "service_role";

grant update on table "crm"."team_members" to "service_role";

grant select on table "crm"."teams" to "anon";

grant select on table "crm"."teams" to "authenticated";

grant delete on table "crm"."teams" to "service_role";

grant insert on table "crm"."teams" to "service_role";

grant references on table "crm"."teams" to "service_role";

grant select on table "crm"."teams" to "service_role";

grant trigger on table "crm"."teams" to "service_role";

grant truncate on table "crm"."teams" to "service_role";

grant update on table "crm"."teams" to "service_role";


  create policy "signed-in users can read the settings catalog"
  on "crm"."setting_definitions"
  as permissive
  for select
  to authenticated, anon
using (true);



  create policy "members can read their orgs settings"
  on "crm"."setting_values"
  as permissive
  for select
  to authenticated, anon
using (((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)) AND ((scope <> 'user'::text) OR (agent_id IN ( SELECT public.get_own_agents() AS get_own_agents)) OR (organization_id IN ( SELECT crm.get_permitted_orgs('members.manage'::text) AS get_permitted_orgs)))));



  create policy "members can read their orgs team members"
  on "crm"."team_members"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));



  create policy "members can read their orgs teams"
  on "crm"."teams"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));



  create policy "managers can edit their orgs pack items"
  on "crm"."organization_pack_items"
  as permissive
  for update
  to authenticated
using (((organization_id IN ( SELECT crm.get_permitted_orgs('organization.manage'::text) AS get_permitted_orgs)) AND (kind <> ALL (ARRAY['compliance'::text, 'module'::text]))))
with check (((organization_id IN ( SELECT crm.get_permitted_orgs('organization.manage'::text) AS get_permitted_orgs)) AND (kind <> ALL (ARRAY['compliance'::text, 'module'::text]))));


CREATE TRIGGER audit AFTER INSERT OR DELETE OR UPDATE ON crm.setting_values FOR EACH ROW EXECUTE FUNCTION crm.audit_setting_values();

CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.setting_values FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');

CREATE TRIGGER audit AFTER INSERT OR DELETE ON crm.team_members FOR EACH ROW EXECUTE FUNCTION crm.audit_team_members();

CREATE TRIGGER audit AFTER INSERT OR DELETE OR UPDATE ON crm.teams FOR EACH ROW EXECUTE FUNCTION crm.audit_teams();

CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.teams FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');


