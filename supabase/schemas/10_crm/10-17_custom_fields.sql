-- Custom fields (P1-06). Definitions are organization_pack_items of kind
-- custom_field: the pack's fields arrive with the pack (and pack upgrades
-- never overwrite an organization's edits); an organization's own fields are
-- items with no pack_value. Values live in crm.contacts.custom_fields (deals
-- get the same column in Phase 3). Tables: 10-09. Triggers: 10-24.
--
-- A definition (the item's value):
--   {key, entity: contact | deal, type, label: {en, hi?}, required?, archived?,
--    options?: [{value, label: {en, hi?}, archived?}]}
-- Keys and types never change once created. Fields and options are archived,
-- never deleted, so stored values keep displaying.

-- Why a definition is not acceptable, or null.
create function crm.field_definition_error(p_def jsonb) returns text
language plpgsql
immutable
set search_path to ''
as $$
declare
  v_label jsonb := '{"type": "object", "required": ["en"], "additionalProperties": false,
    "properties": {"en": {"type": "string", "minLength": 1, "maxLength": 80},
                   "hi": {"type": "string", "minLength": 1, "maxLength": 80}}}';
  v_error text;
  v_type text := p_def->>'type';
  v_options int := jsonb_array_length(coalesce(p_def->'options', '[]'));
begin
  v_error := crm.validate_setting_value(
    jsonb_build_object(
      'type', 'object',
      'required', jsonb_build_array('key', 'entity', 'type', 'label'),
      'additionalProperties', false,
      'properties', jsonb_build_object(
        'key', jsonb_build_object('type', 'string', 'pattern', '^[a-z][a-z0-9_]{1,39}$'),
        'entity', jsonb_build_object('type', 'string', 'enum', jsonb_build_array('contact', 'deal')),
        'type', jsonb_build_object('type', 'string', 'enum', jsonb_build_array(
          'text', 'long_text', 'number', 'date', 'boolean', 'select',
          'multi_select', 'email', 'phone', 'url')),
        'label', v_label,
        'required', jsonb_build_object('type', 'boolean'),
        'archived', jsonb_build_object('type', 'boolean'),
        'options', jsonb_build_object(
          'type', 'array', 'maxItems', 100,
          'items', jsonb_build_object(
            'type', 'object',
            'required', jsonb_build_array('value', 'label'),
            'additionalProperties', false,
            'properties', jsonb_build_object(
              'value', jsonb_build_object('type', 'string', 'pattern', '^[a-z0-9][a-z0-9_]{0,39}$'),
              'label', v_label,
              'archived', jsonb_build_object('type', 'boolean')))))),
    p_def,
    'field'
  );
  if v_error is not null then
    return v_error;
  end if;

  if v_type in ('select', 'multi_select') and v_options = 0 then
    return 'a choice field needs at least one option';
  end if;
  if v_type not in ('select', 'multi_select') and v_options > 0 then
    return 'only choice fields have options';
  end if;
  if v_options > (
    select count(distinct o->>'value') from jsonb_array_elements(p_def->'options') o
  ) then
    return 'option values must be unique';
  end if;

  return null;
end;
$$;

-- Why a value does not fit its field, or null. p_old is the stored value:
-- an archived option may stay, but cannot be newly chosen.
create function crm.custom_field_value_error(
  p_def jsonb,
  p_value jsonb,
  p_old jsonb default null
) returns text
language plpgsql
immutable
set search_path to ''
as $$
declare
  v_key text := p_def->>'key';
  v_kind text := jsonb_typeof(p_value);
  v_text text := jsonb_build_array(p_value)->>0;
  v_max int;
  v_choice text;
  v_active text[] := array(
    select o->>'value' from jsonb_array_elements(coalesce(p_def->'options', '[]')) o
    where not coalesce((o->>'archived')::boolean, false)
  );
  v_all text[] := array(
    select o->>'value' from jsonb_array_elements(coalesce(p_def->'options', '[]')) o
  );
begin
  case p_def->>'type'
    when 'text', 'long_text' then
      if v_kind <> 'string' then
        return format('%s must be text', v_key);
      end if;
      v_max := 500;
      if p_def->>'type' = 'long_text' then
        v_max := 5000;
      end if;
      if length(v_text) > v_max then
        return format('%s is too long', v_key);
      end if;
    when 'number' then
      if v_kind <> 'number' then
        return format('%s must be a number', v_key);
      end if;
    when 'boolean' then
      if v_kind <> 'boolean' then
        return format('%s must be yes or no', v_key);
      end if;
    when 'date' then
      if v_kind <> 'string' or v_text !~ '^\d{4}-\d{2}-\d{2}$' then
        return format('%s must be a date (YYYY-MM-DD)', v_key);
      end if;
      begin
        perform v_text::date;
      exception when others then
        return format('%s must be a date (YYYY-MM-DD)', v_key);
      end;
    when 'email' then
      if v_kind <> 'string' or v_text !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
        return format('%s must be an email address', v_key);
      end if;
    when 'phone' then
      if v_kind <> 'string' or v_text !~ '^\+?[0-9][0-9 ()-]{6,19}$' then
        return format('%s must be a phone number', v_key);
      end if;
    when 'url' then
      if v_kind <> 'string' or v_text !~ '^https?://\S{3,500}$' then
        return format('%s must be a web address starting with http:// or https://', v_key);
      end if;
    when 'select' then
      if v_kind <> 'string' or not v_text = any(v_all) then
        return format('%s: unknown option %s', v_key, coalesce(v_text, ''));
      end if;
      if not v_text = any(v_active) and p_old is distinct from p_value then
        return format('%s: option %s is archived', v_key, v_text);
      end if;
    when 'multi_select' then
      if v_kind <> 'array' then
        return format('%s must be a list of options', v_key);
      end if;
      if jsonb_array_length(p_value) > (
        select count(distinct e) from jsonb_array_elements_text(p_value) e
      ) then
        return format('%s lists an option twice', v_key);
      end if;
      for v_choice in select * from jsonb_array_elements_text(p_value) loop
        if not v_choice = any(v_all) then
          return format('%s: unknown option %s', v_key, v_choice);
        end if;
        if not v_choice = any(v_active)
          and not coalesce(p_old @> to_jsonb(array[v_choice]), false) then
          return format('%s: option %s is archived', v_key, v_choice);
        end if;
      end loop;
    else
      return format('%s has an unknown type', v_key);
  end case;

  return null;
end;
$$;

-- The organization's definition of one field, or null. Internal.
create function crm.custom_field_definition(
  p_organization_id uuid,
  p_entity text,
  p_key text
) returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  select i.value
  from crm.organization_pack_items i
  where i.organization_id = p_organization_id
    and i.kind = 'custom_field'
    and i.item_key = p_key
    and i.value->>'entity' = p_entity;
$$;

-- Defining fields (organization.manage) ------------------------------------------

create function crm.create_custom_field(
  p_organization_id uuid,
  p_entity text,
  p_key text,
  p_type text,
  p_label jsonb,
  p_options jsonb default '[]'::jsonb,
  p_required boolean default false
) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_def jsonb := jsonb_build_object(
    'key', p_key, 'entity', p_entity, 'type', p_type, 'label', p_label,
    'required', coalesce(p_required, false)
  );
  v_error text;
  v_id uuid;
begin
  perform crm.require_permission(p_organization_id, 'organization.manage');

  if jsonb_array_length(coalesce(p_options, '[]')) > 0 then
    v_def := v_def || jsonb_build_object('options', p_options);
  end if;
  v_error := crm.field_definition_error(v_def);
  if v_error is not null then
    raise exception '%', v_error using errcode = '22023';
  end if;

  if exists (
    select 1 from crm.organization_pack_items i
    where i.organization_id = p_organization_id
      and i.kind = 'custom_field'
      and i.item_key = p_key
  ) then
    raise exception 'a field with the key % already exists', p_key
      using errcode = '23505';
  end if;

  insert into crm.organization_pack_items (
    organization_id, kind, item_key, value, pack_value, pack_version, sort_order
  ) values (
    p_organization_id, 'custom_field', p_key, v_def, null,
    coalesce((select op.version from crm.organization_packs op
              where op.organization_id = p_organization_id), 0),
    coalesce((select max(i.sort_order) + 1 from crm.organization_pack_items i
              where i.organization_id = p_organization_id
                and i.kind = 'custom_field'), 1)
  )
  returning id into v_id;

  perform crm.write_audit(
    p_organization_id, 'custom_field.created', 'custom_field', p_key,
    jsonb_build_object('entity', p_entity, 'type', p_type, 'label', p_label->>'en')
  );

  return v_id;
end;
$$;

-- Changes a field's labels, options and required flag. Options can be added
-- and archived, never removed (stored values may use them).
create function crm.update_custom_field(
  p_field_id uuid,
  p_label jsonb,
  p_options jsonb,
  p_required boolean
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_item crm.organization_pack_items;
  v_def jsonb;
  v_error text;
begin
  select * into v_item from crm.organization_pack_items i
  where i.id = p_field_id and i.kind = 'custom_field';
  if not found then
    raise exception 'field not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_item.organization_id, 'organization.manage');

  if exists (
    select 1 from jsonb_array_elements(coalesce(v_item.value->'options', '[]')) old_o
    where not exists (
      select 1 from jsonb_array_elements(coalesce(p_options, '[]')) new_o
      where new_o->>'value' = old_o->>'value'
    )
  ) then
    raise exception 'options cannot be removed; archive them instead'
      using errcode = '22023';
  end if;

  v_def := v_item.value - 'options'
    || jsonb_build_object('label', p_label, 'required', coalesce(p_required, false));
  if jsonb_array_length(coalesce(p_options, '[]')) > 0 then
    v_def := v_def || jsonb_build_object('options', p_options);
  end if;
  v_error := crm.field_definition_error(v_def);
  if v_error is not null then
    raise exception '%', v_error using errcode = '22023';
  end if;

  -- Audited by the pack item trigger (custom_field.updated).
  if v_def is distinct from v_item.value then
    update crm.organization_pack_items set value = v_def where id = p_field_id;
  end if;
end;
$$;

-- Archives (or restores) a field: hidden from forms and filters, values kept.
create function crm.archive_custom_field(
  p_field_id uuid,
  p_archived boolean default true
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_item crm.organization_pack_items;
begin
  select * into v_item from crm.organization_pack_items i
  where i.id = p_field_id and i.kind = 'custom_field';
  if not found then
    raise exception 'field not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_item.organization_id, 'organization.manage');

  if coalesce((v_item.value->>'archived')::boolean, false) = p_archived then
    return;
  end if;

  update crm.organization_pack_items
  set value = case when p_archived
    then value || '{"archived": true}'::jsonb
    else value - 'archived' end
  where id = p_field_id;
  -- Audited by the pack item trigger (custom_field.archived / restored).
end;
$$;

-- Values ---------------------------------------------------------------------------

-- Saves a contact's field values from the contact form: merges p_values
-- (null or "" clears a field) and enforces the required fields. Runs as the
-- caller, so row level security decides which contacts they can change
-- (contacts.edit and number scope). Contacts created automatically (a first
-- inbound message) are never held to "required".
create function crm.set_contact_fields(p_contact_id uuid, p_values jsonb)
returns jsonb
language plpgsql
set search_path to ''
as $$
declare
  v_contact crm.contacts;
  v_merged jsonb;
  v_missing text;
begin
  select * into v_contact from crm.contacts c where c.id = p_contact_id;
  if not found then
    raise exception 'contact not found' using errcode = 'P0002';
  end if;
  if not crm.has_permission(v_contact.organization_id, 'contacts.edit') then
    raise exception 'permission contacts.edit required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_values) is distinct from 'object' then
    raise exception 'values must be an object' using errcode = '22023';
  end if;

  v_merged := crm.clean_custom_fields(v_contact.custom_fields || p_values);

  select string_agg(d.value->'label'->>'en', ', ' order by d.sort_order)
  into v_missing
  from crm.organization_pack_items d
  where d.organization_id = v_contact.organization_id
    and d.kind = 'custom_field'
    and d.value->>'entity' = 'contact'
    and coalesce((d.value->>'required')::boolean, false)
    and not coalesce((d.value->>'archived')::boolean, false)
    and not v_merged ? d.item_key;
  if v_missing is not null then
    raise exception 'required: %', v_missing using errcode = '22023';
  end if;

  update crm.contacts set custom_fields = v_merged
  where id = p_contact_id
  returning * into v_contact;
  if not found then
    raise exception 'contact not found' using errcode = 'P0002';
  end if;

  return v_contact.custom_fields;
end;
$$;

-- Drops cleared fields: null, "" and [] mean "no value".
create function crm.clean_custom_fields(p_values jsonb) returns jsonb
language sql
immutable
set search_path to ''
as $$
  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)
  from jsonb_each(coalesce(p_values, '{}'::jsonb)) as e(k, v)
  where v not in ('null'::jsonb, '""'::jsonb, '[]'::jsonb);
$$;

-- Filtering ------------------------------------------------------------------------

-- Whether stored values match one condition {field, op, value}:
--   eq, neq, in (value: list), contains (text: substring, any case; list
--   fields: has the option), gt, gte, lt, lte (numbers; dates as text),
--   is_empty, is_not_empty.
create function crm.custom_field_matches(p_values jsonb, p_condition jsonb)
returns boolean
language plpgsql
immutable
set search_path to ''
as $$
declare
  v jsonb := p_values->(p_condition->>'field');
  c jsonb := p_condition->'value';
  v_op text := p_condition->>'op';
begin
  if v_op = 'is_empty' then
    return v is null;
  elsif v_op = 'is_not_empty' then
    return v is not null;
  elsif v is null then
    return v_op = 'neq';
  end if;

  case v_op
    when 'eq' then return v = c;
    when 'neq' then return v <> c;
    when 'in' then
      return case when jsonb_typeof(v) = 'array'
        then exists (select 1 from jsonb_array_elements(v) e where c @> jsonb_build_array(e))
        else c @> jsonb_build_array(v) end;
    when 'contains' then
      return case when jsonb_typeof(v) = 'array'
        then v @> jsonb_build_array(c)
        else strpos(lower(jsonb_build_array(v)->>0), lower(jsonb_build_array(c)->>0)) > 0 end;
    when 'gt', 'gte', 'lt', 'lte' then
      if jsonb_typeof(v) = 'number' and jsonb_typeof(c) = 'number' then
        return case v_op
          when 'gt' then (jsonb_build_array(v)->>0)::numeric > (jsonb_build_array(c)->>0)::numeric
          when 'gte' then (jsonb_build_array(v)->>0)::numeric >= (jsonb_build_array(c)->>0)::numeric
          when 'lt' then (jsonb_build_array(v)->>0)::numeric < (jsonb_build_array(c)->>0)::numeric
          else (jsonb_build_array(v)->>0)::numeric <= (jsonb_build_array(c)->>0)::numeric end;
      end if;
      return case v_op
        when 'gt' then (jsonb_build_array(v)->>0) > (jsonb_build_array(c)->>0)
        when 'gte' then (jsonb_build_array(v)->>0) >= (jsonb_build_array(c)->>0)
        when 'lt' then (jsonb_build_array(v)->>0) < (jsonb_build_array(c)->>0)
        else (jsonb_build_array(v)->>0) <= (jsonb_build_array(c)->>0) end;
    else
      raise exception 'unknown filter operator %', v_op using errcode = '22023';
  end case;
end;
$$;

-- Contacts whose fields match every condition (AND), newest first. Runs as
-- the caller: row level security limits it to contacts they may see. The
-- base of segments (P4-03).
create function crm.filter_contacts(
  p_organization_id uuid,
  p_conditions jsonb default '[]'::jsonb,
  p_limit int default 100,
  p_offset int default 0
) returns setof crm.contacts
language plpgsql
stable
set search_path to ''
as $$
declare
  v_condition jsonb;
  v_equal jsonb := '{}'::jsonb;
begin
  if jsonb_typeof(p_conditions) is distinct from 'array' then
    raise exception 'conditions must be a list' using errcode = '22023';
  end if;

  for v_condition in select * from jsonb_array_elements(p_conditions) loop
    if not exists (
      select 1 from crm.organization_pack_items i
      where i.organization_id = p_organization_id
        and i.kind = 'custom_field'
        and i.item_key = v_condition->>'field'
        and i.value->>'entity' = 'contact'
    ) then
      raise exception 'unknown field %', v_condition->>'field' using errcode = '22023';
    end if;
    if (v_condition->>'op') not in (
      'eq', 'neq', 'in', 'contains', 'gt', 'gte', 'lt', 'lte', 'is_empty', 'is_not_empty'
    ) then
      raise exception 'unknown filter operator %', v_condition->>'op' using errcode = '22023';
    end if;
    if v_condition->>'op' = 'eq' then
      v_equal := v_equal || jsonb_build_object(v_condition->>'field', v_condition->'value');
    end if;
  end loop;

  return query
  select c.*
  from crm.contacts c
  where c.organization_id = p_organization_id
    -- Equality conditions use the GIN index.
    and c.custom_fields @> v_equal
    and not exists (
      select 1 from jsonb_array_elements(p_conditions) cond
      where not crm.custom_field_matches(c.custom_fields, cond)
    )
  order by c.created_at desc, c.id
  limit least(greatest(coalesce(p_limit, 100), 1), 1000)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

-- Templates ------------------------------------------------------------------------

-- A stored value as people read it, e.g. capital_range "between_2l_10l" →
-- "₹2 lakh – ₹10 lakh". Labels in p_locale, falling back to English. For
-- message templates ({{contact.capital_range}}) and exports.
create function crm.format_custom_field(
  p_organization_id uuid,
  p_entity text,
  p_key text,
  p_value jsonb,
  p_locale text default 'en'
) returns text
language plpgsql
stable
set search_path to ''
as $$
declare
  v_def jsonb;
  v_locale text := coalesce(nullif(p_locale, ''), 'en');
begin
  if p_value is null or p_value = 'null'::jsonb then
    return '';
  end if;

  select i.value into v_def
  from crm.organization_pack_items i
  where i.organization_id = p_organization_id
    and i.kind = 'custom_field'
    and i.item_key = p_key
    and i.value->>'entity' = p_entity;

  case v_def->>'type'
    when 'select', 'multi_select' then
      return (
        select string_agg(
          coalesce(o->'label'->>v_locale, o->'label'->>'en', chosen),
          ', ' order by ord
        )
        from jsonb_array_elements_text(
          case when jsonb_typeof(p_value) = 'array' then p_value else jsonb_build_array(p_value) end
        ) with ordinality as x(chosen, ord)
        left join lateral (
          select o from jsonb_array_elements(v_def->'options') o
          where o->>'value' = chosen
        ) opt on true
      );
    when 'boolean' then
      return case
        when v_locale = 'hi' then case when p_value = 'true'::jsonb then 'हाँ' else 'नहीं' end
        else case when p_value = 'true'::jsonb then 'Yes' else 'No' end
      end;
    else
      return jsonb_build_array(p_value)->>0;
  end case;
end;
$$;
