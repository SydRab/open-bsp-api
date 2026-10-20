-- Layered settings (P1-04). A setting's effective value comes from the most
-- specific layer that has one:
--
--   user → team → organization (tenant) → pack → platform default
--
-- unless the setting is locked, in which case the platform default always
-- applies (compliance minimums such as "marketing needs opt-in").
--
-- setting_definitions is the platform catalog (one row per setting, loaded
-- by migrations); setting_values holds the overrides. The pack layer is read
-- from crm.organization_pack_items.pack_value, so a pack upgrade changes the
-- pack layer and never an organization's own choices. Resolver and writers:
-- 10-15.

create table crm.setting_definitions (
  key text not null,
  category text not null,
  label text not null,
  description text,
  -- What a valid value looks like: a JSON Schema subset checked by
  -- crm.validate_setting_value (10-15).
  schema jsonb not null,
  platform_default jsonb not null,
  -- The layers that may override the default.
  scopes text[] not null default '{tenant}',
  -- Locked: the platform default always applies; nobody can override it.
  is_locked boolean not null default false,
  -- Needed to change the organization or a team value. A member may always
  -- change their own user value when the setting allows the user scope.
  edit_permission text not null default 'organization.manage',
  -- Where the pack layer comes from: the pack item, and the path inside its
  -- value (empty = the whole value).
  pack_item_kind text,
  pack_item_key text,
  pack_item_path text[] not null default '{}',
  sort_order int not null default 0,
  created_at timestamp with time zone default now() not null
);

alter table only crm.setting_definitions
add constraint setting_definitions_pkey primary key (key);

alter table only crm.setting_definitions
add constraint setting_definitions_edit_permission_fkey
foreign key (edit_permission) references crm.permissions(key);

alter table only crm.setting_definitions
add constraint setting_definitions_key_check
check (key ~ '^[a-z_]+(\.[a-z_]+)+$');

alter table only crm.setting_definitions
add constraint setting_definitions_scopes_check
check (scopes <@ array['tenant', 'team', 'user']::text[]);

alter table only crm.setting_definitions
add constraint setting_definitions_pack_item_check
check ((pack_item_kind is null) = (pack_item_key is null));

create table crm.setting_values (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  setting_key text not null,
  scope text not null,
  team_id uuid,
  agent_id uuid,
  value jsonb not null,
  -- The agent who last set it (null for the platform or an API key).
  updated_by uuid,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.setting_values
add constraint setting_values_pkey primary key (id);

alter table only crm.setting_values
add constraint setting_values_target_key
unique nulls not distinct (organization_id, setting_key, scope, team_id, agent_id);

alter table only crm.setting_values
add constraint setting_values_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.setting_values
add constraint setting_values_setting_key_fkey
foreign key (setting_key) references crm.setting_definitions(key) on delete cascade;

alter table only crm.setting_values
add constraint setting_values_team_fkey
foreign key (organization_id, team_id)
references crm.teams(organization_id, id) on delete cascade;

alter table only crm.setting_values
add constraint setting_values_agent_fkey
foreign key (organization_id, agent_id)
references public.agents(organization_id, id) on delete cascade;

-- Exactly the target the scope names.
alter table only crm.setting_values
add constraint setting_values_scope_check
check (
  (scope = 'tenant' and team_id is null and agent_id is null)
  or (scope = 'team' and team_id is not null and agent_id is null)
  or (scope = 'user' and agent_id is not null and team_id is null)
);

create index setting_values_organization_id_key_idx
on crm.setting_values (organization_id, setting_key);
