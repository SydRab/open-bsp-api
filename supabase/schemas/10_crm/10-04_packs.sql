-- Vertical packs (P1-05). A pack is a versioned bundle of defaults for one
-- industry: pipeline stages, custom fields, qualification questions, a
-- template library, compliance defaults, enabled modules and a terminology
-- map. Definitions live in the repo (`packs/<key>/v<n>.json`) and are loaded
-- by a generated migration (`scripts/crm/pack-to-sql.ts`); a published
-- version is never changed, only superseded.

create table crm.vertical_packs (
  key text not null,
  name text not null,
  description text,
  -- The pack a new organization gets. At most one.
  is_default boolean not null default false,
  created_at timestamp with time zone default now() not null
);

alter table only crm.vertical_packs
add constraint vertical_packs_pkey primary key (key);

create unique index vertical_packs_one_default
on crm.vertical_packs (is_default)
where is_default;

create table crm.pack_versions (
  pack_key text not null,
  version int not null,
  definition jsonb not null,
  -- sha256 of the definition file, so a re-run of the generator can tell an
  -- edited published file from an unchanged one.
  checksum text not null,
  published_at timestamp with time zone default now() not null
);

alter table only crm.pack_versions
add constraint pack_versions_pkey primary key (pack_key, version);

alter table only crm.pack_versions
add constraint pack_versions_pack_key_fkey
foreign key (pack_key) references crm.vertical_packs(key);

alter table only crm.pack_versions
add constraint pack_versions_version_check check (version > 0);

-- Which pack (and version) an organization runs.
create table crm.organization_packs (
  organization_id uuid not null,
  pack_key text not null,
  version int not null,
  applied_at timestamp with time zone default now() not null,
  upgraded_at timestamp with time zone
);

alter table only crm.organization_packs
add constraint organization_packs_pkey primary key (organization_id);

alter table only crm.organization_packs
add constraint organization_packs_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.organization_packs
add constraint organization_packs_version_fkey
foreign key (pack_key, version) references crm.pack_versions(pack_key, version);

-- The tenant's copy of each pack item. `value` is what the tenant uses and
-- may edit; `pack_value` is what the pack last said. An item is customized
-- exactly when the two differ (kept by a trigger), and a pack upgrade only
-- moves `value` along for items that are not customized — that is the whole
-- "upgrades do not overwrite tenant edits" rule.
--
-- Generic on purpose: the typed engines (settings P1-04, custom fields P1-06,
-- pipeline, templates) do not exist yet and will read their kind from here.
create table crm.organization_pack_items (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  kind text not null,
  item_key text not null,
  value jsonb not null,
  pack_value jsonb,
  -- The pack version that last wrote pack_value.
  pack_version int not null,
  is_customized boolean not null default false,
  -- The item was dropped by a later pack version. Kept, because the tenant
  -- may rely on it; the UI can offer to remove it.
  removed_from_pack boolean not null default false,
  sort_order int not null default 0,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.organization_pack_items
add constraint organization_pack_items_pkey primary key (id);

alter table only crm.organization_pack_items
add constraint organization_pack_items_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.organization_pack_items
add constraint organization_pack_items_key
unique (organization_id, kind, item_key);

alter table only crm.organization_pack_items
add constraint organization_pack_items_kind_check
check (kind in (
  'pipeline_stage',
  'custom_field',
  'qualification_question',
  'message_template',
  'compliance',
  'module',
  'terminology'
));
