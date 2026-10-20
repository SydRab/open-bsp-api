create schema if not exists "crm";


  create table "crm"."invitation_roles" (
    "invitation_id" uuid not null,
    "organization_id" uuid not null,
    "role_id" uuid not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "crm"."invitation_roles" enable row level security;


  create table "crm"."member_address_access" (
    "agent_id" uuid not null,
    "organization_id" uuid not null,
    "service" public.service not null,
    "address" text not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "crm"."member_address_access" enable row level security;


  create table "crm"."member_permission_overrides" (
    "agent_id" uuid not null,
    "organization_id" uuid not null,
    "permission" text not null,
    "granted" boolean not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "crm"."member_permission_overrides" enable row level security;


  create table "crm"."member_roles" (
    "agent_id" uuid not null,
    "organization_id" uuid not null,
    "role_id" uuid not null,
    "lead_scope" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."member_roles" enable row level security;


  create table "crm"."organization_pack_items" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "kind" text not null,
    "item_key" text not null,
    "value" jsonb not null,
    "pack_value" jsonb,
    "pack_version" integer not null,
    "is_customized" boolean not null default false,
    "removed_from_pack" boolean not null default false,
    "sort_order" integer not null default 0,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."organization_pack_items" enable row level security;


  create table "crm"."organization_packs" (
    "organization_id" uuid not null,
    "pack_key" text not null,
    "version" integer not null,
    "applied_at" timestamp with time zone not null default now(),
    "upgraded_at" timestamp with time zone
      );


alter table "crm"."organization_packs" enable row level security;


  create table "crm"."organization_profiles" (
    "organization_id" uuid not null,
    "slug" text not null,
    "timezone" text not null default 'Asia/Kolkata'::text,
    "locale" text not null default 'en'::text,
    "status" text not null default 'active'::text,
    "suspended_at" timestamp with time zone,
    "suspended_reason" text,
    "deletion_requested_at" timestamp with time zone,
    "deletion_requested_by" uuid,
    "purge_after" timestamp with time zone,
    "require_mfa_for_admins" boolean not null default false,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."organization_profiles" enable row level security;


  create table "crm"."pack_versions" (
    "pack_key" text not null,
    "version" integer not null,
    "definition" jsonb not null,
    "checksum" text not null,
    "published_at" timestamp with time zone not null default now()
      );


alter table "crm"."pack_versions" enable row level security;


  create table "crm"."permissions" (
    "key" text not null,
    "category" text not null,
    "description" text not null,
    "min_tier" public.role not null default 'member'::public.role,
    "sort_order" integer not null default 0,
    "created_at" timestamp with time zone not null default now()
      );


alter table "crm"."permissions" enable row level security;


  create table "crm"."preset_role_permissions" (
    "role_key" text not null,
    "permission" text not null
      );


alter table "crm"."preset_role_permissions" enable row level security;


  create table "crm"."preset_roles" (
    "key" text not null,
    "name" text not null,
    "description" text not null,
    "tier" public.role not null,
    "lead_scope" text not null default 'all'::text,
    "sort_order" integer not null default 0
      );


alter table "crm"."preset_roles" enable row level security;


  create table "crm"."role_permissions" (
    "organization_id" uuid not null,
    "role_id" uuid not null,
    "permission" text not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "crm"."role_permissions" enable row level security;


  create table "crm"."roles" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "key" text not null,
    "name" text not null,
    "description" text,
    "tier" public.role not null,
    "lead_scope" text not null default 'all'::text,
    "is_preset" boolean not null default true,
    "is_locked" boolean not null default false,
    "sort_order" integer not null default 0,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."roles" enable row level security;


  create table "crm"."vertical_packs" (
    "key" text not null,
    "name" text not null,
    "description" text,
    "is_default" boolean not null default false,
    "created_at" timestamp with time zone not null default now()
      );


alter table "crm"."vertical_packs" enable row level security;

CREATE INDEX invitation_roles_organization_id_idx ON crm.invitation_roles USING btree (organization_id);

CREATE UNIQUE INDEX invitation_roles_pkey ON crm.invitation_roles USING btree (invitation_id);

CREATE INDEX member_address_access_organization_id_idx ON crm.member_address_access USING btree (organization_id);

CREATE UNIQUE INDEX member_address_access_pkey ON crm.member_address_access USING btree (agent_id, service, address);

CREATE INDEX member_permission_overrides_organization_id_idx ON crm.member_permission_overrides USING btree (organization_id);

CREATE UNIQUE INDEX member_permission_overrides_pkey ON crm.member_permission_overrides USING btree (agent_id, permission);

CREATE INDEX member_roles_organization_id_idx ON crm.member_roles USING btree (organization_id);

CREATE UNIQUE INDEX member_roles_pkey ON crm.member_roles USING btree (agent_id);

CREATE INDEX member_roles_role_id_idx ON crm.member_roles USING btree (role_id);

CREATE UNIQUE INDEX organization_pack_items_key ON crm.organization_pack_items USING btree (organization_id, kind, item_key);

CREATE UNIQUE INDEX organization_pack_items_pkey ON crm.organization_pack_items USING btree (id);

CREATE UNIQUE INDEX organization_packs_pkey ON crm.organization_packs USING btree (organization_id);

CREATE UNIQUE INDEX organization_profiles_pkey ON crm.organization_profiles USING btree (organization_id);

CREATE INDEX organization_profiles_purge_idx ON crm.organization_profiles USING btree (purge_after) WHERE (status = 'pending_deletion'::text);

CREATE UNIQUE INDEX organization_profiles_slug_key ON crm.organization_profiles USING btree (slug);

CREATE UNIQUE INDEX pack_versions_pkey ON crm.pack_versions USING btree (pack_key, version);

CREATE UNIQUE INDEX permissions_pkey ON crm.permissions USING btree (key);

CREATE UNIQUE INDEX preset_role_permissions_pkey ON crm.preset_role_permissions USING btree (role_key, permission);

CREATE UNIQUE INDEX preset_roles_pkey ON crm.preset_roles USING btree (key);

CREATE INDEX role_permissions_organization_id_idx ON crm.role_permissions USING btree (organization_id);

CREATE UNIQUE INDEX role_permissions_pkey ON crm.role_permissions USING btree (role_id, permission);

CREATE UNIQUE INDEX roles_organization_id_id_key ON crm.roles USING btree (organization_id, id);

CREATE UNIQUE INDEX roles_organization_id_key_key ON crm.roles USING btree (organization_id, key);

CREATE UNIQUE INDEX roles_pkey ON crm.roles USING btree (id);

CREATE UNIQUE INDEX vertical_packs_one_default ON crm.vertical_packs USING btree (is_default) WHERE is_default;

CREATE UNIQUE INDEX vertical_packs_pkey ON crm.vertical_packs USING btree (key);

alter table "crm"."invitation_roles" add constraint "invitation_roles_pkey" PRIMARY KEY using index "invitation_roles_pkey";

alter table "crm"."member_address_access" add constraint "member_address_access_pkey" PRIMARY KEY using index "member_address_access_pkey";

alter table "crm"."member_permission_overrides" add constraint "member_permission_overrides_pkey" PRIMARY KEY using index "member_permission_overrides_pkey";

alter table "crm"."member_roles" add constraint "member_roles_pkey" PRIMARY KEY using index "member_roles_pkey";

alter table "crm"."organization_pack_items" add constraint "organization_pack_items_pkey" PRIMARY KEY using index "organization_pack_items_pkey";

alter table "crm"."organization_packs" add constraint "organization_packs_pkey" PRIMARY KEY using index "organization_packs_pkey";

alter table "crm"."organization_profiles" add constraint "organization_profiles_pkey" PRIMARY KEY using index "organization_profiles_pkey";

alter table "crm"."pack_versions" add constraint "pack_versions_pkey" PRIMARY KEY using index "pack_versions_pkey";

alter table "crm"."permissions" add constraint "permissions_pkey" PRIMARY KEY using index "permissions_pkey";

alter table "crm"."preset_role_permissions" add constraint "preset_role_permissions_pkey" PRIMARY KEY using index "preset_role_permissions_pkey";

alter table "crm"."preset_roles" add constraint "preset_roles_pkey" PRIMARY KEY using index "preset_roles_pkey";

alter table "crm"."role_permissions" add constraint "role_permissions_pkey" PRIMARY KEY using index "role_permissions_pkey";

alter table "crm"."roles" add constraint "roles_pkey" PRIMARY KEY using index "roles_pkey";

alter table "crm"."vertical_packs" add constraint "vertical_packs_pkey" PRIMARY KEY using index "vertical_packs_pkey";

alter table "crm"."invitation_roles" add constraint "invitation_roles_invitation_fkey" FOREIGN KEY (invitation_id) REFERENCES public.invitations(id) ON DELETE CASCADE not valid;

alter table "crm"."invitation_roles" validate constraint "invitation_roles_invitation_fkey";

alter table "crm"."invitation_roles" add constraint "invitation_roles_role_fkey" FOREIGN KEY (organization_id, role_id) REFERENCES crm.roles(organization_id, id) ON DELETE CASCADE not valid;

alter table "crm"."invitation_roles" validate constraint "invitation_roles_role_fkey";

alter table "crm"."member_address_access" add constraint "member_address_access_address_fkey" FOREIGN KEY (organization_id, service, address) REFERENCES public.organizations_addresses(organization_id, service, address) ON DELETE CASCADE not valid;

alter table "crm"."member_address_access" validate constraint "member_address_access_address_fkey";

alter table "crm"."member_address_access" add constraint "member_address_access_agent_fkey" FOREIGN KEY (organization_id, agent_id) REFERENCES public.agents(organization_id, id) ON DELETE CASCADE not valid;

alter table "crm"."member_address_access" validate constraint "member_address_access_agent_fkey";

alter table "crm"."member_address_access" add constraint "member_address_access_not_local" CHECK ((service <> 'local'::public.service)) not valid;

alter table "crm"."member_address_access" validate constraint "member_address_access_not_local";

alter table "crm"."member_permission_overrides" add constraint "member_permission_overrides_agent_fkey" FOREIGN KEY (organization_id, agent_id) REFERENCES public.agents(organization_id, id) ON DELETE CASCADE not valid;

alter table "crm"."member_permission_overrides" validate constraint "member_permission_overrides_agent_fkey";

alter table "crm"."member_permission_overrides" add constraint "member_permission_overrides_permission_fkey" FOREIGN KEY (permission) REFERENCES crm.permissions(key) ON DELETE CASCADE not valid;

alter table "crm"."member_permission_overrides" validate constraint "member_permission_overrides_permission_fkey";

alter table "crm"."member_roles" add constraint "member_roles_agent_fkey" FOREIGN KEY (organization_id, agent_id) REFERENCES public.agents(organization_id, id) ON DELETE CASCADE not valid;

alter table "crm"."member_roles" validate constraint "member_roles_agent_fkey";

alter table "crm"."member_roles" add constraint "member_roles_lead_scope_check" CHECK (((lead_scope IS NULL) OR (lead_scope = ANY (ARRAY['own'::text, 'team'::text, 'all'::text])))) not valid;

alter table "crm"."member_roles" validate constraint "member_roles_lead_scope_check";

alter table "crm"."member_roles" add constraint "member_roles_role_fkey" FOREIGN KEY (organization_id, role_id) REFERENCES crm.roles(organization_id, id) not valid;

alter table "crm"."member_roles" validate constraint "member_roles_role_fkey";

alter table "crm"."organization_pack_items" add constraint "organization_pack_items_key" UNIQUE using index "organization_pack_items_key";

alter table "crm"."organization_pack_items" add constraint "organization_pack_items_kind_check" CHECK ((kind = ANY (ARRAY['pipeline_stage'::text, 'custom_field'::text, 'qualification_question'::text, 'message_template'::text, 'compliance'::text, 'module'::text, 'terminology'::text]))) not valid;

alter table "crm"."organization_pack_items" validate constraint "organization_pack_items_kind_check";

alter table "crm"."organization_pack_items" add constraint "organization_pack_items_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."organization_pack_items" validate constraint "organization_pack_items_organization_id_fkey";

alter table "crm"."organization_packs" add constraint "organization_packs_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."organization_packs" validate constraint "organization_packs_organization_id_fkey";

alter table "crm"."organization_packs" add constraint "organization_packs_version_fkey" FOREIGN KEY (pack_key, version) REFERENCES crm.pack_versions(pack_key, version) not valid;

alter table "crm"."organization_packs" validate constraint "organization_packs_version_fkey";

alter table "crm"."organization_profiles" add constraint "organization_profiles_locale_check" CHECK ((locale = ANY (ARRAY['en'::text, 'hi'::text]))) not valid;

alter table "crm"."organization_profiles" validate constraint "organization_profiles_locale_check";

alter table "crm"."organization_profiles" add constraint "organization_profiles_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."organization_profiles" validate constraint "organization_profiles_organization_id_fkey";

alter table "crm"."organization_profiles" add constraint "organization_profiles_slug_format" CHECK ((slug ~ '^[a-z0-9][a-z0-9-]{1,46}[a-z0-9]$'::text)) not valid;

alter table "crm"."organization_profiles" validate constraint "organization_profiles_slug_format";

alter table "crm"."organization_profiles" add constraint "organization_profiles_slug_key" UNIQUE using index "organization_profiles_slug_key";

alter table "crm"."organization_profiles" add constraint "organization_profiles_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'suspended'::text, 'pending_deletion'::text]))) not valid;

alter table "crm"."organization_profiles" validate constraint "organization_profiles_status_check";

alter table "crm"."organization_profiles" add constraint "organization_profiles_status_fields_check" CHECK ((((status <> 'suspended'::text) OR (suspended_at IS NOT NULL)) AND ((status <> 'pending_deletion'::text) OR ((deletion_requested_at IS NOT NULL) AND (purge_after IS NOT NULL))))) not valid;

alter table "crm"."organization_profiles" validate constraint "organization_profiles_status_fields_check";

alter table "crm"."pack_versions" add constraint "pack_versions_pack_key_fkey" FOREIGN KEY (pack_key) REFERENCES crm.vertical_packs(key) not valid;

alter table "crm"."pack_versions" validate constraint "pack_versions_pack_key_fkey";

alter table "crm"."pack_versions" add constraint "pack_versions_version_check" CHECK ((version > 0)) not valid;

alter table "crm"."pack_versions" validate constraint "pack_versions_version_check";

alter table "crm"."permissions" add constraint "permissions_key_format" CHECK ((key ~ '^[a-z_]+\.[a-z_]+$'::text)) not valid;

alter table "crm"."permissions" validate constraint "permissions_key_format";

alter table "crm"."preset_role_permissions" add constraint "preset_role_permissions_permission_fkey" FOREIGN KEY (permission) REFERENCES crm.permissions(key) ON DELETE CASCADE not valid;

alter table "crm"."preset_role_permissions" validate constraint "preset_role_permissions_permission_fkey";

alter table "crm"."preset_role_permissions" add constraint "preset_role_permissions_role_key_fkey" FOREIGN KEY (role_key) REFERENCES crm.preset_roles(key) ON DELETE CASCADE not valid;

alter table "crm"."preset_role_permissions" validate constraint "preset_role_permissions_role_key_fkey";

alter table "crm"."preset_roles" add constraint "preset_roles_lead_scope_check" CHECK ((lead_scope = ANY (ARRAY['own'::text, 'team'::text, 'all'::text]))) not valid;

alter table "crm"."preset_roles" validate constraint "preset_roles_lead_scope_check";

alter table "crm"."role_permissions" add constraint "role_permissions_permission_fkey" FOREIGN KEY (permission) REFERENCES crm.permissions(key) ON DELETE CASCADE not valid;

alter table "crm"."role_permissions" validate constraint "role_permissions_permission_fkey";

alter table "crm"."role_permissions" add constraint "role_permissions_role_fkey" FOREIGN KEY (organization_id, role_id) REFERENCES crm.roles(organization_id, id) ON DELETE CASCADE not valid;

alter table "crm"."role_permissions" validate constraint "role_permissions_role_fkey";

alter table "crm"."roles" add constraint "roles_lead_scope_check" CHECK ((lead_scope = ANY (ARRAY['own'::text, 'team'::text, 'all'::text]))) not valid;

alter table "crm"."roles" validate constraint "roles_lead_scope_check";

alter table "crm"."roles" add constraint "roles_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."roles" validate constraint "roles_organization_id_fkey";

alter table "crm"."roles" add constraint "roles_organization_id_id_key" UNIQUE using index "roles_organization_id_id_key";

alter table "crm"."roles" add constraint "roles_organization_id_key_key" UNIQUE using index "roles_organization_id_key_key";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.after_agent_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role_id uuid;
  v_current_tier public.role;
begin
  if new.user_id is null or new.deleted_at is not null then
    return null;
  end if;

  -- Joining (insert) or coming back (revival) via accept_invitation, which
  -- runs as the invitee, before it marks the invitation accepted.
  if (tg_op = 'INSERT' or old.deleted_at is not null)
    and new.user_id = auth.uid() then
    select ir.role_id into v_role_id
    from crm.invitation_roles ir
    join public.invitations i on i.id = ir.invitation_id
    where i.organization_id = new.organization_id
      and i.status = 'pending'
      and lower(i.email) = lower(auth.jwt()->>'email')
    order by i.created_at desc
    limit 1;
  end if;

  if v_role_id is null then
    select r.tier into v_current_tier
    from crm.member_roles mr
    join crm.roles r on r.id = mr.role_id
    where mr.agent_id = new.id;

    if v_current_tier = new.role then
      return null;
    end if;

    select r.id into v_role_id
    from crm.roles r
    where r.organization_id = new.organization_id
      and r.key = crm.default_role_key(new.role);

    if v_role_id is null then
      return null;
    end if;
  end if;

  insert into crm.member_roles (agent_id, organization_id, role_id)
  values (new.id, new.organization_id, v_role_id)
  on conflict (agent_id) do update
    set role_id = excluded.role_id,
        updated_at = now()
    where crm.member_roles.role_id is distinct from excluded.role_id;

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.after_insert_on_organizations()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  insert into crm.organization_profiles (organization_id, slug)
  values (new.id, crm.generate_slug(new.name));

  perform crm.create_preset_roles(new.id);
  perform crm.apply_default_pack(new.id);

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.after_member_role_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update public.agents a
  set role = r.tier
  from crm.roles r
  where r.id = new.role_id
    and a.id = new.agent_id
    and a.role is distinct from r.tier;

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.apply_default_pack(p_organization_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_pack_key text;
  v_version int;
begin
  select vp.key, max(pv.version)
  into v_pack_key, v_version
  from crm.vertical_packs vp
  join crm.pack_versions pv on pv.pack_key = vp.key
  where vp.is_default
  group by vp.key;

  if v_pack_key is not null then
    perform crm.apply_pack(p_organization_id, v_pack_key, v_version);
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.apply_pack(p_organization_id uuid, p_pack_key text, p_version integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_definition jsonb;
  v_current crm.organization_packs;
begin
  select definition into v_definition
  from crm.pack_versions
  where pack_key = p_pack_key and version = p_version;

  if not found then
    raise exception 'pack %@% not found', p_pack_key, p_version
      using errcode = 'P0002';
  end if;

  select * into v_current
  from crm.organization_packs
  where organization_id = p_organization_id
  for update;

  if found and v_current.pack_key <> p_pack_key then
    raise exception 'organization runs pack %, switching packs is not supported', v_current.pack_key
      using errcode = '22023';
  end if;

  if found and v_current.version > p_version then
    raise exception 'cannot downgrade pack from % to %', v_current.version, p_version
      using errcode = '22023';
  end if;

  insert into crm.organization_pack_items (
    organization_id, kind, item_key, value, pack_value, pack_version, sort_order
  )
  select p_organization_id, i.kind, i.item_key, i.value, i.value, p_version, i.sort_order
  from crm.pack_items(v_definition) i
  on conflict (organization_id, kind, item_key) do update
    set value = case
          when crm.organization_pack_items.is_customized
            then crm.organization_pack_items.value
          else excluded.value
        end,
        pack_value = excluded.pack_value,
        pack_version = excluded.pack_version,
        removed_from_pack = false,
        sort_order = excluded.sort_order;

  update crm.organization_pack_items
  set removed_from_pack = true
  where organization_id = p_organization_id
    and pack_version <> p_version
    and not removed_from_pack;

  insert into crm.organization_packs (organization_id, pack_key, version)
  values (p_organization_id, p_pack_key, p_version)
  on conflict (organization_id) do update
    set version = excluded.version,
        upgraded_at = case
          when crm.organization_packs.version <> excluded.version then now()
          else crm.organization_packs.upgraded_at
        end;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.assert_can_edit_role(p_role_id uuid)
 RETURNS crm.roles
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.assert_can_manage_member(p_agent_id uuid)
 RETURNS public.agents
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.before_write_on_organization_pack_items()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  new.is_customized := new.value is distinct from new.pack_value;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.before_write_on_organization_profiles()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  new.slug := lower(new.slug);

  if not exists (
    select 1 from pg_catalog.pg_timezone_names where name = new.timezone
  ) then
    raise exception 'unknown timezone %', new.timezone
      using errcode = '22023';
  end if;

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.caller_agent(p_organization_id uuid)
 RETURNS public.agents
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select a.* from public.agents a
  where a.organization_id = p_organization_id
    and a.user_id = auth.uid()
    and a.deleted_at is null;
$function$
;

CREATE OR REPLACE FUNCTION crm.cancel_organization_deletion(p_organization_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.create_preset_roles(p_organization_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.deactivate_member(p_agent_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_target public.agents := crm.assert_can_manage_member(p_agent_id);
begin
  if v_target.user_id = auth.uid() then
    raise exception 'use leave organization to remove yourself'
      using errcode = '22023';
  end if;

  delete from public.agents where id = v_target.id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.default_role_key(p_tier public.role)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case p_tier
    when 'owner' then 'owner'
    when 'admin' then 'admin'
    else 'viewer'
  end;
$function$
;

CREATE OR REPLACE FUNCTION crm.deletion_grace_period()
 RETURNS interval
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select interval '30 days';
$function$
;

CREATE OR REPLACE FUNCTION crm.generate_slug(p_name text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.get_hidden_addresses()
 RETURNS TABLE(organization_id uuid, service public.service, address text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.get_my_organization_statuses()
 RETURNS TABLE(organization_id uuid, name text, status text, suspended_reason text, purge_after timestamp with time zone, can_cancel_deletion boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.get_permitted_orgs(p_permission text)
 RETURNS SETOF uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.has_permission(p_organization_id uuid, p_permission text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select p_organization_id in (select crm.get_permitted_orgs(p_permission));
$function$
;

CREATE OR REPLACE FUNCTION crm.invite_member(p_organization_id uuid, p_email text, p_role_key text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_email text := lower(trim(p_email));
  v_caller public.agents;
  v_role crm.roles;
  v_invitation_id uuid;
begin
  perform crm.require_permission(p_organization_id, 'members.invite');
  v_caller := crm.caller_agent(p_organization_id);

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
$function$
;

CREATE OR REPLACE FUNCTION crm.my_permissions(p_organization_id uuid)
 RETURNS SETOF text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select pm.key
  from crm.permissions pm
  where crm.has_permission(p_organization_id, pm.key)
  order by pm.sort_order, pm.key;
$function$
;

CREATE OR REPLACE FUNCTION crm.pack_items(p_definition jsonb)
 RETURNS TABLE(kind text, item_key text, value jsonb, sort_order integer)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select 'pipeline_stage', e->>'key', e, ord::int
  from jsonb_array_elements(coalesce(p_definition->'pipeline_stages', '[]')) with ordinality as t(e, ord)
  union all
  select 'custom_field', e->>'key', e, ord::int
  from jsonb_array_elements(coalesce(p_definition->'custom_fields', '[]')) with ordinality as t(e, ord)
  union all
  select 'qualification_question', e->>'key', e, ord::int
  from jsonb_array_elements(coalesce(p_definition->'qualification_questions', '[]')) with ordinality as t(e, ord)
  union all
  select 'message_template', e->>'name', e, ord::int
  from jsonb_array_elements(coalesce(p_definition->'message_templates', '[]')) with ordinality as t(e, ord)
  union all
  select 'compliance', k, v, ord::int
  from jsonb_each(coalesce(p_definition->'compliance', '{}')) with ordinality as t(k, v, ord)
  union all
  select 'module', k, v, ord::int
  from jsonb_each(coalesce(p_definition->'modules', '{}')) with ordinality as t(k, v, ord)
  union all
  select 'terminology', k, v, ord::int
  from jsonb_each(coalesce(p_definition->'terminology', '{}')) with ordinality as t(k, v, ord);
$function$
;

CREATE OR REPLACE FUNCTION crm.purge_organizations()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.reactivate_organization(p_organization_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.request_organization_deletion(p_organization_id uuid)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.require_permission(p_organization_id uuid, p_permission text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if p_organization_id is null
    or not crm.has_permission(p_organization_id, p_permission) then
    raise exception 'permission % required', p_permission
      using errcode = '42501';
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.reset_pack_item(p_item_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_organization_id uuid;
begin
  select organization_id into v_organization_id
  from crm.organization_pack_items
  where id = p_item_id;

  perform crm.require_permission(v_organization_id, 'organization.manage');

  update crm.organization_pack_items
  set value = pack_value
  where id = p_item_id
    and pack_value is not null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.reset_role_permissions(p_role_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.revoke_invitation(p_invitation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.set_member_address_access(p_agent_id uuid, p_service public.service, p_address text, p_allowed boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.set_member_lead_scope(p_agent_id uuid, p_lead_scope text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_target public.agents := crm.assert_can_manage_member(p_agent_id);
begin
  update crm.member_roles
  set lead_scope = p_lead_scope,
      updated_at = now()
  where agent_id = v_target.id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.set_member_permission_override(p_agent_id uuid, p_permission text, p_granted boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.set_member_role(p_agent_id uuid, p_role_key text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.set_require_mfa_for_admins(p_organization_id uuid, p_required boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.set_role_permission(p_role_id uuid, p_permission text, p_enabled boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.suspend_organization(p_organization_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.tier_rank(tier public.role)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case tier
    when 'owner' then 3
    when 'admin' then 2
    else 1
  end;
$function$
;

CREATE OR REPLACE FUNCTION crm.upgrade_organization_pack(p_organization_id uuid, p_version integer DEFAULT NULL::integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_current crm.organization_packs;
  v_target int;
begin
  perform crm.require_permission(p_organization_id, 'organization.manage');

  select * into v_current
  from crm.organization_packs
  where organization_id = p_organization_id;

  if not found then
    raise exception 'organization has no pack'
      using errcode = 'P0002';
  end if;

  v_target := coalesce(
    p_version,
    (select max(version) from crm.pack_versions where pack_key = v_current.pack_key)
  );

  perform crm.apply_pack(p_organization_id, v_current.pack_key, v_target);
  return v_target;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.get_authorized_orgs(role public.role DEFAULT 'member'::public.role)
 RETURNS SETOF uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  req_level int;
  api_key text;
  org_id uuid;
begin
  req_level := case role::text
    when 'owner' then 3
    when 'admin' then 2
    else 1 -- 'member'
  end;

  -- First, try JWT authentication via auth.uid()
  if auth.uid() is not null then
    -- Aliased because the parameter is also called `role`: a bare `role` here
    -- would resolve to it, and every caller would come back an owner.
    --
    -- No invitation clause: an agents row is a member, full stop. It used to
    -- also have to exclude rows whose invitation was still pending, and every
    -- helper that forgot to was a hole. Invitations are their own table now.
    return query select a.organization_id from public.agents a
    where
      a.user_id = auth.uid()
    -- A deleted agent is a former member: this is what makes marking the row
    -- revoke access rather than merely rename it.
    and a.deleted_at is null
    -- [crm] A suspended or pending-deletion organization is invisible to
    -- every policy that goes through here (P1-01, docs/upstream-edits.md).
    and not exists (
      select 1 from crm.organization_profiles p
      where p.organization_id = a.organization_id
        and p.status <> 'active'
    )
    and (
      case a.role
        when 'owner' then 3
        when 'admin' then 2
        else 1 -- 'member'
      end
    ) >= req_level;

    -- Authenticated but lacking the requested role: return the empty set so RLS
    -- subqueries can fall through to other OR-combined policies (e.g. a member
    -- editing themselves while an owner-only policy is also evaluated).
    -- Raising here would short-circuit the whole RLS evaluation.
    -- raise exception using
    --   errcode = '42501',
    --   message = format('insufficient permissions, %s role required', role::text);
    return;
  end if;

  -- Fallback to API key authentication
  api_key := current_setting('request.headers', true)::json->>'api-key';

  if api_key is not null then
    select a.organization_id into org_id
    from public.api_keys a
    where a.key = api_key
    -- [crm] Same suspension filter as the JWT branch.
    and not exists (
      select 1 from crm.organization_profiles p
      where p.organization_id = a.organization_id
        and p.status <> 'active'
    )
    and (
      case (a.role::text)
        when 'owner' then 3
        when 'admin' then 2
        else 1 -- 'member'
      end
    ) >= req_level;

    if org_id is not null then
      return next org_id;
    end if;
    -- Same reasoning as the JWT branch: invalid key or insufficient role returns
    -- the empty set, not a raise. Validate api-key existence at the request edge
    -- (e.g. a pre-request hook) if you want loud failure for missing/invalid keys.
    -- raise exception using
    --   errcode = '42501',
    --   message = format('invalid api key or insufficient permissions, %s role required', role::text);
    return;
  end if;

  raise exception using
    errcode = '42501',
    message = 'authentication required',
    hint = 'use api-key header or jwt authentication';
end;
$function$
;

grant select on table "crm"."invitation_roles" to "anon";

grant select on table "crm"."invitation_roles" to "authenticated";

grant delete on table "crm"."invitation_roles" to "service_role";

grant insert on table "crm"."invitation_roles" to "service_role";

grant references on table "crm"."invitation_roles" to "service_role";

grant select on table "crm"."invitation_roles" to "service_role";

grant trigger on table "crm"."invitation_roles" to "service_role";

grant truncate on table "crm"."invitation_roles" to "service_role";

grant update on table "crm"."invitation_roles" to "service_role";

grant select on table "crm"."member_address_access" to "anon";

grant select on table "crm"."member_address_access" to "authenticated";

grant delete on table "crm"."member_address_access" to "service_role";

grant insert on table "crm"."member_address_access" to "service_role";

grant references on table "crm"."member_address_access" to "service_role";

grant select on table "crm"."member_address_access" to "service_role";

grant trigger on table "crm"."member_address_access" to "service_role";

grant truncate on table "crm"."member_address_access" to "service_role";

grant update on table "crm"."member_address_access" to "service_role";

grant select on table "crm"."member_permission_overrides" to "anon";

grant select on table "crm"."member_permission_overrides" to "authenticated";

grant delete on table "crm"."member_permission_overrides" to "service_role";

grant insert on table "crm"."member_permission_overrides" to "service_role";

grant references on table "crm"."member_permission_overrides" to "service_role";

grant select on table "crm"."member_permission_overrides" to "service_role";

grant trigger on table "crm"."member_permission_overrides" to "service_role";

grant truncate on table "crm"."member_permission_overrides" to "service_role";

grant update on table "crm"."member_permission_overrides" to "service_role";

grant select on table "crm"."member_roles" to "anon";

grant select on table "crm"."member_roles" to "authenticated";

grant delete on table "crm"."member_roles" to "service_role";

grant insert on table "crm"."member_roles" to "service_role";

grant references on table "crm"."member_roles" to "service_role";

grant select on table "crm"."member_roles" to "service_role";

grant trigger on table "crm"."member_roles" to "service_role";

grant truncate on table "crm"."member_roles" to "service_role";

grant update on table "crm"."member_roles" to "service_role";

grant select on table "crm"."organization_pack_items" to "anon";

grant select on table "crm"."organization_pack_items" to "authenticated";

grant delete on table "crm"."organization_pack_items" to "service_role";

grant insert on table "crm"."organization_pack_items" to "service_role";

grant references on table "crm"."organization_pack_items" to "service_role";

grant select on table "crm"."organization_pack_items" to "service_role";

grant trigger on table "crm"."organization_pack_items" to "service_role";

grant truncate on table "crm"."organization_pack_items" to "service_role";

grant update on table "crm"."organization_pack_items" to "service_role";

grant select on table "crm"."organization_packs" to "anon";

grant select on table "crm"."organization_packs" to "authenticated";

grant delete on table "crm"."organization_packs" to "service_role";

grant insert on table "crm"."organization_packs" to "service_role";

grant references on table "crm"."organization_packs" to "service_role";

grant select on table "crm"."organization_packs" to "service_role";

grant trigger on table "crm"."organization_packs" to "service_role";

grant truncate on table "crm"."organization_packs" to "service_role";

grant update on table "crm"."organization_packs" to "service_role";

grant select on table "crm"."organization_profiles" to "anon";

grant select on table "crm"."organization_profiles" to "authenticated";

grant delete on table "crm"."organization_profiles" to "service_role";

grant insert on table "crm"."organization_profiles" to "service_role";

grant references on table "crm"."organization_profiles" to "service_role";

grant select on table "crm"."organization_profiles" to "service_role";

grant trigger on table "crm"."organization_profiles" to "service_role";

grant truncate on table "crm"."organization_profiles" to "service_role";

grant update on table "crm"."organization_profiles" to "service_role";

grant select on table "crm"."pack_versions" to "anon";

grant select on table "crm"."pack_versions" to "authenticated";

grant delete on table "crm"."pack_versions" to "service_role";

grant insert on table "crm"."pack_versions" to "service_role";

grant references on table "crm"."pack_versions" to "service_role";

grant select on table "crm"."pack_versions" to "service_role";

grant trigger on table "crm"."pack_versions" to "service_role";

grant truncate on table "crm"."pack_versions" to "service_role";

grant update on table "crm"."pack_versions" to "service_role";

grant select on table "crm"."permissions" to "anon";

grant select on table "crm"."permissions" to "authenticated";

grant delete on table "crm"."permissions" to "service_role";

grant insert on table "crm"."permissions" to "service_role";

grant references on table "crm"."permissions" to "service_role";

grant select on table "crm"."permissions" to "service_role";

grant trigger on table "crm"."permissions" to "service_role";

grant truncate on table "crm"."permissions" to "service_role";

grant update on table "crm"."permissions" to "service_role";

grant select on table "crm"."preset_role_permissions" to "anon";

grant select on table "crm"."preset_role_permissions" to "authenticated";

grant delete on table "crm"."preset_role_permissions" to "service_role";

grant insert on table "crm"."preset_role_permissions" to "service_role";

grant references on table "crm"."preset_role_permissions" to "service_role";

grant select on table "crm"."preset_role_permissions" to "service_role";

grant trigger on table "crm"."preset_role_permissions" to "service_role";

grant truncate on table "crm"."preset_role_permissions" to "service_role";

grant update on table "crm"."preset_role_permissions" to "service_role";

grant select on table "crm"."preset_roles" to "anon";

grant select on table "crm"."preset_roles" to "authenticated";

grant delete on table "crm"."preset_roles" to "service_role";

grant insert on table "crm"."preset_roles" to "service_role";

grant references on table "crm"."preset_roles" to "service_role";

grant select on table "crm"."preset_roles" to "service_role";

grant trigger on table "crm"."preset_roles" to "service_role";

grant truncate on table "crm"."preset_roles" to "service_role";

grant update on table "crm"."preset_roles" to "service_role";

grant select on table "crm"."role_permissions" to "anon";

grant select on table "crm"."role_permissions" to "authenticated";

grant delete on table "crm"."role_permissions" to "service_role";

grant insert on table "crm"."role_permissions" to "service_role";

grant references on table "crm"."role_permissions" to "service_role";

grant select on table "crm"."role_permissions" to "service_role";

grant trigger on table "crm"."role_permissions" to "service_role";

grant truncate on table "crm"."role_permissions" to "service_role";

grant update on table "crm"."role_permissions" to "service_role";

grant select on table "crm"."roles" to "anon";

grant select on table "crm"."roles" to "authenticated";

grant delete on table "crm"."roles" to "service_role";

grant insert on table "crm"."roles" to "service_role";

grant references on table "crm"."roles" to "service_role";

grant select on table "crm"."roles" to "service_role";

grant trigger on table "crm"."roles" to "service_role";

grant truncate on table "crm"."roles" to "service_role";

grant update on table "crm"."roles" to "service_role";

grant select on table "crm"."vertical_packs" to "anon";

grant select on table "crm"."vertical_packs" to "authenticated";

grant delete on table "crm"."vertical_packs" to "service_role";

grant insert on table "crm"."vertical_packs" to "service_role";

grant references on table "crm"."vertical_packs" to "service_role";

grant select on table "crm"."vertical_packs" to "service_role";

grant trigger on table "crm"."vertical_packs" to "service_role";

grant truncate on table "crm"."vertical_packs" to "service_role";

grant update on table "crm"."vertical_packs" to "service_role";


  create policy "invitees can read their invitation role"
  on "crm"."invitation_roles"
  as permissive
  for select
  to authenticated
using ((invitation_id IN ( SELECT i.id
   FROM public.invitations i
  WHERE ((i.status = 'pending'::text) AND (lower(i.email) = lower(( SELECT (auth.jwt() ->> 'email'::text))))))));



  create policy "members can read their orgs invitation roles"
  on "crm"."invitation_roles"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));



  create policy "members can read their own number access, managers all"
  on "crm"."member_address_access"
  as permissive
  for select
  to authenticated, anon
using (((agent_id IN ( SELECT public.get_own_agents() AS get_own_agents)) OR (organization_id IN ( SELECT crm.get_permitted_orgs('members.manage'::text) AS get_permitted_orgs))));



  create policy "members can read their own overrides, managers all"
  on "crm"."member_permission_overrides"
  as permissive
  for select
  to authenticated, anon
using (((agent_id IN ( SELECT public.get_own_agents() AS get_own_agents)) OR (organization_id IN ( SELECT crm.get_permitted_orgs('members.manage'::text) AS get_permitted_orgs))));



  create policy "members can read their orgs member roles"
  on "crm"."member_roles"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));



  create policy "managers can edit their orgs pack items"
  on "crm"."organization_pack_items"
  as permissive
  for update
  to authenticated
using ((organization_id IN ( SELECT crm.get_permitted_orgs('organization.manage'::text) AS get_permitted_orgs)))
with check ((organization_id IN ( SELECT crm.get_permitted_orgs('organization.manage'::text) AS get_permitted_orgs)));



  create policy "members can read their orgs pack items"
  on "crm"."organization_pack_items"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));



  create policy "members can read their orgs pack"
  on "crm"."organization_packs"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));



  create policy "managers can update their orgs profile"
  on "crm"."organization_profiles"
  as permissive
  for update
  to authenticated
using ((organization_id IN ( SELECT crm.get_permitted_orgs('organization.manage'::text) AS get_permitted_orgs)))
with check ((organization_id IN ( SELECT crm.get_permitted_orgs('organization.manage'::text) AS get_permitted_orgs)));



  create policy "members can read their orgs profile"
  on "crm"."organization_profiles"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));



  create policy "signed-in users can read pack versions"
  on "crm"."pack_versions"
  as permissive
  for select
  to authenticated, anon
using (true);



  create policy "signed-in users can read the permission catalog"
  on "crm"."permissions"
  as permissive
  for select
  to authenticated, anon
using (true);



  create policy "signed-in users can read preset role permissions"
  on "crm"."preset_role_permissions"
  as permissive
  for select
  to authenticated, anon
using (true);



  create policy "signed-in users can read preset roles"
  on "crm"."preset_roles"
  as permissive
  for select
  to authenticated, anon
using (true);



  create policy "members can read their orgs role permissions"
  on "crm"."role_permissions"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));



  create policy "members can read their orgs roles"
  on "crm"."roles"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));



  create policy "signed-in users can read vertical packs"
  on "crm"."vertical_packs"
  as permissive
  for select
  to authenticated, anon
using (true);



  create policy "crm: creating ai agents needs ai_agents.manage"
  on "public"."agents"
  as restrictive
  for insert
  to authenticated, anon
with check (((user_id IS NOT NULL) OR (organization_id IN ( SELECT crm.get_permitted_orgs('ai_agents.manage'::text) AS get_permitted_orgs))));



  create policy "crm: deleting ai agents needs ai_agents.manage"
  on "public"."agents"
  as restrictive
  for delete
  to authenticated, anon
using (((user_id IS NOT NULL) OR (organization_id IN ( SELECT crm.get_permitted_orgs('ai_agents.manage'::text) AS get_permitted_orgs))));



  create policy "crm: adding contacts needs contacts.edit"
  on "public"."contacts_addresses"
  as restrictive
  for insert
  to authenticated, anon
with check ((organization_id IN ( SELECT crm.get_permitted_orgs('contacts.edit'::text) AS get_permitted_orgs)));



  create policy "crm: deleting contacts needs contacts.edit"
  on "public"."contacts_addresses"
  as restrictive
  for delete
  to authenticated, anon
using ((organization_id IN ( SELECT crm.get_permitted_orgs('contacts.edit'::text) AS get_permitted_orgs)));



  create policy "crm: editing contacts needs contacts.edit"
  on "public"."contacts_addresses"
  as restrictive
  for update
  to authenticated, anon
using ((organization_id IN ( SELECT crm.get_permitted_orgs('contacts.edit'::text) AS get_permitted_orgs)));



  create policy "crm: reading contacts needs contacts.view"
  on "public"."contacts_addresses"
  as restrictive
  for select
  to authenticated, anon
using ((((organization_id IN ( SELECT crm.get_permitted_orgs('contacts.view'::text) AS get_permitted_orgs)) OR (organization_id IN ( SELECT crm.get_permitted_orgs('conversations.view'::text) AS get_permitted_orgs))) AND (NOT ((organization_id, service, organization_address) IN ( SELECT h.organization_id,
    h.service,
    h.address
   FROM crm.get_hidden_addresses() h(organization_id, service, address))))));



  create policy "crm: reading conversations needs conversations.view"
  on "public"."conversations"
  as restrictive
  for select
  to authenticated, anon
using (((service = 'local'::public.service) OR ((organization_id IN ( SELECT crm.get_permitted_orgs('conversations.view'::text) AS get_permitted_orgs)) AND (NOT ((organization_id, service, organization_address) IN ( SELECT h.organization_id,
    h.service,
    h.address
   FROM crm.get_hidden_addresses() h(organization_id, service, address)))))));



  create policy "crm: reading messages needs conversations.view"
  on "public"."messages"
  as restrictive
  for select
  to authenticated, anon
using (((service = 'local'::public.service) OR ((organization_id IN ( SELECT crm.get_permitted_orgs('conversations.view'::text) AS get_permitted_orgs)) AND (NOT ((organization_id, service, organization_address) IN ( SELECT h.organization_id,
    h.service,
    h.address
   FROM crm.get_hidden_addresses() h(organization_id, service, address)))))));



  create policy "crm: sending needs messages.send"
  on "public"."messages"
  as restrictive
  for insert
  to authenticated, anon
with check (((service = 'local'::public.service) OR (organization_id IN ( SELECT crm.get_permitted_orgs('messages.send'::text) AS get_permitted_orgs))));



  create policy "crm: orgs are deleted through the deletion request"
  on "public"."organizations"
  as restrictive
  for delete
  to authenticated, anon
using (false);



  create policy "crm: updating an org needs organization.manage"
  on "public"."organizations"
  as restrictive
  for update
  to authenticated, anon
using ((id IN ( SELECT crm.get_permitted_orgs('organization.manage'::text) AS get_permitted_orgs)));



  create policy "crm: number access scope"
  on "public"."organizations_addresses"
  as restrictive
  for select
  to authenticated, anon
using ((NOT ((organization_id, service, address) IN ( SELECT h.organization_id,
    h.service,
    h.address
   FROM crm.get_hidden_addresses() h(organization_id, service, address)))));


CREATE TRIGGER sync_agent_tier AFTER INSERT OR UPDATE OF role_id ON crm.member_roles FOR EACH ROW EXECUTE FUNCTION crm.after_member_role_change();

CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.organization_pack_items FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');

CREATE TRIGGER track_customization BEFORE INSERT OR UPDATE ON crm.organization_pack_items FOR EACH ROW EXECUTE FUNCTION crm.before_write_on_organization_pack_items();

CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.organization_profiles FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');

CREATE TRIGGER validate_profile BEFORE INSERT OR UPDATE ON crm.organization_profiles FOR EACH ROW EXECUTE FUNCTION crm.before_write_on_organization_profiles();

CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.roles FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');

CREATE TRIGGER crm_sync_member_role AFTER INSERT OR UPDATE OF role, deleted_at ON public.agents FOR EACH ROW EXECUTE FUNCTION crm.after_agent_change();

CREATE TRIGGER crm_handle_new_organization AFTER INSERT ON public.organizations FOR EACH ROW EXECUTE FUNCTION crm.after_insert_on_organizations();


