-- Applying and upgrading vertical packs (P1-05).

-- Flattens a pack definition into (kind, item_key, value, sort_order) rows.
-- Lists are keyed by their item's `key` (`name` for templates); objects
-- (compliance, modules, terminology) by their property names.
create function crm.pack_items(p_definition jsonb)
returns table (kind text, item_key text, value jsonb, sort_order int)
language sql
immutable
set search_path to ''
as $$
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
$$;

-- Applies a pack version to an organization: first application or upgrade.
--
--   * new items are added;
--   * items the tenant has not edited follow the pack;
--   * items the tenant edited keep their value (pack_value still records what
--     the pack now says, so the UI can show "pack changed this");
--   * items the new version dropped are kept and flagged removed_from_pack.
--
-- Internal: called by organization creation, by crm.upgrade_organization_pack
-- and by the platform (service_role).
create function crm.apply_pack(
  p_organization_id uuid,
  p_pack_key text,
  p_version int
) returns void
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

-- The default pack's latest version, applied when an organization is
-- created. A no-op when no pack is published (e.g. mid-migration).
create function crm.apply_default_pack(p_organization_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

-- Tenant-initiated upgrade to a newer version of its pack (latest when
-- p_version is null).
create function crm.upgrade_organization_pack(
  p_organization_id uuid,
  p_version int default null
) returns int
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

-- Undo a tenant edit: the item follows the pack again.
create function crm.reset_pack_item(p_item_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
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
$$;
